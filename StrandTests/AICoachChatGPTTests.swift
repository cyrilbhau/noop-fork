import Foundation
import XCTest
import WhoopStore
@testable import Strand

@MainActor
final class AICoachChatGPTTests: XCTestCase {
    func testSubscriptionReadinessNeverUsesTheAPIKeyConnection() async throws {
        try await isolatedDefaults {
            let requests = EngineChatGPTRequests()
            let http = EngineChatGPTURLProtocol.session { request in
                requests.append(request)
                return (500, "application/json", Data())
            }
            let auth = ChatGPTSession(session: http, store: EngineChatGPTMemoryStore())
            let repo = Repository(deviceId: "test-chatgpt-no-key")
            let store = try await WhoopStore.inMemory()
            let existing = [CoachMessageRow(id: UUID().uuidString, role: "assistant", text: "Saved advice",
                                             provider: "openAI", createdAt: Int(Date().timeIntervalSince1970), orderIndex: 0)]
            try await store.replaceCoachMessages(existing)
            repo.setStoreForTesting(store)
            let engine = AICoachEngine(repo: repo, chatGPTSession: auth, chatGPTHTTP: http)
            XCTAssertEqual(engine.provider, .chatGPT)
            XCTAssertNil(AIProvider.chatGPT.legacyClient)
            XCTAssertFalse(engine.isConfigured)
            XCTAssertFalse(engine.canRefreshModels)
            await engine.send("Hello")
            XCTAssertTrue(engine.messages.isEmpty)
            XCTAssertFalse(engine.keyRejected)
            XCTAssertEqual(engine.errorText, ChatGPTAuthError.signInRequired.localizedDescription)
            XCTAssertTrue(requests.snapshot.isEmpty)
            await engine.waitForHistoryWritesForTesting()
            let retained = try await store.coachMessages()
            XCTAssertEqual(retained, existing, "A send rejected before appending must not erase saved history")
            http.invalidateAndCancel()
        }
    }

    func testAllFourInferencePathsUseResponsesAndIndependentHealthConsent() async throws {
        try await isolatedDefaults {
            let requests = EngineChatGPTRequests()
            let fixture = try await makeEngine { request in
                requests.append(request)
                return Self.response(request)
            }
            let engine = fixture.engine
            var contextReads = 0
            engine.fullContextOverride = { contextReads += 1; return "HEALTH_MARKER charge 75" }
            await engine.send("A general question")
            XCTAssertEqual(contextReads, 0)
            XCTAssertEqual(engine.messages.last?.text, "Completed advice")
            let first = try Self.body(XCTUnwrap(requests.snapshot.first))
            XCTAssertFalse(String(describing: first).contains("HEALTH_MARKER"))
            XCTAssertTrue(String(describing: first).contains("not granted access"))
            XCTAssertEqual(Set(first.keys), ["model", "instructions", "input", "store", "stream"])

            engine.dataConsent = true
            let original = engine.messages
            let brief = await engine.generateBrief()
            XCTAssertEqual(brief, "Completed advice")
            XCTAssertEqual(engine.messages, original, "Headless briefs do not append to the conversation")
            engine.clearConversation()
            await engine.startBriefIfNeeded()
            XCTAssertEqual(engine.messages.last?.text, "Today's brief\n\nCompleted advice")

            engine.messages = (0..<14).map { index in
                ChatMessage(role: index.isMultiple(of: 2) ? .user : .assistant, text: "History turn \(index)")
            }
            await engine.send("Keep coaching")
            let bodies = try requests.snapshot.filter { $0.url == ChatGPTClient.responsesURL }.map(Self.body)
            XCTAssertEqual(bodies.count, 5, "send, headless brief, opening brief, summary, follow-up")
            XCTAssertTrue(bodies.contains { String(describing: $0).contains("Summarize the following conversation") })
            XCTAssertTrue(String(describing: bodies.last!).contains("Summary of earlier conversation"))
            for request in requests.snapshot {
                XCTAssertEqual(request.url, ChatGPTClient.responsesURL)
                XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer access-one")
            }
            XCTAssertEqual(engine.messages.last?.text, "Completed advice")
            await engine.waitForHistoryWritesForTesting()
            fixture.http.invalidateAndCancel()
        }
    }

