import Foundation
import Network

/// The small, local HTTP boundary used only while an interactive ChatGPT sign-in is open.
/// Parsing is separate from the listener so malformed requests can be checked without a socket.
enum ChatGPTLoopbackRequestParser {
    static let maximumRequestBytes = 16_384
    static let callbackPath = "/auth/callback"

    enum Rejection: Error {
        case malformed, method, path, oversized, state

        var status: String {
            switch self {
            case .method: return "405 Method Not Allowed"
            case .path: return "404 Not Found"
            case .oversized: return "431 Request Header Fields Too Large"
            case .malformed, .state: return "400 Bad Request"
            }
        }
    }

    static func callbackURL(from request: Data, redirectURI: URL, expectedState: String) throws -> URL {
        guard request.count <= maximumRequestBytes else { throw Rejection.oversized }
        guard let text = String(data: request, encoding: .utf8),
              let end = text.range(of: "\r\n\r\n"), end.upperBound == text.endIndex else {
            throw Rejection.malformed
        }
        let lines = String(text[..<end.lowerBound]).components(separatedBy: "\r\n")
        guard let first = lines.first else { throw Rejection.malformed }
        let parts = first.split(separator: " ", omittingEmptySubsequences: false)
        guard parts.count == 3, parts[2] == "HTTP/1.1" || parts[2] == "HTTP/1.0" else {
            throw Rejection.malformed
        }
        guard parts[0] == "GET" else { throw Rejection.method }

        var headers: [String: [String]] = [:]
        for line in lines.dropFirst() {
            guard let colon = line.firstIndex(of: ":"), colon != line.startIndex,
                  line.first != " ", line.first != "\t" else { throw Rejection.malformed }
            let name = String(line[..<colon]).lowercased()
            guard name.unicodeScalars.allSatisfy({
                $0.isASCII && (CharacterSet.alphanumerics.contains($0) || "!#$%&'*+-.^_`|~".unicodeScalars.contains($0))
            }) else { throw Rejection.malformed }
            let value = String(line[line.index(after: colon)...]).trimmingCharacters(in: .whitespaces)
            guard value.unicodeScalars.allSatisfy({ $0.value == 9 || $0.value >= 32 && $0.value != 127 }) else {
                throw Rejection.malformed
            }
            headers[name, default: []].append(value)
        }
        // An exact Host also prevents accepting a request to this listener through a different hostname.
        guard redirectURI.scheme == "http", redirectURI.host == "127.0.0.1",
              let port = redirectURI.port,
              headers["host"] == ["127.0.0.1:\(port)"], headers["transfer-encoding"] == nil,
              headers["content-length"] == nil || headers["content-length"] == ["0"] else {
            throw Rejection.malformed
        }

        let target = String(parts[1])
        guard target.hasPrefix("/"), !target.hasPrefix("//"),
              !target.contains("#"), !target.contains("\\"), validPercentEscapes(target),
              let targetParts = URLComponents(string: target), targetParts.scheme == nil,
              targetParts.host == nil, targetParts.percentEncodedPath == callbackPath else {
            throw Rejection.path
        }
        let items = targetParts.queryItems ?? []
        var values: [String: String] = [:]
        for item in items {
            // Duplicate parameters are ambiguous, including fields interpreted by the token client.
            guard values[item.name] == nil, let value = item.value else { throw Rejection.malformed }
            values[item.name] = value
        }
        guard !expectedState.isEmpty, values["state"] == expectedState else { throw Rejection.state }
        guard (values["code"] != nil) != (values["error"] != nil),
              !(values["code"] ?? values["error"] ?? "").isEmpty else { throw Rejection.malformed }
        var callback = URLComponents(url: redirectURI, resolvingAgainstBaseURL: false)
        callback?.percentEncodedQuery = targetParts.percentEncodedQuery
        guard let result = callback?.url else { throw Rejection.malformed }
        return result
    }

    private static func validPercentEscapes(_ value: String) -> Bool {
        let bytes = Array(value.utf8)
        var index = 0
        func isHex(_ byte: UInt8) -> Bool {
            (48...57).contains(byte) || (65...70).contains(byte) || (97...102).contains(byte)
        }
        while index < bytes.count {
            if bytes[index] == 37 {
                guard index + 2 < bytes.count, isHex(bytes[index + 1]), isHex(bytes[index + 2]) else { return false }
                index += 3
            } else {
                // HTTP request targets must not contain whitespace or control characters.
                guard bytes[index] > 32, bytes[index] < 127 else { return false }
                index += 1
            }
        }
        return true
    }
}

