import Foundation
import XCTest
@testable import Strand

@MainActor
final class ChatGPTSessionTests: XCTestCase {
    private let date = Date(timeIntervalSince1970: 1_800_000_000)

    func testUnreadableKeychainIsNeverReplacedWithEmptyState() throws {
        let store = ChatGPTMemoryStore()
        store.failLoad = true
        let client = ChatGPTSession(store: store)
        XCTAssertEqual(client.state, .unavailable)
        XCTAssertThrowsError(try client.prepareAuthorization(redirectURI: redirect))
        XCTAssertEqual(store.saveCount, 0)
    }

    func testStorageRetryAfterUnlockRecoversSavedConnectionWithoutNetworkOrBrowser() async throws {
        let store = ChatGPTMemoryStore(value: seed(expired: false))
        store.failLoad = true
        let counts = ChatGPTLockedCounts()
        let session = ChatGPTTestURLProtocol.session { _ in counts.increment("unexpected"); return (200, Self.response()) }
        let client = ChatGPTSession(session: session, store: store, now: { self.date }, verifier: ChatGPTStubVerifier())
        XCTAssertEqual(client.state, .unavailable)
        XCTAssertNil(client.activeProfileID)
        client.retryStorageIfUnavailable()
        XCTAssertEqual(client.state, .unavailable)
        XCTAssertEqual(store.saveCount, 0)

        store.failLoad = false
        client.retryStorageIfUnavailable()
        XCTAssertEqual(client.state, .ready)
        XCTAssertEqual(client.activeProfileID, "profile")
        let token = try await client.validAccessToken()
        XCTAssertEqual(token, "access-old")
        XCTAssertEqual(counts.value("unexpected"), 0)
        XCTAssertEqual(store.saveCount, 0, "Recovering a readable record must not create or overwrite registration")

        let generation = client.requestGeneration
        client.reportRequestFailure(.init(kind: .usage, status: 429), profileID: "profile", generation: generation)
        client.retryStorageIfUnavailable()
        XCTAssertEqual(client.state, .usageLimited)
        client.reportRequestFailure(.init(kind: .auth, status: 401), profileID: "profile", generation: generation)
        client.retryStorageIfUnavailable()
        XCTAssertEqual(client.state, .reauthorizationRequired)
    }

    func testRegistrationIsSavedBeforeCodeExchangeAndVerifiedBeforeActivation() async throws {
        let store = ChatGPTMemoryStore()
        let verifier = ChatGPTStubVerifier()
        let session = ChatGPTTestURLProtocol.session { request in
            let fields = ChatGPTTestURLProtocol.body(request)
            XCTAssertTrue(fields.contains("grant_type=authorization_code"))
            XCTAssertTrue(fields.contains("client_id=oaiapp_new"))
            return (200, Self.response(idToken: "verified-id"))
        }
        let client = ChatGPTSession(session: session, store: store, now: { self.date }, verifier: verifier)
        let attempt = try client.prepareAuthorization(redirectURI: redirect)
        try await client.completeAuthorization(attempt: attempt, callback: .init(code: "one-time-code", clientID: "oaiapp_new"))
        XCTAssertEqual(verifier.calls, 1)
        XCTAssertEqual(client.activeProfile?.subject, "subject")
        XCTAssertEqual(client.state, .ready)
        XCTAssertNil(store.value?.pendingClientID)
        let accessToken = try await client.validAccessToken()
        XCTAssertEqual(accessToken, "access-new")
        XCTAssertTrue(store.history.dropLast().contains { $0.pendingClientID == "oaiapp_new" && $0.activeProfileID == nil })
        client.cancelAuthorization()
        do {
            try await client.completeAuthorization(attempt: attempt, callback: .init(code: "duplicate", clientID: "oaiapp_new"))
            XCTFail("A consumed callback must not be accepted")
        } catch { XCTAssertTrue(error is ChatGPTAuthError) }
    }

    func testConcurrentRefreshUsesOneRotationAndSignoutRevokesItsSuccessor() async throws {
        let store = ChatGPTMemoryStore(value: seed())
        let started = expectation(description: "refresh received")
        let gate = DispatchSemaphore(value: 0)
        let counts = ChatGPTLockedCounts()
        let session = ChatGPTTestURLProtocol.session { request in
            if request.url == ChatGPTAuth.discoveryURL { return (200, ChatGPTTestURLProtocol.discovery) }
            let body = ChatGPTTestURLProtocol.body(request)
            if body.contains("grant_type=refresh_token") {
                counts.increment("refresh")
                started.fulfill()
                _ = gate.wait(timeout: .now() + 5)
                return (200, Self.response())
            }
            XCTAssertTrue(body.contains("token=refresh-new"), "Signout must revoke the rotated successor")
            counts.increment("revoke")
            return (200, Data())
        }
        let client = ChatGPTSession(session: session, store: store, now: { self.date }, verifier: ChatGPTStubVerifier())
        let first = Task { try await client.validAccessToken() }
        let second = Task { try await client.validAccessToken() }
        await fulfillment(of: [started], timeout: 3)
        let disconnect = Task { await client.disconnect() }
        await Task.yield()
        gate.signal()
        _ = try? await first.value
        _ = try? await second.value
        await disconnect.value
        XCTAssertEqual(counts.value("refresh"), 1)
        XCTAssertEqual(counts.value("revoke"), 1)
        XCTAssertNil(store.value?.registrations.first?.tokens)
        XCTAssertEqual(client.state, .signedOut)
    }