    func testConsentRevocationAfterContextAwaitPreventsHealthEgress() async throws {
        try await isolatedDefaults {
            let requests = EngineChatGPTRequests()
            let fixture = try await makeEngine { request in requests.append(request); return Self.response(request) }
            let gate = EngineChatGPTGate()
            let reached = expectation(description: "context is being built")
            fixture.engine.dataConsent = true
            fixture.engine.fullContextOverride = {
                reached.fulfill()
                await gate.wait()
                return "PRIVATE_HEALTH_CONTEXT"
            }
            let send = Task { await fixture.engine.send("Coach me") }
            await fulfillment(of: [reached], timeout: 3)
            fixture.engine.dataConsent = false
            await gate.open()
            await send.value
            XCTAssertTrue(requests.snapshot.isEmpty)
            XCTAssertFalse(fixture.engine.messages.contains { $0.role == .assistant })
            XCTAssertNil(fixture.engine.errorText)
            await fixture.engine.waitForHistoryWritesForTesting()
            fixture.http.invalidateAndCancel()
        }
    }

    func testMasterOffAfterBriefContextAwaitPreventsHeadlessEgress() async throws {
        try await isolatedDefaults {
            let requests = EngineChatGPTRequests()
            let fixture = try await makeEngine { request in requests.append(request); return Self.response(request) }
            let gate = EngineChatGPTGate()
            let reached = expectation(description: "brief context is being built")
            fixture.engine.dataConsent = true
            fixture.engine.fullContextOverride = { reached.fulfill(); await gate.wait(); return "HEALTH" }
            let brief = Task { await fixture.engine.generateBrief() }
            await fulfillment(of: [reached], timeout: 3)
            UserDefaults.standard.set(false, forKey: "noop.coachEnabled")
            fixture.engine.applyCoachMasterSwitch()
            await gate.open()
            let result = await brief.value
            XCTAssertNil(result)
            XCTAssertTrue(requests.snapshot.isEmpty)
            fixture.http.invalidateAndCancel()
        }
    }

    func testInvalidatedSessionCannotPublishLateStreamOutput() async throws {
        try await isolatedDefaults {
            let reached = expectation(description: "inference started")
            let gate = DispatchSemaphore(value: 0)
            let fixture = try await makeEngine { request in
                reached.fulfill()
                _ = gate.wait(timeout: .now() + 5)
                return Self.response(request)
            }
            let send = Task { await fixture.engine.send("Hello") }
            await fulfillment(of: [reached], timeout: 3)
            fixture.auth.invalidateRequests()
            gate.signal()
            await send.value
            XCTAssertFalse(fixture.engine.messages.contains { $0.role == .assistant })
            XCTAssertNil(fixture.engine.errorText)
            XCTAssertFalse(fixture.engine.sending)
            await fixture.engine.waitForHistoryWritesForTesting()
            fixture.http.invalidateAndCancel()
        }
    }

