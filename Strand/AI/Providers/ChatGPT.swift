import Foundation

/// One account-visible model. The slug is the wire identifier; the label is only for display.
struct ChatGPTModel: Equatable, Identifiable, Codable, Sendable {
    let slug: String
    let displayName: String
    var id: String { slug }
}

/// A failure safe to display or include in diagnostics. Provider text and response bodies are never
/// retained: they can echo submitted health data or credentials. Codes and request IDs are bounded
/// machine identifiers, rather than arbitrary strings supplied by the server.
struct ChatGPTRequestError: LocalizedError, Equatable, Sendable {
    enum Kind: String, Sendable { case auth, permission, usage, model, server, stream }
    enum BodyShape: String, Sendable { case structured, detail, unrecognized }

    let kind: Kind
    let status: Int?
    let code: String?
    let requestID: String?
    let outputStarted: Bool
    let bodyShape: BodyShape?

    init(kind: Kind, status: Int? = nil, code: String? = nil, requestID: String? = nil,
         outputStarted: Bool = false, bodyShape: BodyShape? = nil) {
        self.kind = kind
        self.status = status
        self.code = Self.machineIdentifier(code)
        self.requestID = Self.machineIdentifier(requestID)
        self.outputStarted = outputStarted
        self.bodyShape = bodyShape
    }

    var errorDescription: String? {
        switch kind {
        case .auth:
            return "ChatGPT could not authorize this request. Check your connection and plan permission."
        case .permission:
            return "Your ChatGPT account or its policy does not permit this request."
        case .usage:
            return "ChatGPT plan usage is currently limited. Check Usage in ChatGPT settings before retrying."
        case .model:
            return "This ChatGPT model is unavailable. Refresh the model list and choose an available model."
        case .server:
            return "ChatGPT could not complete the request. Try again later."
        case .stream:
            return "The ChatGPT response did not finish. Try again when your connection is available."
        }
    }

    var diagnosticSummary: String {
        var parts = [kind.rawValue]
        if let status { parts.append("HTTP \(status)") }
        if let code { parts.append(code) }
        if let requestID { parts.append("request \(requestID)") }
        if let bodyShape { parts.append(bodyShape.rawValue) }
        return parts.joined(separator: " · ")
    }

    static func http(status: Int, data: Data, requestID: String?,
                     outputStarted: Bool = false) -> ChatGPTRequestError {
        let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        return provider(status: status, object: object, requestID: requestID,
                        outputStarted: outputStarted)
    }

    static func provider(status: Int?, object: [String: Any]?, requestID: String?,
                         outputStarted: Bool) -> ChatGPTRequestError {
        let error = object?["error"] as? [String: Any] ?? object
        let code = machineIdentifier(error?["code"] as? String)
        let param = error?["param"] as? String
        let shape: BodyShape
        if object?["error"] is [String: Any] || code != nil { shape = .structured }
        else if object?["detail"] != nil { shape = .detail }
        else { shape = .unrecognized }

        let kind: Kind
        switch code {
        case "subscription_sharing_usage_limit_exceeded", "rate_limit_exceeded", "insufficient_quota":
            kind = .usage
        case "subscription_sharing_invalid_user", "invalid_api_key", "invalid_token", "token_expired":
            kind = .auth
        case "model_not_found", "invalid_model", "model_access_denied":
            kind = .model
        case "subscription_sharing_user_not_eligible", "subscription_sharing_route_not_supported",
             "chatpass_v2_scope_not_authorized", "chatpass_v2_invalid_authorization_context":
            kind = .permission
        case "subscription_sharing_unsupported_capability":
            kind = param == "model" ? .model : .permission
        case "subscription_sharing_usage_unavailable", "subscription_sharing_user_unavailable":
            kind = .server
        default:
            switch status {
            case 401: kind = .auth
            case 403: kind = .permission
            case 429: kind = .usage
            case 404: kind = .model
            default: kind = .server
            }
        }
        return ChatGPTRequestError(kind: kind, status: status, code: code, requestID: requestID,
                                  outputStarted: outputStarted, bodyShape: shape)
    }

    private static func machineIdentifier(_ value: String?) -> String? {
        guard let value, !value.isEmpty, value.utf8.count <= 128 else { return nil }
        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_.:-")
        guard value.unicodeScalars.allSatisfy({ allowed.contains($0) }) else { return nil }
        return value
    }
}

/// Direct ChatGPT-plan transport. Authentication, account selection and bounded retries belong to
/// the session owner; this value never loads, refreshes, caches or logs a credential.
struct ChatGPTClient {
    private let session: URLSession
    static let modelsURL = URL(string: "https://api.openai.com/v1/models")!
    static let responsesURL = URL(string: "https://api.openai.com/v1/responses")!

    init(session: URLSession = URLSession(configuration: .ephemeral)) { self.session = session }