/// Single-use IPv4 loopback listener. All mutable state belongs to its serial queue.
/// A valid callback is delivered only after the complete HTTP response has been sent.
final class ChatGPTLoopbackListener: @unchecked Sendable {
    enum Failure: LocalizedError {
        case unavailable, timedOut, alreadyStarted, alreadyWaiting

        var errorDescription: String? {
            switch self {
            case .unavailable: return "Couldn't open the local ChatGPT sign-in callback. Try again."
            case .timedOut: return "ChatGPT sign-in timed out. Return to NOOP and try again."
            case .alreadyStarted, .alreadyWaiting: return "A ChatGPT sign-in is already running."
            }
        }
    }

    private final class Incoming {
        let connection: NWConnection
        var bytes = Data()
        var timeout: DispatchSourceTimer?
        init(_ connection: NWConnection) { self.connection = connection }
    }

    private let queue = DispatchQueue(label: "com.noop.chatgpt.loopback")
    private let timeoutInterval: TimeInterval
    private var listener: NWListener?
    private var deadline: DispatchSourceTimer?
    private var incoming: [UUID: Incoming] = [:]
    private var started = false
    private var redirectURI: URL?
    private var expectedState: String?
    private var callbackClaimed = false
    private var claimedConnectionID: UUID?
    private var terminal: Result<URL, Error>?
    private var ready: CheckedContinuation<URL, Error>?
    private var callback: CheckedContinuation<URL, Error>?

    init(timeoutInterval: TimeInterval = 600) { self.timeoutInterval = timeoutInterval }

    func start() async throws -> URL {
        try Task.checkCancellation()
        return try await withTaskCancellationHandler(operation: {
            try await withCheckedThrowingContinuation { continuation in
                queue.async { [self] in
                    if let terminal {
                        switch terminal {
                        case .success: continuation.resume(throwing: Failure.alreadyStarted)
                        case .failure(let error): continuation.resume(throwing: error)
                        }
                        return
                    }
                    guard !started else { continuation.resume(throwing: Failure.alreadyStarted); return }
                    started = true
                    ready = continuation
                    do {
                        let parameters = NWParameters.tcp
                        parameters.requiredLocalEndpoint = .hostPort(host: .ipv4(.loopback), port: .any)
                        parameters.acceptLocalOnly = true
                        parameters.allowLocalEndpointReuse = false
                        let listener = try NWListener(using: parameters, on: .any)
                        self.listener = listener
                        listener.stateUpdateHandler = { [weak self] state in self?.listenerChanged(state) }
                        listener.newConnectionHandler = { [weak self] connection in self?.accept(connection) }
                        let deadline = DispatchSource.makeTimerSource(queue: queue)
                        deadline.schedule(deadline: .now() + timeoutInterval)
                        deadline.setEventHandler { [weak self] in self?.finish(.failure(Failure.timedOut)) }
                        self.deadline = deadline
                        deadline.resume()
                        listener.start(queue: queue)
                    } catch {
                        finish(.failure(Failure.unavailable))
                    }
                }
            }
        }, onCancel: { [self] in cancel() })
    }

    /// Install state before presenting the browser. This is local memory only, never a log or response.
    func expectCallback(state: String) {
        queue.sync { expectedState = state }
    }

    func waitForCallback() async throws -> URL {
        try Task.checkCancellation()
        return try await withTaskCancellationHandler(operation: {
            try await withCheckedThrowingContinuation { continuation in
                queue.async { [self] in
                    if let terminal { continuation.resume(with: terminal); return }
                    guard callback == nil else { continuation.resume(throwing: Failure.alreadyWaiting); return }
                    callback = continuation
                }
            }
        }, onCancel: { [self] in cancel() })
    }

    func cancel() {
        queue.async { [self] in finish(.failure(CancellationError())) }
    }

