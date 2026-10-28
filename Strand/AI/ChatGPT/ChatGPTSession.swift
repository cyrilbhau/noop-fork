import Combine
import Foundation

enum ChatGPTSessionState: Equatable {
    case signedOut, authorizing, signedInWithoutPlanPermission, ready, refreshing
    case reauthorizationRequired, unavailable, usageLimited
}

@MainActor
final class ChatGPTSession: ObservableObject {
    @Published private(set) var state: ChatGPTSessionState = .signedOut
    @Published private(set) var lastError: String?
    @Published private(set) var profiles: [ChatGPTProfile] = []
    @Published private(set) var activeProfileID: String?
    @Published private(set) var requestGeneration: UInt64 = 0
    var activeProfile: ChatGPTProfile? { profiles.first { $0.id == activeProfileID } }

    private let session: URLSession
    private let store: any ChatGPTCredentialStoring
    private let verifier: any ChatGPTIDTokenVerifying
    private let discovery: ChatGPTIDTokenVerifier
    private let now: () -> Date
    private var saved: ChatGPTStoredState?
    private var needsPersistence = false
    private var pendingAttempt: UUID?
    private struct RefreshFlight {
        let id: UUID
        let task: Task<String, Error>
    }
    private var refreshTasks: [String: RefreshFlight] = [:]
    private var disconnecting = false

    init(session: URLSession = ChatGPTAuth.makeURLSession(), store: (any ChatGPTCredentialStoring)? = nil,
         now: @escaping () -> Date = Date.init, verifier: (any ChatGPTIDTokenVerifying)? = nil) {
        self.session = session
        self.store = store ?? ChatGPTCredentialStore()
        self.now = now
        let actualVerifier = ChatGPTIDTokenVerifier(session: session, now: now)
        self.discovery = actualVerifier
        self.verifier = verifier ?? actualVerifier
        do { try ensureStorage(); publish() }
        catch { state = .unavailable; lastError = ChatGPTAuthError.persistenceFailed.localizedDescription }
    }

    func prepareAuthorization(redirectURI: URL, profileID: String? = nil, requestConsent: Bool = false) throws -> ChatGPTAuthorizationAttempt {
        guard pendingAttempt == nil, refreshTasks.isEmpty, !disconnecting else { throw ChatGPTAuthError.busy }
        try ensureStorage()
        guard let saved else { throw ChatGPTAuthError.persistenceFailed }
        let registration = profileID.flatMap { id in saved.registrations.first { $0.profile.id == id } }
        if profileID != nil && registration == nil { throw ChatGPTAuthError.signInRequired }
        let attempt = try ChatGPTAuth.makeAttempt(redirectURI: redirectURI, hostID: saved.hostID,
                                                 profile: registration?.profile,
                                                 retainedIDToken: registration?.tokens?.idToken ?? registration?.identityOnlyIDToken,
                                                 pendingClientID: profileID == nil ? saved.pendingClientID : nil,
                                                 requestConsent: requestConsent, now: now())
        invalidateRequests()
        pendingAttempt = attempt.id
        state = .authorizing
        lastError = nil
        return attempt
    }