    func fetchModels(accessToken: String) async throws -> [ChatGPTModel] {
        try Task.checkCancellation()
        let request = try Self.modelsRequest(accessToken: accessToken)
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request, delegate: ChatGPTRejectRedirects())
            try Task.checkCancellation()
        } catch {
            if Task.isCancelled || error is CancellationError { throw CancellationError() }
            throw ChatGPTRequestError(kind: .server, code: "catalog_connection_failed")
        }
        guard let http = response as? HTTPURLResponse else {
            throw ChatGPTRequestError(kind: .server, code: "missing_http_response")
        }
        let requestID = http.value(forHTTPHeaderField: "x-request-id")
        guard (200..<300).contains(http.statusCode) else {
            throw ChatGPTRequestError.http(status: http.statusCode, data: data, requestID: requestID)
        }
        return try Self.parseModels(data, requestID: requestID)
    }

    @MainActor
    func send(accessToken: String, model: String, instructions: String,
              messages: [(role: ChatMessage.Role, content: String)]) async throws -> String {
        var text = ""
        try await stream(accessToken: accessToken, model: model, instructions: instructions,
                         messages: messages) { text += $0 }
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Delta delivery shares the Coach/UI executor; URLSession performs asynchronous network I/O.
    @MainActor
    func stream(accessToken: String, model: String, instructions: String,
                messages: [(role: ChatMessage.Role, content: String)],
                onDelta: (String) -> Void) async throws {
        try Task.checkCancellation()
        let request = try Self.responsesRequest(accessToken: accessToken, model: model,
                                                instructions: instructions, messages: messages)
        let bytes: URLSession.AsyncBytes
        let response: URLResponse
        do {
            (bytes, response) = try await session.bytes(for: request, delegate: ChatGPTRejectRedirects())
        } catch {
            if Task.isCancelled || error is CancellationError { throw CancellationError() }
            throw ChatGPTRequestError(kind: .stream, code: "connection_failed")
        }
        let dataTask = bytes.task
        defer { dataTask.cancel() }
        guard let http = response as? HTTPURLResponse else {
            throw ChatGPTRequestError(kind: .stream, code: "missing_http_response")
        }
        let requestID = http.value(forHTTPHeaderField: "x-request-id")
        var parser = ChatGPTResponsesStream(status: http.statusCode, requestID: requestID)
        do {
            try await withTaskCancellationHandler {
                try Task.checkCancellation()
                guard (200..<300).contains(http.statusCode) else {
                    var body = Data()
                    for try await byte in bytes {
                        try Task.checkCancellation()
                        guard body.count < 65_536 else { break }
                        body.append(byte)
                    }
                    throw ChatGPTRequestError.http(status: http.statusCode, data: body, requestID: requestID)
                }
                let contentType = http.value(forHTTPHeaderField: "Content-Type")?
                    .split(separator: ";", maxSplits: 1).first?
                    .trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                // The direct subscription route can return valid SSE without this header.
                // Validate the event stream below, but reject an explicitly different media type.
                guard contentType == nil || contentType == "text/event-stream" else {
                    throw ChatGPTRequestError(kind: .stream, status: http.statusCode,
                                              code: "expected_event_stream", requestID: requestID)
                }
                for try await byte in bytes {
                    try Task.checkCancellation()
                    try parser.append(byte, onDelta: onDelta)
                    if parser.completed { break }
                }
                try Task.checkCancellation()
                _ = try parser.finish(onDelta: onDelta)
            } onCancel: {
                dataTask.cancel()
            }
        } catch {
            if Task.isCancelled || error is CancellationError { throw CancellationError() }
            if let typed = error as? ChatGPTRequestError { throw typed }
            throw ChatGPTRequestError(kind: .stream, status: http.statusCode,
                                      code: "connection_interrupted", requestID: requestID,
                                      outputStarted: parser.outputStarted)
        }
    }

    static func modelsRequest(accessToken: String) throws -> URLRequest {
        try authorizedRequest(url: modelsURL, accessToken: accessToken)
    }

    static func responsesRequest(accessToken: String, model: String, instructions: String,
                                 messages: [(role: ChatMessage.Role, content: String)]) throws -> URLRequest {
        guard !model.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ChatGPTRequestError(kind: .model, code: "missing_model")
        }
        var request = try authorizedRequest(url: responsesURL, accessToken: accessToken)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
        let input = messages.map { ["role": $0.role.rawValue, "content": $0.content] }
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "model": model, "instructions": instructions, "input": input,
            "store": false, "stream": true
        ])
        return request
    }

    static func parseModels(_ data: Data, requestID: String? = nil) throws -> [ChatGPTModel] {
        guard let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let rows = object["models"] as? [Any] else {
            throw ChatGPTRequestError(kind: .model, code: "malformed_catalog", requestID: requestID)
        }
        var seen: Set<String> = []
        return rows.compactMap { value in
            guard let row = value as? [String: Any], row["visibility"] as? String == "list",
                  let slug = row["slug"] as? String, !slug.isEmpty,
                  slug == slug.trimmingCharacters(in: .whitespacesAndNewlines),
                  let label = row["display_name"] as? String,
                  !label.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  seen.insert(slug).inserted else { return nil }
            return ChatGPTModel(slug: slug, displayName: label)
        }
    }

    private static func authorizedRequest(url: URL, accessToken: String) throws -> URLRequest {
        guard !accessToken.isEmpty,
              accessToken.rangeOfCharacter(from: .whitespacesAndNewlines) == nil else {
            throw ChatGPTRequestError(kind: .auth, code: "missing_or_invalid_access_token")
        }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        return request
    }
}

/// Fixed public API endpoints must not redirect a health-bearing request or OAuth credential.
private final class ChatGPTRejectRedirects: NSObject, URLSessionTaskDelegate {
    func urlSession(_ session: URLSession, task: URLSessionTask,
                    willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest,
                    completionHandler: @escaping (URLRequest?) -> Void) {
        completionHandler(nil)
    }
}
