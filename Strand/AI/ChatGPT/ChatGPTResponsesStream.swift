import Foundation

/// Incremental UTF-8/SSE decoder for Responses. A successful HTTP status or an EOF is not a
/// completed answer. Only a completed terminal event with nonempty text can finish successfully.
struct ChatGPTResponsesStream {
    private(set) var text = ""
    private(set) var completed = false
    var outputStarted: Bool { !text.isEmpty }

    private let status: Int?
    private let requestID: String?
    private var line = Data()
    private var dataLines: [String] = []
    private var eventName: String?
    private var eventBytes = 0
    private var previousWasCR = false
    private var firstLine = true
    private var failed = false
    private static let maxLineBytes = 1_048_576
    private static let maxEventBytes = 2_097_152

    init(status: Int? = nil, requestID: String? = nil) {
        self.status = status
        self.requestID = requestID
    }

    mutating func append(_ data: Data, onDelta: (String) -> Void) throws {
        for byte in data { try append(byte, onDelta: onDelta) }
    }

    mutating func append(_ byte: UInt8, onDelta: (String) -> Void) throws {
        guard !failed else { throw failure("stream_already_failed") }
        do {
            if previousWasCR {
                previousWasCR = false
                if byte == 10 { return }
            }
            if byte == 13 || byte == 10 {
                previousWasCR = byte == 13
                try consumeLine(onDelta: onDelta)
                return
            }
            guard line.count < Self.maxLineBytes else { throw failure("event_line_too_large") }
            line.append(byte)
        } catch {
            failed = true
            throw error
        }
    }

    /// Flush a pending record only at clean EOF, matching the official SDK's tolerance for servers
    /// that omit the final blank line. An explicit, valid completion event is still required.
    @discardableResult
    mutating func finish(onDelta: (String) -> Void = { _ in }) throws -> String {
        guard !failed else { throw failure("stream_ended_before_completion") }
        do {
            if !completed {
                if !line.isEmpty { try consumeLine(onDelta: onDelta) }
                if !dataLines.isEmpty { try consumeEvent(onDelta: onDelta) }
            }
            guard completed else { throw failure("stream_ended_before_completion") }
            let result = text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !result.isEmpty else { throw failure("empty_response") }
            return result
        } catch {
            failed = true
            throw error
        }
    }

    private mutating func consumeLine(onDelta: (String) -> Void) throws {
        guard var value = String(data: line, encoding: .utf8) else { throw failure("invalid_utf8") }
        line.removeAll(keepingCapacity: true)
        if firstLine {
            firstLine = false
            if value.hasPrefix("\u{FEFF}") { value.removeFirst() }
        }
        if value.isEmpty {
            try consumeEvent(onDelta: onDelta)
            return
        }
        if value.hasPrefix(":") { return }
        let split = value.firstIndex(of: ":")
        let field = split.map { String(value[..<$0]) } ?? value
        var content = split.map { String(value[value.index(after: $0)...]) } ?? ""
        if content.hasPrefix(" ") { content.removeFirst() }
        switch field {
        case "data":
            eventBytes += content.utf8.count + 1
            guard eventBytes <= Self.maxEventBytes else { throw failure("event_too_large") }
            dataLines.append(content)
        case "event": eventName = content
        default: break
        }
    }

    private mutating func consumeEvent(onDelta: (String) -> Void) throws {
        let name = eventName
        let payload = dataLines.joined(separator: "\n")
        let hasData = !dataLines.isEmpty
        dataLines.removeAll(keepingCapacity: true)
        eventName = nil
        eventBytes = 0
        guard hasData else { return }
        if completed {
            if payload == "[DONE]" { return }
            throw failure("event_after_completion")
        }
        guard payload != "[DONE]" else { throw failure("stream_ended_before_completion") }
        guard let data = payload.data(using: .utf8),
              let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let type = object["type"] as? String, !type.isEmpty else {
            throw failure("malformed_event")
        }
        if let name, !name.isEmpty, name != type { throw failure("event_type_mismatch") }
        switch type {
        case "response.output_text.delta":
            guard let delta = object["delta"] as? String else { throw failure("malformed_text_delta") }
            if !delta.isEmpty {
                text += delta
                onDelta(delta)
            }
        case "response.completed":
            guard let response = object["response"] as? [String: Any],
                  response["status"] as? String == "completed" else {
                throw failure("malformed_completion")
            }
            guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw failure("empty_response")
            }
            completed = true
        case "response.failed":
            let response = object["response"] as? [String: Any]
            throw ChatGPTRequestError.provider(status: status, object: response,
                                               requestID: requestID, outputStarted: outputStarted)
        case "error":
            throw ChatGPTRequestError.provider(status: status, object: object,
                                               requestID: requestID, outputStarted: outputStarted)
        case "response.incomplete":
            throw failure("response_incomplete")
        case "response.refusal.delta", "response.refusal.done":
            throw failure("response_refused")
        default:
            // Lifecycle, reasoning and final text snapshots are not additional answer deltas.
            break
        }
    }

    private func failure(_ code: String) -> ChatGPTRequestError {
        ChatGPTRequestError(kind: .stream, status: status, code: code,
                           requestID: requestID, outputStarted: outputStarted)
    }
}