    func completeAuthorization(attempt: ChatGPTAuthorizationAttempt, callback: ChatGPTAuthorizationCallback) async throws {
        guard pendingAttempt == attempt.id, !disconnecting, !Task.isCancelled,
              now().timeIntervalSince(attempt.createdAt) < 600,
              callback.clientID.hasPrefix("oaiapp_"), !callback.code.isEmpty,
              attempt.clientID == ChatGPTAuth.dynamicClientID || attempt.clientID == callback.clientID else {
            throw ChatGPTAuthError.cancelled
        }
        let generation = requestGeneration
        do {
            guard var record = saved else { throw ChatGPTAuthError.persistenceFailed }
            if attempt.profileID == nil { record.pendingClientID = callback.clientID; try commit(record) }
            let response = try await requestTokens(fields: ["grant_type": "authorization_code", "client_id": callback.clientID,
                                                          "code": callback.code, "code_verifier": attempt.verifier,
                                                          "redirect_uri": attempt.redirectURI.absoluteString,
                                                          "resource": ChatGPTAuth.resource])
            let receivedAt = now()
            let tokens = try response.optionalTokens(at: receivedAt)
            guard pendingAttempt == attempt.id, generation == requestGeneration, !disconnecting, !Task.isCancelled else {
                if let tokens { await revokeQuietly(tokens: tokens, clientID: callback.clientID) }
                throw ChatGPTAuthError.cancelled
            }
            guard let idToken = response.idToken else {
                if let tokens { await revokeQuietly(tokens: tokens, clientID: callback.clientID) }
                throw ChatGPTAuthError.invalidIdentity
            }
            let old = attempt.profileID.flatMap { id in saved?.registrations.first { $0.profile.id == id } }
            let identity: ChatGPTIdentity
            do {
                identity = try await verifier.verify(idToken, clientID: callback.clientID, nonce: attempt.nonce,
                                                     expectedSubject: old?.profile.subject, receivedAt: receivedAt)
            } catch {
                if let tokens { await revokeQuietly(tokens: tokens, clientID: callback.clientID) }
                throw error
            }
            guard pendingAttempt == attempt.id, generation == requestGeneration, !disconnecting, !Task.isCancelled else {
                if let tokens { await revokeQuietly(tokens: tokens, clientID: callback.clientID) }
                throw ChatGPTAuthError.cancelled
            }
            guard var latest = saved else { throw ChatGPTAuthError.persistenceFailed }
            let profile = ChatGPTProfile(id: old?.profile.id ?? UUID().uuidString, clientID: callback.clientID,
                                         issuer: identity.issuer, subject: identity.subject, email: identity.email,
                                         name: identity.name, label: old?.profile.label ?? "Connection \(latest.registrations.count + 1)")
            latest.registrations.removeAll { $0.profile.id == profile.id }
            var registration = ChatGPTRegistration(profile: profile, tokens: tokens, pendingRefresh: nil)
            if tokens == nil {
                registration.identityOnlyIDToken = idToken
                registration.identityOnlyScopes = Set((response.scope ?? "").split(whereSeparator: { $0.isWhitespace }).map(String.init))
            }
            latest.registrations.append(registration)
            latest.activeProfileID = profile.id
            latest.pendingClientID = nil
            try commit(latest)
            pendingAttempt = nil
            publish()
        } catch {
            if generation == requestGeneration {
                pendingAttempt = nil
                publish()
                lastError = safeMessage(error)
            }
            throw error
        }
    }

    func cancelAuthorization() {
        pendingAttempt = nil
        invalidateRequests()
        if !disconnecting { publish() }
    }

    func invalidateRequests() { requestGeneration &+= 1 }

    // A Keychain read before first unlock may fail without exposing an active
    // profile. Let the next foreground action recover it without browser sign-in.
    func retryStorageIfUnavailable() {
        guard state == .unavailable, pendingAttempt == nil, !disconnecting, refreshTasks.isEmpty else { return }
        do {
            try ensureStorage()
            publish()
        } catch {
            state = .unavailable
            lastError = ChatGPTAuthError.persistenceFailed.localizedDescription
        }
    }

    // Request outcomes affect the visible connection state, never the credential
    // grant. A rejected inference request alone does not establish revocation.
    func reportRequestFailure(_ error: ChatGPTRequestError, profileID: String, generation: UInt64) {
        guard generation == requestGeneration, profileID == saved?.activeProfileID,
              !disconnecting, pendingAttempt == nil, !needsPersistence,
              saved?.registrations.contains(where: { $0.profile.id == profileID && $0.tokens != nil }) == true else { return }
        switch error.kind {
        case .auth: state = .reauthorizationRequired
        case .usage: state = .usageLimited
        case .permission, .model, .server, .stream: break
        }
        lastError = error.localizedDescription
    }

    func reportRequestSuccess(profileID: String, generation: UInt64) {
        guard generation == requestGeneration, profileID == saved?.activeProfileID,
              !disconnecting, pendingAttempt == nil, !needsPersistence,
              let registration = saved?.registrations.first(where: { $0.profile.id == profileID }),
              registration.pendingRefresh == nil,
              registration.tokens?.scopes.contains(ChatGPTAuth.planScope) == true else { return }
        state = refreshTasks[profileID] == nil ? .ready : .refreshing
        lastError = nil
    }

    func selectProfile(_ profileID: String) throws {
        guard !disconnecting, pendingAttempt == nil, refreshTasks.isEmpty else { throw ChatGPTAuthError.busy }
        try ensureStorage()
        guard var latest = saved, latest.registrations.contains(where: { $0.profile.id == profileID }) else { throw ChatGPTAuthError.signInRequired }
        invalidateRequests()
        latest.activeProfileID = profileID
        try commit(latest)
        publish()
    }