    func testIdentityOnlySuccessIsRetainedWithoutEnablingInference() async throws {
        let store = ChatGPTMemoryStore()
        let session = ChatGPTTestURLProtocol.session { _ in
            (200, Data("{\"id_token\":\"identity-only\",\"scope\":\"openid profile email\"}".utf8))
        }
        let client = ChatGPTSession(session: session, store: store, now: { self.date }, verifier: ChatGPTStubVerifier())
        let attempt = try client.prepareAuthorization(redirectURI: redirect)
        try await client.completeAuthorization(attempt: attempt, callback: .init(code: "code", clientID: "oaiapp_identity"))
        XCTAssertEqual(client.state, .signedInWithoutPlanPermission)
        XCTAssertNotNil(client.activeProfile)
        XCTAssertNil(store.value?.registrations.first?.tokens)
        XCTAssertEqual(store.value?.registrations.first?.identityOnlyIDToken, "identity-only")
        do { _ = try await client.validAccessToken(); XCTFail("Identity alone must never enable inference") }
        catch { guard case ChatGPTAuthError.planPermissionRequired = error else { return XCTFail("Expected missing plan permission") } }
        let resumed = ChatGPTSession(session: session, store: store, now: { self.date }, verifier: ChatGPTStubVerifier())
        XCTAssertEqual(resumed.state, .signedInWithoutPlanPermission)
    }

    func testDisconnectReportsFailedLocalClearAndCanRetryIt() async throws {
        let store = ChatGPTMemoryStore(value: seed(expired: false))
        let session = ChatGPTTestURLProtocol.session { request in
            (200, request.url == ChatGPTAuth.discoveryURL ? ChatGPTTestURLProtocol.discovery : Data())
        }
        let client = ChatGPTSession(session: session, store: store, now: { self.date }, verifier: ChatGPTStubVerifier())
        store.failSaves = 1
        await client.disconnect()
        XCTAssertEqual(client.state, .unavailable)
        XCTAssertTrue(client.lastError?.contains("could not be cleared") == true)
        XCTAssertNotNil(store.value?.registrations.first?.tokens)
        await client.disconnect()
        XCTAssertNil(store.value?.registrations.first?.tokens)
        XCTAssertEqual(client.state, .signedOut)
    }

    func testFailedRotationWriteRecoversSameReplacementWithoutReusingOldGrant() async throws {
        let store = ChatGPTMemoryStore(value: seed())
        let counts = ChatGPTLockedCounts()
        let session = ChatGPTTestURLProtocol.session { _ in counts.increment("refresh"); return (200, Self.response()) }
        let client = ChatGPTSession(session: session, store: store, now: { self.date }, verifier: ChatGPTStubVerifier())
        store.failSaves = 1
        do { _ = try await client.validAccessToken(); XCTFail("A failed secure write must not return a token") }
        catch { XCTAssertEqual(client.state, .unavailable) }
        XCTAssertEqual(counts.value("refresh"), 1)
        let accessToken = try await client.validAccessToken()
        XCTAssertEqual(accessToken, "access-new")
        XCTAssertEqual(counts.value("refresh"), 1)
        XCTAssertEqual(store.value?.registrations.first?.tokens?.refreshToken, "refresh-new")
        XCTAssertEqual(client.state, .ready)
    }

    func testTerminalRefreshClearsTokensButNetworkFailurePreservesThem() async throws {
        for terminal in [true, false] {
            let store = ChatGPTMemoryStore(value: seed())
            let session = ChatGPTTestURLProtocol.session { _ in
                if terminal { return (400, Data("{\"error\":\"invalid_grant\"}".utf8)) }
                throw URLError(.notConnectedToInternet)
            }
            let client = ChatGPTSession(session: session, store: store, now: { self.date }, verifier: ChatGPTStubVerifier())
            do { _ = try await client.validAccessToken(); XCTFail("Refresh should fail") } catch { }
            if terminal {
                XCTAssertNil(store.value?.registrations.first?.tokens)
                XCTAssertEqual(client.state, .reauthorizationRequired)
            } else { XCTAssertEqual(store.value?.registrations.first?.tokens?.refreshToken, "refresh-old") }
            XCTAssertEqual(store.value?.registrations.first?.profile.clientID, "oaiapp_test")
        }
    }