    private func listenerChanged(_ state: NWListener.State) {
        guard terminal == nil else { return }
        switch state {
        case .ready:
            guard let port = listener?.port, port.rawValue != 0,
                  let url = URL(string: "http://127.0.0.1:\(port.rawValue)\(ChatGPTLoopbackRequestParser.callbackPath)") else {
                finish(.failure(Failure.unavailable)); return
            }
            redirectURI = url
            ready?.resume(returning: url)
            ready = nil
        case .failed, .cancelled: finish(.failure(Failure.unavailable))
        default: break
        }
    }

    private func accept(_ connection: NWConnection) {
        guard terminal == nil, !callbackClaimed, incoming.count < 4 else { connection.cancel(); return }
        let id = UUID()
        let request = Incoming(connection)
        incoming[id] = request
        let timeout = DispatchSource.makeTimerSource(queue: queue)
        timeout.schedule(deadline: .now() + 5)
        timeout.setEventHandler { [weak self] in
            guard let self else { return }
            if self.claimedConnectionID == id { self.finish(.failure(Failure.unavailable)) }
            else { self.close(id) }
        }
        request.timeout = timeout
        timeout.resume()
        connection.start(queue: queue)
        receive(id)
    }

    private func receive(_ id: UUID) {
        guard let request = incoming[id] else { return }
        request.connection.receive(minimumIncompleteLength: 1, maximumLength: 4096) { [weak self] data, _, complete, error in
            guard let self, let request = self.incoming[id], self.terminal == nil else { return }
            if let data { request.bytes.append(data) }
            if request.bytes.count > ChatGPTLoopbackRequestParser.maximumRequestBytes {
                self.respond(id, status: ChatGPTLoopbackRequestParser.Rejection.oversized.status)
            } else if request.bytes.range(of: Data("\r\n\r\n".utf8)) != nil {
                self.process(id)
            } else if complete || error != nil {
                self.close(id)
            } else {
                self.receive(id)
            }
        }
    }

    private func process(_ id: UUID) {
        guard let request = incoming[id], let redirectURI, let expectedState, !callbackClaimed else {
            respond(id, status: "400 Bad Request"); return
        }
        do {
            let url = try ChatGPTLoopbackRequestParser.callbackURL(
                from: request.bytes, redirectURI: redirectURI, expectedState: expectedState)
            callbackClaimed = true
            claimedConnectionID = id
            // Finish writing before the coordinator dismisses the browser; no credential appears in HTML.
            respond(id, status: "200 OK", callbackURL: url)
        } catch let rejection as ChatGPTLoopbackRequestParser.Rejection {
            respond(id, status: rejection.status)
        } catch {
            respond(id, status: "400 Bad Request")
        }
    }

    private func respond(_ id: UUID, status: String, callbackURL: URL? = nil) {
        guard let request = incoming[id] else { return }
        let message = callbackURL == nil ? "This sign-in request was not accepted." : "Sign-in received. You can return to NOOP."
        let body = "<!doctype html><html><head><meta name=\"viewport\" content=\"width=device-width\"></head><body><p>\(message)</p></body></html>"
        let response = "HTTP/1.1 \(status)\r\nContent-Type: text/html; charset=utf-8\r\nContent-Length: \(body.utf8.count)\r\nConnection: close\r\nCache-Control: no-store\r\nReferrer-Policy: no-referrer\r\nContent-Security-Policy: default-src 'none'\r\n\r\n\(body)"
        request.connection.send(content: Data(response.utf8), contentContext: .finalMessage,
                                isComplete: true, completion: .contentProcessed { [weak self] error in
            guard let self, self.incoming[id] != nil else { return }
            self.close(id)
            if let callbackURL {
                self.finish(error == nil ? .success(callbackURL) : .failure(Failure.unavailable))
            }
        })
    }

    private func close(_ id: UUID) {
        guard let request = incoming.removeValue(forKey: id) else { return }
        request.timeout?.cancel()
        request.connection.cancel()
    }

    private func finish(_ result: Result<URL, Error>) {
        guard terminal == nil else { return }
        terminal = result
        expectedState = nil
        claimedConnectionID = nil
        deadline?.cancel()
        deadline = nil
        listener?.cancel()
        listener = nil
        for id in Array(incoming.keys) { close(id) }
        if let ready {
            switch result {
            case .failure(let error): ready.resume(throwing: error)
            case .success: ready.resume(throwing: Failure.unavailable)
            }
            self.ready = nil
        }
        callback?.resume(with: result)
        callback = nil
    }
}