    func validAccessToken(profileID: String? = nil, forceRefresh: Bool = false) async throws -> String {
        guard !disconnecting, pendingAttempt == nil else { throw ChatGPTAuthError.busy }
        try Task.checkCancellation()
        try ensureStorage()
        guard let id = profileID ?? saved?.activeProfileID,
              let registration = saved?.registrations.first(where: { $0.profile.id == id }) else { throw ChatGPTAuthError.signInRequired }
        guard let tokens = registration.tokens else {
            throw registration.identityOnlyIDToken == nil ? ChatGPTAuthError.signInRequired : ChatGPTAuthError.planPermissionRequired
        }
        guard tokens.scopes.contains(ChatGPTAuth.planScope) else { throw ChatGPTAuthError.planPermissionRequired }
        let generation = requestGeneration
        let needsRefresh = registration.pendingRefresh != nil || forceRefresh || tokens.expiresAt <= now().addingTimeInterval(60)
        if !needsRefresh { return tokens.accessToken }
        if registration.pendingRefresh == nil, let hint = tokens.earliestRefreshAt {
            guard let earliest = hint.date else { throw ChatGPTAuthError.refreshNotReady }
            if earliest > now() {
                if tokens.expiresAt > now(), !forceRefresh { return tokens.accessToken }
                throw ChatGPTAuthError.refreshNotReady
            }
        }
        if refreshTasks[id] == nil {
            // An unstructured task finishes checkpointing remote rotation even when a
            // caller is cancelled. Disconnect drains it before revoking its successor.
            refreshTasks[id] = RefreshFlight(id: UUID(), task: Task { @MainActor in try await self.performRefresh(profileID: id) })
        }
        let flight = refreshTasks[id]!
        do {
            let token = try await flight.task.value
            if refreshTasks[id]?.id == flight.id { refreshTasks[id] = nil }
            try Task.checkCancellation()
            guard generation == requestGeneration, !disconnecting else { throw ChatGPTAuthError.cancelled }
            return token
        } catch {
            if refreshTasks[id]?.id == flight.id { refreshTasks[id] = nil }
            if generation == requestGeneration, !disconnecting { lastError = safeMessage(error) }
            throw error
        }
    }

    func disconnect() async {
        guard !disconnecting else { return }
        guard saved != nil else {
            state = .unavailable
            lastError = ChatGPTAuthError.persistenceFailed.localizedDescription
            return
        }
        disconnecting = true
        pendingAttempt = nil
        invalidateRequests()
        state = .signedOut
        // A cancelled network request might already have rotated its grant. Finish
        // receiving it, then revoke the newest token instead of the consumed one.
        for flight in Array(refreshTasks.values) { _ = try? await flight.task.value }
        refreshTasks.removeAll()
        var remoteConfirmed = true
        var localConfirmed = true
        if let id = saved?.activeProfileID,
           let registration = saved?.registrations.first(where: { $0.profile.id == id }) {
            if let tokens = registration.pendingRefresh ?? registration.tokens {
                remoteConfirmed = await revokeQuietly(tokens: tokens, clientID: registration.profile.clientID)
            }
            if var latest = saved, let index = latest.registrations.firstIndex(where: { $0.profile.id == id }) {
                latest.registrations[index].tokens = nil
                latest.registrations[index].pendingRefresh = nil
                latest.registrations[index].identityOnlyIDToken = nil
                latest.registrations[index].identityOnlyScopes = nil
                do { try commit(latest) }
                catch { localConfirmed = false }
            }
        }
        disconnecting = false
        publish()
        if !localConfirmed {
            lastError = "ChatGPT requests are stopped, but saved credentials could not be cleared. Unlock the phone and retry disconnecting."
        } else if !remoteConfirmed {
            lastError = "Local credentials were cleared, but remote disconnection was not confirmed. Disconnect Noop in ChatGPT Settings."
        }
    }

    private func performRefresh(profileID: String) async throws -> String {
        guard var registration = saved?.registrations.first(where: { $0.profile.id == profileID }),
              let previous = registration.tokens else { throw ChatGPTAuthError.signInRequired }
        if !disconnecting { state = .refreshing }
        do {
            var rotation = registration.pendingRefresh
            if rotation == nil {
                guard let refreshToken = previous.refreshToken else { throw ChatGPTAuthError.signInRequired }
                let response = try await requestTokens(fields: ["grant_type": "refresh_token", "client_id": registration.profile.clientID,
                                                              "refresh_token": refreshToken, "resource": ChatGPTAuth.resource])
                do { rotation = try response.tokens(at: now(), prior: previous) }
                catch {
                    // A 200 with malformed replacement fields cannot safely replay
                    // the old rotating grant. Stop using it and require reconnect.
                    try clearTokens(profileID: profileID)
                    throw error
                }
                registration.pendingRefresh = rotation
                try replace(registration)
            }
            guard let rotation else { throw ChatGPTAuthError.invalidTokenResponse }
            if let idToken = rotation.idToken, rotation.requiresIdentityVerification ?? (idToken != previous.idToken) {
                let identity = try await verifier.verify(idToken, clientID: registration.profile.clientID, nonce: nil,
                                                         expectedSubject: registration.profile.subject, receivedAt: rotation.receivedAt)
                registration.profile.email = identity.email
                registration.profile.name = identity.name
            }
            registration.tokens = rotation
            registration.pendingRefresh = nil
            try replace(registration)
            if !disconnecting { publish() }
            guard rotation.scopes.contains(ChatGPTAuth.planScope) else { throw ChatGPTAuthError.planPermissionRequired }
            guard rotation.expiresAt > now() else { throw ChatGPTAuthError.refreshNotReady }
            return rotation.accessToken
        } catch {
            if let auth = error as? ChatGPTAuthError,
               auth.isTerminalRefresh || (auth.isInvalidIdentity) {
                try? clearTokens(profileID: profileID)
                if !disconnecting { state = .reauthorizationRequired }
            } else if !disconnecting {
                if case ChatGPTAuthError.planPermissionRequired = error { publish() }
                else if case ChatGPTAuthError.signInRequired = error { state = .reauthorizationRequired }
                else { state = .unavailable }
            }
            throw error
        }
    }