    func testJWKSOutagePreservesCheckpointAndDoesNotReplayRotatedGrant() async throws {
        let store = ChatGPTMemoryStore(value: seed())
        let verifier = ChatGPTStubVerifier()
        verifier.failure = ChatGPTAuthError.identityUnavailable
        let counts = ChatGPTLockedCounts()
        let session = ChatGPTTestURLProtocol.session { _ in counts.increment("refresh"); return (200, Self.response(idToken: "rotated-id")) }
        let client = ChatGPTSession(session: session, store: store, now: { self.date }, verifier: verifier)
        do { _ = try await client.validAccessToken(); XCTFail("Identity verification should fail during outage") } catch { }
        XCTAssertEqual(store.value?.registrations.first?.pendingRefresh?.refreshToken, "refresh-new")
        XCTAssertEqual(client.state, .unavailable)
        verifier.failure = nil
        let token = try await client.validAccessToken()
        XCTAssertEqual(token, "access-new")
        XCTAssertEqual(counts.value("refresh"), 1)
        XCTAssertNil(store.value?.registrations.first?.pendingRefresh)
        XCTAssertEqual(verifier.calls, 2)
    }

    func testEarliestRefreshBlocksForcedRefreshAndExpiredAccess() async throws {
        var value = seed()
        value.registrations[0].tokens?.earliestRefreshAt = .seconds(date.addingTimeInterval(300).timeIntervalSince1970)
        let store = ChatGPTMemoryStore(value: value)
        let counts = ChatGPTLockedCounts()
        let session = ChatGPTTestURLProtocol.session { _ in counts.increment("unexpected"); return (200, Self.response()) }
        let client = ChatGPTSession(session: session, store: store, now: { self.date }, verifier: ChatGPTStubVerifier())
        do { _ = try await client.validAccessToken(forceRefresh: true); XCTFail("Must honor earliest refresh time") }
        catch { XCTAssertTrue(error is ChatGPTAuthError) }
        XCTAssertEqual(counts.value("unexpected"), 0)
    }

    func testExpiredAccessWithoutOfflineGrantRequiresSignInAfterRelaunch() async throws {
        var value = seed()
        value.registrations[0].tokens?.refreshToken = nil
        value.registrations[0].tokens?.scopes = [ChatGPTAuth.planScope]
        let store = ChatGPTMemoryStore(value: value)
        let counts = ChatGPTLockedCounts()
        let session = ChatGPTTestURLProtocol.session { _ in counts.increment("unexpected"); return (200, Self.response()) }
        let client = ChatGPTSession(session: session, store: store, now: { self.date }, verifier: ChatGPTStubVerifier())
        do { _ = try await client.validAccessToken(); XCTFail("Expired access without a refresh grant must require sign-in") }
        catch { guard case ChatGPTAuthError.signInRequired = error else { return XCTFail("Expected sign-in requirement") } }
        XCTAssertEqual(client.state, .reauthorizationRequired)
        XCTAssertEqual(counts.value("unexpected"), 0)
        XCTAssertEqual(store.value?.registrations.first?.profile.clientID, "oaiapp_test")
    }

    func testCancelledAuthorizationCannotReplaceActiveProfile() async throws {
        let store = ChatGPTMemoryStore(value: seed(expired: false))
        let verifier = ChatGPTStubVerifier()
        let session = ChatGPTTestURLProtocol.session { request in
            if request.url == ChatGPTAuth.discoveryURL { return (200, ChatGPTTestURLProtocol.discovery) }
            if request.url?.path.contains("revoke") == true { return (200, Data()) }
            return (200, Self.response(idToken: "new-id"))
        }
        let client = ChatGPTSession(session: session, store: store, now: { self.date }, verifier: verifier)
        verifier.beforeReturn = { client.cancelAuthorization() }
        let attempt = try client.prepareAuthorization(redirectURI: redirect)
        do {
            try await client.completeAuthorization(attempt: attempt, callback: .init(code: "code", clientID: "oaiapp_new"))
            XCTFail("Cancelled authorization must fail")
        } catch { }
        XCTAssertEqual(client.activeProfileID, "profile")
        XCTAssertEqual(store.value?.registrations.count, 1)
    }

