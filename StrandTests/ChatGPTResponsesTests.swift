import Foundation
import XCTest
@testable import Strand

final class ChatGPTResponsesTests: XCTestCase {
    func testRequestUsesOnlySupportedBodyAndPublicEndpoint() throws {
        let request = try ChatGPTClient.responsesRequest(
            accessToken: "test-oauth-token", model: "account-model", instructions: "Coach briefly.",
            messages: [(.user, "My first question"), (.assistant, "Previous answer"), (.user, "A follow-up")])
        XCTAssertEqual(request.url?.absoluteString, "https://api.openai.com/v1/responses")
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer test-oauth-token")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Accept"), "text/event-stream")
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: XCTUnwrap(request.httpBody)) as? [String: Any])
        XCTAssertEqual(Set(object.keys), ["model", "instructions", "input", "store", "stream"])
        XCTAssertEqual(object["model"] as? String, "account-model")
        XCTAssertEqual(object["instructions"] as? String, "Coach briefly.")
        XCTAssertEqual(object["store"] as? Bool, false)
        XCTAssertEqual(object["stream"] as? Bool, true)
        let input = try XCTUnwrap(object["input"] as? [[String: String]])
        XCTAssertEqual(input, [
            ["role": "user", "content": "My first question"],
            ["role": "assistant", "content": "Previous answer"],
            ["role": "user", "content": "A follow-up"]
        ])
        XCTAssertThrowsError(try ChatGPTClient.modelsRequest(accessToken: "token\r\nInjected: yes"))
        XCTAssertThrowsError(try ChatGPTClient.modelsRequest(accessToken: ""))
    }

    func testCatalogUsesAccountSchemaAndPreservesVisibleServerOrder() throws {
        let data = Data(#"{"models":[{"slug":"second","display_name":"Second label","visibility":"list"},{"slug":"hidden","display_name":"Hidden","visibility":"hide"},{"slug":"first","display_name":"First label","visibility":"list"},{"slug":"second","display_name":"Duplicate","visibility":"list"},{"slug":"broken","visibility":"list"},23]}"#.utf8)
        XCTAssertEqual(try ChatGPTClient.parseModels(data), [
            ChatGPTModel(slug: "second", displayName: "Second label"),
            ChatGPTModel(slug: "first", displayName: "First label")
        ])
        XCTAssertEqual(try ChatGPTClient.parseModels(Data(#"{"models":[]}"#.utf8)), [])
        XCTAssertThrowsError(try ChatGPTClient.parseModels(Data(#"{"data":[{"id":"api-key-model"}]}"#.utf8)))
    }

    func testSSESurvivesEveryUTF8SplitAndCRLFMultilineDataWithoutDuplicatingFinalText() throws {
        let payload = "\u{FEFF}: keepalive\r\nid: 123\r\n\r\n"
            + "event: response.output_text.delta\r\n"
            + "data: {\r\ndata: \"type\":\"response.output_text.delta\",\r\n"
            + "data: \"delta\":\"Recovery 💚\"\r\ndata: }\r\n\r\n"
            + event("response.output_text.delta", fields: ["delta": " today"])
            + event("response.output_text.done", fields: ["text": "Recovery 💚 today"])
            + completed()
        let bytes = Data(payload.utf8)
        for split in 0...bytes.count {
            var parser = ChatGPTResponsesStream()
            var output = ""
            try parser.append(Data(bytes.prefix(split))) { output += $0 }
            try parser.append(Data(bytes.dropFirst(split))) { output += $0 }
            XCTAssertTrue(parser.completed, "split \(split)")
            XCTAssertEqual(try parser.finish(), "Recovery 💚 today", "split \(split)")
            XCTAssertEqual(output, "Recovery 💚 today", "split \(split)")
        }
        var byteParser = ChatGPTResponsesStream()
        var output = ""
        for byte in bytes { try byteParser.append(byte) { output += $0 } }
        XCTAssertEqual(try byteParser.finish(), output)
    }

    func testPrematureEOFAndTruncatedCompletionNeverSucceed() throws {
        let prefix = event("response.output_text.delta", fields: ["delta": "Partial advice"])
        for suffix in ["", String(completed().dropLast(3)), "data: [DONE]\n\n",
                       String(event("response.incomplete", fields: ["response": ["status": "incomplete"]]).dropLast(2))] {
            var parser = ChatGPTResponsesStream(status: 200, requestID: "req_eof")
            var output = ""
            XCTAssertThrowsError(try {
                try parser.append(Data((prefix + suffix).utf8)) { output += $0 }
                _ = try parser.finish()
            }()) { error in
                XCTAssertEqual((error as? ChatGPTRequestError)?.kind, .stream)
                XCTAssertEqual((error as? ChatGPTRequestError)?.outputStarted, true)
            }
            XCTAssertEqual(output, "Partial advice")
        }
    }

    func testCleanEOFAcceptsACompleteTerminalWithoutFinalBlankLine() throws {
        let prefix = event("response.output_text.delta", fields: ["delta": "Complete advice"])
        for trailingNewlines in 0...1 {
            var parser = ChatGPTResponsesStream()
            var output = ""
            let terminal = String(completed().dropLast(2)) + String(repeating: "\n", count: trailingNewlines)
            try parser.append(Data((prefix + terminal).utf8)) { output += $0 }
            XCTAssertFalse(parser.completed)
            XCTAssertEqual(try parser.finish { output += $0 }, "Complete advice")
            XCTAssertTrue(parser.completed)
            XCTAssertEqual(output, "Complete advice")
        }
    }

    func testCleanEOFFlushEmitsFinalDeltaButStillRequiresCompletion() throws {
        var parser = ChatGPTResponsesStream()
        var output = ""
        let delta = String(event("response.output_text.delta", fields: ["delta": "Partial at EOF"]).dropLast(2))
        try parser.append(Data(delta.utf8)) { output += $0 }
        XCTAssertEqual(output, "")
        XCTAssertThrowsError(try parser.finish { output += $0 }) { error in
            XCTAssertEqual((error as? ChatGPTRequestError)?.code, "stream_ended_before_completion")
            XCTAssertEqual((error as? ChatGPTRequestError)?.outputStarted, true)
        }
        XCTAssertEqual(output, "Partial at EOF")
    }

    func testFailedUsageEventPreservesPartialOutputAndSanitizedMetadata() throws {
        var parser = ChatGPTResponsesStream(status: 200, requestID: "req_usage")
        var output = ""
        let payload = event("response.output_text.delta", fields: ["delta": "Start of advice"])
            + event("response.failed", fields: ["response": [
                "status": "failed", "error": [
                    "code": "subscription_sharing_usage_limit_exceeded",
                    "message": "echoed-secret-token and private health data"
                ]
            ]])
        XCTAssertThrowsError(try parser.append(Data(payload.utf8)) { output += $0 }) { error in
            let error = error as? ChatGPTRequestError
            XCTAssertEqual(error?.kind, .usage)
            XCTAssertEqual(error?.status, 200)
            XCTAssertEqual(error?.code, "subscription_sharing_usage_limit_exceeded")
            XCTAssertEqual(error?.requestID, "req_usage")
            XCTAssertEqual(error?.outputStarted, true)
            XCTAssertFalse(error?.diagnosticSummary.contains("echoed-secret-token") ?? true)
            XCTAssertFalse(error?.localizedDescription.contains("private health data") ?? true)
        }
        XCTAssertEqual(output, "Start of advice")
        XCTAssertThrowsError(try parser.finish())
    }

    func testIncompleteRefusalEmptyAndMalformedEventsFail() throws {
        let cases = [
            event("response.incomplete", fields: ["response": ["status": "incomplete"]]),
            event("response.refusal.delta", fields: ["delta": "Refused"]),
            completed(),
            "data: not-json\n\n",
            "data: {\"delta\":\"missing type\"}\n\n",
            "event: wrong\ndata: {\"type\":\"response.output_text.delta\",\"delta\":\"text\"}\n\n",
            event("response.output_text.delta", fields: ["delta": 45]),
            event("response.completed", fields: ["response": ["status": "in_progress"]])
        ]
        for payload in cases {
            var parser = ChatGPTResponsesStream()
            XCTAssertThrowsError(try {
                try parser.append(Data(payload.utf8)) { _ in }
                _ = try parser.finish()
            }(), "payload \(payload)")
        }
        var invalidUTF8 = ChatGPTResponsesStream()
        XCTAssertThrowsError(try invalidUTF8.append(Data([0xFF, 0x0A])) { _ in })
    }

    func testExplicitErrorAfterOutputIsNotMistakenForCompletion() throws {
        var parser = ChatGPTResponsesStream()
        let payload = event("response.output_text.delta", fields: ["delta": "Some advice"])
            + event("error", fields: ["code": "subscription_sharing_usage_unavailable", "message": "Private echo"])
        XCTAssertThrowsError(try parser.append(Data(payload.utf8)) { _ in }) { error in
            XCTAssertEqual((error as? ChatGPTRequestError)?.kind, .server)
            XCTAssertEqual((error as? ChatGPTRequestError)?.outputStarted, true)
        }
    }

    func testAdmissionErrorsDistinguishAuthPermissionQuotaAndTransientAvailability() {
        let cases: [(Int, String, ChatGPTRequestError.Kind, ChatGPTRequestError.BodyShape)] = [
            (401, #"{"detail":"credential-token is invalid"}"#, .auth, .detail),
            (403, #"{"detail":"Region restriction"}"#, .permission, .detail),
            (403, #"{"error":{"code":"subscription_sharing_user_not_eligible"}}"#, .permission, .structured),
            (429, #"{"error":{"code":"subscription_sharing_usage_limit_exceeded"}}"#, .usage, .structured),
            (503, #"{"error":{"code":"subscription_sharing_usage_unavailable"}}"#, .server, .structured),
            (400, #"{"error":{"code":"subscription_sharing_unsupported_capability","param":"model"}}"#, .model, .structured),
            (503, "bad gateway", .server, .unrecognized)
        ]
        for (status, body, kind, shape) in cases {
            let error = ChatGPTRequestError.http(status: status, data: Data(body.utf8), requestID: "req_123")
            XCTAssertEqual(error.kind, kind)
            XCTAssertEqual(error.bodyShape, shape)
            XCTAssertEqual(error.status, status)
            XCTAssertEqual(error.requestID, "req_123")
            XCTAssertFalse(error.localizedDescription.contains("credential-token"))
        }
        let unsafe = ChatGPTRequestError.http(status: 500, data: Data(#"{"error":{"code":"secret\nvalue"}}"#.utf8),
                                              requestID: "request\r\nprivate-data")
        XCTAssertNil(unsafe.code)
        XCTAssertNil(unsafe.requestID)
    }

    func testClientFetchesCatalogAndAggregatesTheSameStreamAsForeground() async throws {
        let catalogSession = ChatGPTResponsesURLProtocol.session(status: 200, contentType: "application/json", chunks: [
            Data(#"{"models":[{"slug":"permitted","display_name":"My model","visibility":"list"}]}"#.utf8)
        ])
        defer { catalogSession.invalidateAndCancel() }
        let models = try await ChatGPTClient(session: catalogSession).fetchModels(accessToken: "test-token")
        XCTAssertEqual(models, [ChatGPTModel(slug: "permitted", displayName: "My model")])

        let payload = Data((event("response.output_text.delta", fields: ["delta": "Ready 💚"])
                            + event("response.output_text.delta", fields: ["delta": " today"])
                            + completed()).utf8)
        let chunks = payload.map { Data([$0]) }
        let session = ChatGPTResponsesURLProtocol.session(status: 200, contentType: "text/event-stream; charset=utf-8", chunks: chunks)
        defer { session.invalidateAndCancel() }
        let client = ChatGPTClient(session: session)
        var foreground = ""
        try await client.stream(accessToken: "test-token", model: "permitted", instructions: "Coach.",
                                messages: [(.user, "Hello")]) {
            XCTAssertTrue(Thread.isMainThread, "Stream callbacks mutate the main-actor Coach/UI state")
            foreground += $0
        }
        let aggregated = try await client.send(accessToken: "test-token", model: "permitted", instructions: "Coach.",
                                               messages: [(.user, "Hello")])
        XCTAssertEqual(foreground, "Ready 💚 today")
        XCTAssertEqual(aggregated, foreground)
    }

    func testClientDoesNotReturnPartialHeadlessAnswerOrReclassifyHTTP403AsBadKey() async throws {
        let session = ChatGPTResponsesURLProtocol.session(status: 200, contentType: "text/event-stream", chunks: [
            Data(event("response.output_text.delta", fields: ["delta": "Unfinished"]).utf8)
        ])
        defer { session.invalidateAndCancel() }
        do {
            _ = try await ChatGPTClient(session: session).send(accessToken: "test-token", model: "model",
                                                              instructions: "Coach.", messages: [(.user, "Hello")])
            XCTFail("Partial headless output must not become a successful brief")
        } catch let error as ChatGPTRequestError {
            XCTAssertEqual(error.kind, .stream)
            XCTAssertTrue(error.outputStarted)
        }
        let denied = ChatGPTResponsesURLProtocol.session(status: 403, contentType: "application/json", chunks: [
            Data(#"{"detail":"Policy restriction with private data"}"#.utf8)
        ])
        defer { denied.invalidateAndCancel() }
        do {
            try await ChatGPTClient(session: denied).stream(accessToken: "test-token", model: "model",
                                                            instructions: "Coach.", messages: [(.user, "Hello")]) { _ in
                XCTFail("An admission rejection must never emit output")
            }
            XCTFail("Expected permission error")
        } catch let error as ChatGPTRequestError {
            XCTAssertEqual(error.kind, .permission)
            XCTAssertEqual(error.status, 403)
            XCTAssertEqual(error.requestID, "req_transport")
            XCTAssertFalse(error.outputStarted)
        }
    }

    func testClientAcceptsHeaderlessSSEButRejectsAnExplicitJSONContentType() async throws {
        let payload = Data((event("response.output_text.delta", fields: ["delta": "Connected."])
                            + completed()).utf8)
        let headerless = ChatGPTResponsesURLProtocol.session(status: 200, contentType: nil, chunks: [payload])
        defer { headerless.invalidateAndCancel() }
        let text = try await ChatGPTClient(session: headerless).send(
            accessToken: "test-token", model: "permitted", instructions: "Reply briefly.",
            messages: [(.user, "Hello")])
        XCTAssertEqual(text, "Connected.")

        let explicitJSON = ChatGPTResponsesURLProtocol.session(status: 200, contentType: "application/json", chunks: [payload])
        defer { explicitJSON.invalidateAndCancel() }
        do {
            _ = try await ChatGPTClient(session: explicitJSON).send(
                accessToken: "test-token", model: "permitted", instructions: "Reply briefly.",
                messages: [(.user, "Hello")])
            XCTFail("An explicitly different media type must be rejected even if its bytes resemble SSE")
        } catch let error as ChatGPTRequestError {
            XCTAssertEqual(error.kind, .stream)
            XCTAssertEqual(error.code, "expected_event_stream")
            XCTAssertFalse(error.outputStarted)
        }
    }

    func testClientAcceptsCompletedEventAtCleanEOFWithoutASeparator() async throws {
        let payload = Data((event("response.output_text.delta", fields: ["delta": "Connected."])
                            + String(completed().dropLast(2))).utf8)
        let session = ChatGPTResponsesURLProtocol.session(status: 200, contentType: nil, chunks: [payload])
        defer { session.invalidateAndCancel() }
        let text = try await ChatGPTClient(session: session).send(
            accessToken: "test-token", model: "permitted", instructions: "Reply briefly.",
            messages: [(.user, "Hello")])
        XCTAssertEqual(text, "Connected.")
    }

    func testCancelledClientDoesNotDispatchOrEmitOutput() async throws {
        let session = ChatGPTResponsesURLProtocol.session(status: 200, contentType: "text/event-stream", chunks: [])
        defer { session.invalidateAndCancel() }
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            try await ChatGPTClient(session: session).stream(accessToken: "test-token", model: "model",
                                                            instructions: "Coach.", messages: [(.user, "Hello")]) { _ in
                XCTFail("Cancelled inference must not emit a delta")
            }
        }
        do {
            try await task.value
            XCTFail("Expected cancellation")
        } catch is CancellationError {
            // Cancellation stays cancellation, rather than being presented as a server/auth failure.
        }
    }

    private func event(_ type: String, fields: [String: Any] = [:]) -> String {
        var object = fields
        object["type"] = type
        let data = try! JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
        return "event: \(type)\ndata: \(String(decoding: data, as: UTF8.self))\n\n"
    }

    private func completed() -> String {
        event("response.completed", fields: ["response": ["status": "completed", "output": []]])
    }
}

/// Each session has an isolated fixture, so concurrent tests cannot overwrite each other's stream.
private final class ChatGPTResponsesURLProtocol: URLProtocol {
    private struct Fixture {
        let status: Int
        let contentType: String?
        let chunks: [Data]
    }
    private static let lock = NSLock()
    nonisolated(unsafe) private static var fixtures: [String: Fixture] = [:]

    static func session(status: Int, contentType: String?, chunks: [Data]) -> URLSession {
        let id = UUID().uuidString
        lock.lock()
        fixtures[id] = Fixture(status: status, contentType: contentType, chunks: chunks)
        lock.unlock()
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [ChatGPTResponsesURLProtocol.self]
        configuration.httpAdditionalHeaders = ["X-Noop-ChatGPT-Test": id]
        return URLSession(configuration: configuration)
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let id = request.value(forHTTPHeaderField: "X-Noop-ChatGPT-Test") ?? ""
        Self.lock.lock()
        let fixture = Self.fixtures[id]
        Self.lock.unlock()
        guard let fixture else {
            client?.urlProtocol(self, didFailWithError: URLError(.resourceUnavailable))
            return
        }
        var headers = ["x-request-id": "req_transport"]
        if let contentType = fixture.contentType { headers["Content-Type"] = contentType }
        let response = HTTPURLResponse(url: request.url!, statusCode: fixture.status, httpVersion: "HTTP/1.1",
                                       headerFields: headers)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        for chunk in fixture.chunks { client?.urlProtocol(self, didLoad: chunk) }
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}