    func testCatalogResultsCannotOverwriteAnotherProviderAndLabelsUseSlugs() async throws {
        try await isolatedDefaults {
            let reached = expectation(description: "catalog started")
            let gate = DispatchSemaphore(value: 0)
            let fixture = try await makeEngine { request in
                reached.fulfill()
                _ = gate.wait(timeout: .now() + 5)
                return (200, "application/json", Data(#"{"models":[{"slug":"late-model","display_name":"Late label","visibility":"list"}]}"#.utf8))
            }
            XCTAssertEqual(fixture.engine.model, "account-model")
            XCTAssertEqual(fixture.engine.modelDisplayName("account-model"), "Account label")
            let refresh = Task { await fixture.engine.refreshModels() }
            await fulfillment(of: [reached], timeout: 3)
            fixture.engine.provider = .anthropic
            gate.signal()
            await refresh.value
            XCTAssertEqual(fixture.engine.availableModels, AIProvider.anthropic.modelOptions)
            XCTAssertFalse(fixture.engine.availableModels.contains("late-model"))
            fixture.http.invalidateAndCancel()
        }
    }

    func testAuthenticationRetriesOnceBeforeAnyOutputAndNeverUsesAPIKeyBilling() async throws {
        try await isolatedDefaults {
            let requests = EngineChatGPTRequests()
            let fixture = try await makeEngine { request in
                requests.append(request)
                if request.url == ChatGPTAuth.tokenEndpoint {
                    return (200, "application/json", Data(#"{"access_token":"access-new","refresh_token":"refresh-new","token_type":"Bearer","expires_in":3600,"scope":"chatgpt.tokens.use.direct offline_access"}"#.utf8))
                }
                if requests.snapshot.filter({ $0.url == ChatGPTClient.responsesURL }).count == 1 {
                    return (401, "application/json", Data(#"{"error":{"code":"invalid_token"}}"#.utf8))
                }
                return Self.response(request)
            }
            await fixture.engine.send("Hello")
            let inference = requests.snapshot.filter { $0.url == ChatGPTClient.responsesURL }
            XCTAssertEqual(inference.count, 2)
            XCTAssertEqual(requests.snapshot.filter { $0.url == ChatGPTAuth.tokenEndpoint }.count, 1)
            XCTAssertEqual(inference.map { $0.value(forHTTPHeaderField: "Authorization") }, ["Bearer access-one", "Bearer access-new"])
            XCTAssertEqual(fixture.engine.messages.last?.text, "Completed advice")
            XCTAssertFalse(fixture.engine.keyRejected)
            await fixture.engine.waitForHistoryWritesForTesting()
            fixture.http.invalidateAndCancel()
        }
    }

    func testAuthenticationFailureAfterTextNeverReplaysPartialAnswer() async throws {
        try await isolatedDefaults {
            let requests = EngineChatGPTRequests()
            let fixture = try await makeEngine { request in
                requests.append(request)
                return (200, "text/event-stream", Data((Self.delta("Partial")
                    + "data: {\"type\":\"response.failed\",\"response\":{\"status\":\"failed\",\"error\":{\"code\":\"invalid_token\"}}}\n\n").utf8))
            }
            await fixture.engine.send("Hello")
            XCTAssertEqual(requests.snapshot.count, 1)
            XCTAssertEqual(fixture.engine.messages.last?.text, "Partial\n\n*(stream interrupted)*")
            XCTAssertFalse(fixture.engine.keyRejected)
            XCTAssertEqual(fixture.auth.state, .reauthorizationRequired)
            await fixture.engine.waitForHistoryWritesForTesting()
            fixture.http.invalidateAndCancel()
        }
    }

    func testUncommittedOrDifferentAccountHistoryIsNeverRestored() async throws {
        try await isolatedDefaults {
            let store = try await WhoopStore.inMemory()
            let rows = [CoachMessageRow(id: UUID().uuidString, role: "assistant", text: "OTHER_ACCOUNT_ADVICE",
                                         provider: "chatGPT", createdAt: Int(Date().timeIntervalSince1970), orderIndex: 0)]
            try await store.replaceCoachMessages(rows)
            UserDefaults.standard.set("old-profile", forKey: "ai.chatGPT.conversationProfile")
            let fixture = try await makeEngine(store: store) { request in Self.response(request) }
            XCTAssertTrue(UserDefaults.standard.bool(forKey: "ai.coachHistoryWritePending"))
            await fixture.engine.loadPersistedMessagesIfNeeded()
            XCTAssertTrue(fixture.engine.messages.isEmpty)
            await fixture.engine.waitForHistoryWritesForTesting()

            // Simulate process death after SQLite replacement but before its owner metadata commit.
            try await store.replaceCoachMessages(rows)
            UserDefaults.standard.set(fixture.profileID, forKey: "ai.chatGPT.conversationProfile")
            UserDefaults.standard.set(true, forKey: "ai.coachHistoryWritePending")
            let restarted = try await makeEngine(store: store, profileID: fixture.profileID) { request in Self.response(request) }
            await restarted.engine.loadPersistedMessagesIfNeeded()
            XCTAssertTrue(restarted.engine.messages.isEmpty)
            let stillStored = try await store.coachMessages()
            XCTAssertEqual(stillStored, rows, "The pending marker rejects replay even when SQLite still has rows")
            fixture.http.invalidateAndCancel()
            restarted.http.invalidateAndCancel()
        }
    }

    func testScheduledAndExplicitBriefHistoryRestoresForTheSameProfile() async throws {
        try await isolatedDefaults {
            let store = try await WhoopStore.inMemory()
            let fixture = try await makeEngine(store: store) { request in Self.response(request) }
            fixture.engine.surfaceScheduledBrief("Scheduled advice")
            await fixture.engine.waitForHistoryWritesForTesting()
            XCTAssertEqual(UserDefaults.standard.string(forKey: "ai.chatGPT.conversationProfile"), fixture.profileID)
            let restored = try await makeEngine(store: store, profileID: fixture.profileID) { request in Self.response(request) }
            await restored.engine.loadPersistedMessagesIfNeeded()
            XCTAssertEqual(restored.engine.messages.last?.text, "Today's brief\n\nScheduled advice")

            fixture.engine.clearConversation()
            fixture.engine.appendGeneratedBrief("Explicit advice")
            await fixture.engine.waitForHistoryWritesForTesting()
            let generated = try await makeEngine(store: store, profileID: fixture.profileID) { request in Self.response(request) }
            await generated.engine.loadPersistedMessagesIfNeeded()
            XCTAssertEqual(generated.engine.messages.last?.text, "Today's brief\n\nExplicit advice")
            fixture.http.invalidateAndCancel()
            restored.http.invalidateAndCancel()
            generated.http.invalidateAndCancel()
        }
    }

    private func makeEngine(store: WhoopStore? = nil, profileID: String = UUID().uuidString,
                            handler: @escaping EngineChatGPTURLProtocol.Handler) async throws
        -> (engine: AICoachEngine, auth: ChatGPTSession, http: URLSession, profileID: String) {
        let http = EngineChatGPTURLProtocol.session(handler: handler)
        let profile = ChatGPTProfile(id: profileID, clientID: "oaiapp_engine", issuer: ChatGPTAuth.issuer,
                                     subject: "test-subject", email: nil, name: nil, label: "Test")
        let tokens = ChatGPTTokens(accessToken: "access-one", refreshToken: "refresh-one", idToken: "verified-test-id",
                                   expiresAt: Date().addingTimeInterval(3600), scopes: [ChatGPTAuth.planScope, "offline_access"],
                                   earliestRefreshAt: nil, receivedAt: Date())
        let state = ChatGPTStoredState(hostID: "urn:uuid:test-host", registrations: [
            ChatGPTRegistration(profile: profile, tokens: tokens, pendingRefresh: nil)
        ], activeProfileID: profileID)
        let auth = ChatGPTSession(session: http, store: EngineChatGPTMemoryStore(value: state))
        UserDefaults.standard.set(try JSONEncoder().encode([ChatGPTModel(slug: "account-model", displayName: "Account label")]),
                                  forKey: "ai.chatGPT.catalog.\(profileID)")
        UserDefaults.standard.set("account-model", forKey: "ai.chatGPT.model.\(profileID)")
        let repo = Repository(deviceId: "test-chatgpt-engine")
        let actualStore: WhoopStore
        if let store { actualStore = store } else { actualStore = try await WhoopStore.inMemory() }
        repo.setStoreForTesting(actualStore)
        let engine = AICoachEngine(repo: repo, chatGPTSession: auth, chatGPTHTTP: http)
        return (engine, auth, http, profileID)
    }

    private func isolatedDefaults(_ operation: () async throws -> Void) async rethrows {
        let defaults = UserDefaults.standard
        let relevant: (String) -> Bool = { $0.hasPrefix("ai.") || $0.hasPrefix("coachBrief.") || $0 == "noop.coachEnabled" }
        let old = defaults.dictionaryRepresentation().filter { relevant($0.key) }
        for key in old.keys { defaults.removeObject(forKey: key) }
        defaults.set("chatGPT", forKey: "ai.provider")
        defaults.set(true, forKey: "noop.coachEnabled")
        defer {
            for key in defaults.dictionaryRepresentation().keys where relevant(key) { defaults.removeObject(forKey: key) }
            for (key, value) in old { defaults.set(value, forKey: key) }
        }
        try await operation()
    }

    nonisolated private static func body(_ request: URLRequest) throws -> [String: Any] {
        let raw = ChatGPTTestURLProtocol.body(request)
        return try XCTUnwrap(JSONSerialization.jsonObject(with: Data(raw.utf8)) as? [String: Any])
    }

    nonisolated private static func delta(_ text: String) -> String {
        let object: [String: Any] = ["type": "response.output_text.delta", "delta": text]
        return "data: \(String(decoding: try! JSONSerialization.data(withJSONObject: object), as: UTF8.self))\n\n"
    }

    nonisolated private static func response(_ request: URLRequest) -> (Int, String, Data) {
        if request.url == ChatGPTClient.modelsURL {
            return (200, "application/json", Data(#"{"models":[{"slug":"account-model","display_name":"Account label","visibility":"list"}]}"#.utf8))
        }
        return (200, "text/event-stream", Data((delta("Completed advice")
            + "data: {\"type\":\"response.completed\",\"response\":{\"status\":\"completed\"}}\n\n").utf8))
    }
}

@MainActor
private final class EngineChatGPTMemoryStore: ChatGPTCredentialStoring {
    var value: ChatGPTStoredState?
    init(value: ChatGPTStoredState? = nil) { self.value = value }
    func load() throws -> ChatGPTStoredState? { value }
    func save(_ value: ChatGPTStoredState) throws { self.value = value }
}

private actor EngineChatGPTGate {
    private var continuation: CheckedContinuation<Void, Never>?
    private var opened = false
    func wait() async {
        if opened { return }
        await withCheckedContinuation { continuation = $0 }
    }
    func open() { opened = true; continuation?.resume(); continuation = nil }
}

private final class EngineChatGPTRequests {
    private let lock = NSLock()
    private var requests: [URLRequest] = []
    func append(_ request: URLRequest) { lock.lock(); requests.append(request); lock.unlock() }
    var snapshot: [URLRequest] { lock.lock(); defer { lock.unlock() }; return requests }
}

private final class EngineChatGPTURLProtocol: URLProtocol {
    typealias Handler = (URLRequest) throws -> (Int, String, Data)
    private static let lock = NSLock()
    nonisolated(unsafe) private static var handlers: [String: Handler] = [:]
    static func session(handler: @escaping Handler) -> URLSession {
        let id = UUID().uuidString
        lock.lock(); handlers[id] = handler; lock.unlock()
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [EngineChatGPTURLProtocol.self]
        configuration.httpAdditionalHeaders = ["x-noop-engine-test": id]
        return URLSession(configuration: configuration)
    }
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        Self.lock.lock()
        let handler = request.value(forHTTPHeaderField: "x-noop-engine-test").flatMap { Self.handlers[$0] }
        Self.lock.unlock()
        do {
            guard let handler else { throw URLError(.unsupportedURL) }
            let (status, contentType, data) = try handler(request)
            let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: "HTTP/1.1",
                                           headerFields: ["Content-Type": contentType])!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch { client?.urlProtocol(self, didFailWithError: error) }
    }
    override func stopLoading() {}
}