    private var redirect: URL { URL(string: "http://127.0.0.1:1455/auth/callback")! }
    private func seed(expired: Bool = true) -> ChatGPTStoredState {
        let profile = ChatGPTProfile(id: "profile", clientID: "oaiapp_test", issuer: ChatGPTAuth.issuer, subject: "subject", email: nil, name: nil, label: "Connection 1")
        let tokens = ChatGPTTokens(accessToken: "access-old", refreshToken: "refresh-old", idToken: "old-id",
                                   expiresAt: date.addingTimeInterval(expired ? -1 : 3600), scopes: [ChatGPTAuth.planScope, "offline_access"], earliestRefreshAt: nil, receivedAt: date.addingTimeInterval(-3600))
        return ChatGPTStoredState(hostID: "urn:uuid:stable-host", registrations: [.init(profile: profile, tokens: tokens, pendingRefresh: nil)], activeProfileID: profile.id)
    }
    nonisolated private static func response(idToken: String? = nil) -> Data {
        var value: [String: Any] = ["access_token": "access-new", "refresh_token": "refresh-new", "token_type": "Bearer", "expires_in": 3600, "scope": "chatgpt.tokens.use.direct offline_access openid profile email resource.invoke"]
        value["id_token"] = idToken
        return try! JSONSerialization.data(withJSONObject: value)
    }
}

@MainActor
private final class ChatGPTMemoryStore: ChatGPTCredentialStoring {
    var value: ChatGPTStoredState?
    var failLoad = false
    var failSaves = 0
    var saveCount = 0
    var history: [ChatGPTStoredState] = []
    init(value: ChatGPTStoredState? = nil) { self.value = value }
    func load() throws -> ChatGPTStoredState? {
        if failLoad { throw ChatGPTAuthError.persistenceFailed }
        return value
    }
    func save(_ value: ChatGPTStoredState) throws {
        saveCount += 1
        if failSaves > 0 { failSaves -= 1; throw ChatGPTAuthError.persistenceFailed }
        self.value = value
        history.append(value)
    }
}

@MainActor
private final class ChatGPTStubVerifier: ChatGPTIDTokenVerifying {
    var calls = 0
    var beforeReturn: (() -> Void)?
    var failure: Error?
    func verify(_ token: String, clientID: String, nonce: String?, expectedSubject: String?, receivedAt: Date) async throws -> ChatGPTIdentity {
        calls += 1
        beforeReturn?()
        if let failure { throw failure }
        return ChatGPTIdentity(issuer: ChatGPTAuth.issuer, subject: "subject", email: "example@example.com", name: nil)
    }
}

private final class ChatGPTLockedCounts {
    private let lock = NSLock()
    private var counts: [String: Int] = [:]
    func increment(_ name: String) { lock.lock(); defer { lock.unlock() }; counts[name, default: 0] += 1 }
    func value(_ name: String) -> Int { lock.lock(); defer { lock.unlock() }; return counts[name, default: 0] }
}

final class ChatGPTTestURLProtocol: URLProtocol {
    typealias Handler = (URLRequest) throws -> (Int, Data)
    private static let lock = NSLock()
    private static var handlers: [String: Handler] = [:]
    static let discovery = Data("{\"issuer\":\"https://auth.openai.com\",\"authorization_endpoint\":\"https://auth.openai.com/api/accounts/authorize\",\"token_endpoint\":\"https://auth.openai.com/api/accounts/oauth/token\",\"jwks_uri\":\"https://auth.openai.com/.well-known/jwks.json\",\"revocation_endpoint\":\"https://auth.openai.com/api/accounts/oauth/revoke\"}".utf8)

    static func session(handler: @escaping Handler) -> URLSession {
        let id = UUID().uuidString
        lock.lock(); handlers[id] = handler; lock.unlock()
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [ChatGPTTestURLProtocol.self]
        config.httpAdditionalHeaders = ["x-noop-test-session": id]
        return URLSession(configuration: config)
    }
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        Self.lock.lock()
        let handler = request.value(forHTTPHeaderField: "x-noop-test-session").flatMap { Self.handlers[$0] }
        Self.lock.unlock()
        do {
            guard let handler else { throw URLError(.unsupportedURL) }
            let (status, data) = try handler(request)
            let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: "HTTP/1.1", headerFields: ["Content-Type": "application/json"])!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch { client?.urlProtocol(self, didFailWithError: error) }
    }
    override func stopLoading() { }
    static func body(_ request: URLRequest) -> String {
        if let data = request.httpBody { return String(decoding: data, as: UTF8.self) }
        guard let stream = request.httpBodyStream else { return "" }
        stream.open(); defer { stream.close() }
        var data = Data(), buffer = [UInt8](repeating: 0, count: 1024)
        while stream.hasBytesAvailable {
            let count = stream.read(&buffer, maxLength: buffer.count)
            if count <= 0 { break }
            data.append(buffer, count: count)
        }
        return String(decoding: data, as: UTF8.self)
    }
}