    private func requestTokens(fields: [String: String]) async throws -> ChatGPTTokenResponse {
        let request = ChatGPTAuth.formRequest(url: ChatGPTAuth.tokenEndpoint, fields: fields)
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, response.url == request.url,
              data.count <= 1_000_000 else { throw ChatGPTAuthError.invalidTokenResponse }
        guard http.statusCode == 200 else { throw ChatGPTAuth.remoteError(data: data, response: http) }
        guard let decoded = try? JSONDecoder().decode(ChatGPTTokenResponse.self, from: data) else {
            throw ChatGPTAuthError.invalidTokenResponse
        }
        return decoded
    }

    @discardableResult
    private func revokeQuietly(tokens: ChatGPTTokens, clientID: String) async -> Bool {
        guard let token = tokens.refreshToken else { return false }
        guard let config = try? await discovery.configuration(), let endpoint = config.revocationEndpoint else { return false }
        for attempt in 0..<2 {
            do {
                let request = ChatGPTAuth.formRequest(url: endpoint, fields: ["token": token, "token_type_hint": "refresh_token", "client_id": clientID])
                let (_, response) = try await session.data(for: request)
                if let http = response as? HTTPURLResponse, response.url == endpoint {
                    if http.statusCode == 200 { return true }
                    if http.statusCode < 500 { return false }
                }
            } catch { /* A single bounded retry retains the token until revocation finishes. */ }
            if attempt == 0 { try? await Task.sleep(nanoseconds: 300_000_000) }
        }
        return false
    }

    private func ensureStorage() throws {
        if saved == nil {
            if let loaded = try store.load() { saved = loaded }
            else { try commit(ChatGPTStoredState(hostID: "urn:uuid:" + UUID().uuidString.lowercased())) }
        }
        if needsPersistence, let saved { try commit(saved); publish() }
    }

    private func commit(_ candidate: ChatGPTStoredState) throws {
        // Keep the successor in memory on a failed write; never return to the
        // consumed persisted refresh token while this process can recover it.
        saved = candidate
        do { try store.save(candidate); needsPersistence = false }
        catch { needsPersistence = true; state = .unavailable; throw ChatGPTAuthError.persistenceFailed }
    }

    private func replace(_ registration: ChatGPTRegistration) throws {
        guard var latest = saved, let index = latest.registrations.firstIndex(where: { $0.profile.id == registration.profile.id }) else {
            throw ChatGPTAuthError.cancelled
        }
        latest.registrations[index] = registration
        try commit(latest)
    }

    private func clearTokens(profileID: String) throws {
        guard var latest = saved, let index = latest.registrations.firstIndex(where: { $0.profile.id == profileID }) else { return }
        latest.registrations[index].tokens = nil
        latest.registrations[index].pendingRefresh = nil
        try commit(latest)
    }

    private func publish() {
        // A failed secure write cannot activate a new profile in the UI. The
        // private candidate is retained only to recover the exact replacement.
        if needsPersistence { state = .unavailable; return }
        profiles = saved?.registrations.map(\.profile) ?? []
        activeProfileID = saved?.activeProfileID
        guard let registration = saved?.registrations.first(where: { $0.profile.id == activeProfileID }) else { state = .signedOut; return }
        guard let tokens = registration.tokens else {
            state = registration.identityOnlyIDToken == nil ? .signedOut : .signedInWithoutPlanPermission
            return
        }
        state = tokens.scopes.contains(ChatGPTAuth.planScope) ? .ready : .signedInWithoutPlanPermission
        if registration.pendingRefresh != nil { state = .unavailable }
        lastError = nil
    }

    private func safeMessage(_ error: Error) -> String {
        (error as? ChatGPTAuthError)?.localizedDescription ?? "The ChatGPT connection is temporarily unavailable. Try again."
    }
}

private extension ChatGPTAuthError {
    var isInvalidIdentity: Bool {
        switch self { case .invalidIdentity, .invalidTokenResponse: return true; default: return false }
    }
}
