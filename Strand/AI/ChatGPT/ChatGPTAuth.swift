import CryptoKit
import Foundation
import Security

enum ChatGPTAuthError: Error, LocalizedError {
    case invalidCallback, stateMismatch, accessDenied, invalidClient, invalidIdentity
    case signInRequired, planPermissionRequired, busy, cancelled, invalidTokenResponse
    case persistenceFailed, refreshNotReady, identityUnavailable, invalidDiscovery
    case remote(status: Int, code: String?, requestID: String?)

    var errorDescription: String? {
        switch self {
        case .invalidCallback: return "ChatGPT returned an invalid sign-in callback. Try again."
        case .stateMismatch: return "The sign-in callback did not match this attempt. Try again."
        case .accessDenied: return "ChatGPT sign-in was cancelled or permission was declined."
        case .invalidClient: return "The ChatGPT registration did not match this connection."
        case .invalidIdentity: return "The ChatGPT identity could not be verified. Sign in again."
        case .signInRequired: return "Sign in with ChatGPT to continue."
        case .planPermissionRequired: return "Enable ChatGPT plan usage for this connection to continue."
        case .busy: return "Finish the current ChatGPT connection change first."
        case .cancelled: return "ChatGPT sign-in or the request was cancelled."
        case .invalidTokenResponse: return "ChatGPT returned incomplete credentials. Sign in again."
        case .persistenceFailed: return "The ChatGPT connection could not be saved securely. Unlock the phone and try again."
        case .refreshNotReady: return "This ChatGPT connection cannot refresh yet. Try again shortly."
        case .identityUnavailable: return "ChatGPT identity verification is temporarily unavailable. Try again shortly."
        case .invalidDiscovery: return "ChatGPT sign-in configuration could not be verified."
        case let .remote(status, code, _):
            if Self.terminalRefreshCodes.contains(code ?? "") { return "This ChatGPT connection expired or was disconnected. Sign in again." }
            return "ChatGPT could not complete the connection request (HTTP \(status)). Try again."
        }
    }

    static let terminalRefreshCodes: Set<String> = ["invalid_grant", "invalid_refresh_token", "token_expired", "refresh_token_expired", "refresh_token_invalidated", "refresh_token_reused"]
    var isTerminalRefresh: Bool {
        if case let .remote(_, code, _) = self { return Self.terminalRefreshCodes.contains(code ?? "") }
        return false
    }
}

struct ChatGPTAuthorizationAttempt {
    let id: UUID
    let redirectURI: URL
    let state: String
    let nonce: String
    let verifier: String
    let authorizationURL: URL
    let profileID: String?
    let clientID: String
    let createdAt: Date
}

struct ChatGPTAuthorizationCallback {
    let code: String
    let clientID: String
}

struct ChatGPTIdentity: Codable, Equatable {
    let issuer: String
    let subject: String
    let email: String?
    let name: String?
}

struct ChatGPTProfile: Codable, Identifiable, Equatable {
    let id: String
    let clientID: String
    let issuer: String
    let subject: String
    var email: String?
    var name: String?
    var label: String
}

// The official SIWC devkit accepts numeric Unix seconds or a date string here:
// github.com/openai/sign-in-with-chatgpt-devkit/blob/main/packages/local/src/index.ts
enum ChatGPTRefreshHint: Codable, Equatable {
    case seconds(Double), dateString(String), unrecognized

    init(from decoder: Decoder) throws {
        let value = try decoder.singleValueContainer()
        if let seconds = try? value.decode(Double.self), seconds.isFinite { self = .seconds(seconds) }
        else if let string = try? value.decode(String.self) { self = .dateString(string) }
        else { self = .unrecognized }
    }
    func encode(to encoder: Encoder) throws {
        var value = encoder.singleValueContainer()
        switch self {
        case let .seconds(seconds): try value.encode(seconds)
        case let .dateString(string): try value.encode(string)
        case .unrecognized: try value.encode(false)
        }
    }
    var date: Date? {
        switch self {
        case let .seconds(seconds): return Date(timeIntervalSince1970: seconds)
        case let .dateString(string):
            let format = ISO8601DateFormatter()
            format.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            return format.date(from: string) ?? ISO8601DateFormatter().date(from: string)
        case .unrecognized: return nil
        }
    }
}

struct ChatGPTTokens: Codable, Equatable {
    var accessToken: String
    var refreshToken: String?
    var idToken: String?
    var expiresAt: Date
    var scopes: Set<String>
    var earliestRefreshAt: ChatGPTRefreshHint?
    var receivedAt: Date
    var requiresIdentityVerification: Bool? = nil
}

struct ChatGPTTokenResponse: Decodable {
    let accessToken: String?
    let refreshToken: String?
    let idToken: String?
    let tokenType: String?
    let expiresIn: Double?
    let scope: String?
    let earliestRefreshAt: ChatGPTRefreshHint?
    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token", refreshToken = "refresh_token", idToken = "id_token"
        case tokenType = "token_type", expiresIn = "expires_in", scope
        case earliestRefreshAt = "earliest_refresh_at"
    }

    func optionalTokens(at date: Date) throws -> ChatGPTTokens? {
        guard let scope else { throw ChatGPTAuthError.invalidTokenResponse }
        let granted = Set(scope.split(whereSeparator: { $0.isWhitespace }).map(String.init))
        if accessToken?.isEmpty == false || granted.contains(ChatGPTAuth.planScope) || granted.contains("offline_access") {
            return try tokens(at: date)
        }
        // Identity-only OAuth may legitimately have no inference credentials.
        // It still requires verified identity and its granted scopes are retained.
        return nil
    }

    func tokens(at date: Date, prior: ChatGPTTokens? = nil) throws -> ChatGPTTokens {
        guard let accessToken, !accessToken.isEmpty, tokenType?.lowercased() == "bearer",
              let expiresIn, expiresIn.isFinite, expiresIn > 0,
              let granted = scope ?? prior.map({ $0.scopes.sorted().joined(separator: " ") }) else {
            throw ChatGPTAuthError.invalidTokenResponse
        }
        let scopes = Set(granted.split(whereSeparator: { $0.isWhitespace }).map(String.init))
        if prior != nil || scopes.contains("offline_access") {
            guard let refreshToken, !refreshToken.isEmpty else { throw ChatGPTAuthError.invalidTokenResponse }
        }
        if let idToken, idToken.isEmpty { throw ChatGPTAuthError.invalidIdentity }
        return ChatGPTTokens(accessToken: accessToken, refreshToken: refreshToken,
                             idToken: idToken ?? prior?.idToken,
                             expiresAt: date.addingTimeInterval(expiresIn), scopes: scopes,
                             earliestRefreshAt: earliestRefreshAt, receivedAt: date,
                             requiresIdentityVerification: idToken != nil)
    }
}

enum ChatGPTAuth {
    static let issuer = "https://auth.openai.com"
    static let resource = "https://api.openai.com/v1"
    static let authorizationEndpoint = URL(string: issuer + "/api/accounts/authorize")!
    static let tokenEndpoint = URL(string: issuer + "/api/accounts/oauth/token")!
    static let discoveryURL = URL(string: issuer + "/.well-known/openid-configuration")!
    static let planScope = "chatgpt.tokens.use.direct"
    static let scopes = "openid profile email offline_access resource.invoke chatgpt.tokens.use.direct"
    static let dynamicClientID = "dynamic_agent_client"

    static func randomValue() throws -> String {
        var bytes = [UInt8](repeating: 0, count: 32)
        guard SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes) == errSecSuccess else {
            throw ChatGPTAuthError.invalidCallback
        }
        return base64URL(Data(bytes))
    }

    static func base64URL(_ data: Data) -> String {
        data.base64EncodedString().replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
    }

    static func makeAttempt(redirectURI: URL, hostID: String, profile: ChatGPTProfile?,
                            retainedIDToken: String? = nil, pendingClientID: String? = nil,
                            requestConsent: Bool = false, now: Date = Date()) throws -> ChatGPTAuthorizationAttempt {
        guard let parts = URLComponents(url: redirectURI, resolvingAgainstBaseURL: false),
              parts.scheme == "http", parts.host == "127.0.0.1", parts.path == "/auth/callback",
              let port = parts.port, (1...65535).contains(port), parts.query == nil,
              parts.fragment == nil, parts.user == nil, parts.password == nil else {
            throw ChatGPTAuthError.invalidCallback
        }
        let state = try randomValue(), nonce = try randomValue(), verifier = try randomValue()
        let clientID = profile?.clientID ?? pendingClientID ?? dynamicClientID
        var query = [URLQueryItem(name: "client_id", value: clientID),
                     URLQueryItem(name: "response_type", value: "code"),
                     URLQueryItem(name: "redirect_uri", value: redirectURI.absoluteString),
                     URLQueryItem(name: "scope", value: scopes), URLQueryItem(name: "resource", value: resource),
                     URLQueryItem(name: "ext_agent_host_id", value: hostID),
                     URLQueryItem(name: "state", value: state), URLQueryItem(name: "nonce", value: nonce),
                     URLQueryItem(name: "code_challenge_method", value: "S256"),
                     URLQueryItem(name: "code_challenge", value: base64URL(Data(SHA256.hash(data: Data(verifier.utf8)))))]
        if clientID == dynamicClientID { query.append(URLQueryItem(name: "agent_name_hint", value: "Noop")) }
        if let retainedIDToken { query.append(URLQueryItem(name: "id_token_hint", value: retainedIDToken)) }
        if let email = profile?.email { query.append(URLQueryItem(name: "login_hint", value: email)) }
        if requestConsent { query.append(URLQueryItem(name: "prompt", value: "consent")) }
        var authorization = URLComponents(url: authorizationEndpoint, resolvingAgainstBaseURL: false)!
        authorization.queryItems = query
        guard let url = authorization.url else { throw ChatGPTAuthError.invalidCallback }
        return ChatGPTAuthorizationAttempt(id: UUID(), redirectURI: redirectURI, state: state, nonce: nonce,
                                            verifier: verifier, authorizationURL: url, profileID: profile?.id,
                                            clientID: clientID, createdAt: now)
    }

    static func parseCallback(url: URL, attempt: ChatGPTAuthorizationAttempt) throws -> ChatGPTAuthorizationCallback {
        guard let parts = URLComponents(url: url, resolvingAgainstBaseURL: false),
              parts.scheme == attempt.redirectURI.scheme, parts.host == "127.0.0.1",
              parts.port == attempt.redirectURI.port, parts.path == attempt.redirectURI.path,
              parts.fragment == nil, parts.user == nil, parts.password == nil else { throw ChatGPTAuthError.invalidCallback }
        let fields = Dictionary(grouping: parts.queryItems ?? [], by: \.name)
        for name in ["state", "code", "client_id", "error", "iss"] where (fields[name]?.count ?? 0) > 1 {
            throw ChatGPTAuthError.invalidCallback
        }
        guard fields["state"]?.first?.value == attempt.state else { throw ChatGPTAuthError.stateMismatch }
        if let issuer = fields["iss"]?.first?.value, issuer != Self.issuer { throw ChatGPTAuthError.invalidCallback }
        if fields["error"] != nil {
            guard fields["code"] == nil else { throw ChatGPTAuthError.invalidCallback }
            throw ChatGPTAuthError.accessDenied
        }
        guard let code = fields["code"]?.first?.value, !code.isEmpty else { throw ChatGPTAuthError.invalidCallback }
        let callbackClient = fields["client_id"]?.first?.value
        let clientID: String
        if attempt.clientID == dynamicClientID {
            guard let callbackClient, callbackClient.hasPrefix("oaiapp_"), callbackClient.count <= 512 else { throw ChatGPTAuthError.invalidClient }
            clientID = callbackClient
        } else {
            guard callbackClient == nil || callbackClient == attempt.clientID else { throw ChatGPTAuthError.invalidClient }
            clientID = attempt.clientID
        }
        return ChatGPTAuthorizationCallback(code: code, clientID: clientID)
    }

    static func formRequest(url: URL, fields: [String: String]) -> URLRequest {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-._~"))
        let body = fields.sorted(by: { $0.key < $1.key }).map {
            "\($0.key.addingPercentEncoding(withAllowedCharacters: allowed)!)=\($0.value.addingPercentEncoding(withAllowedCharacters: allowed)!)"
        }.joined(separator: "&")
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 30)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.httpBody = Data(body.utf8)
        return request
    }

    static func remoteError(data: Data, response: HTTPURLResponse) -> ChatGPTAuthError {
        let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        let nested = object?["error"] as? [String: Any]
        let raw = nested?["code"] as? String ?? object?["error"] as? String ?? object?["error_reason"] as? String
        let code = raw.flatMap { $0.count <= 100 && $0.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "_" }) ? $0 : nil }
        return .remote(status: response.statusCode, code: code, requestID: response.value(forHTTPHeaderField: "x-request-id"))
    }

    static func makeURLSession() -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.httpCookieStorage = nil
        config.httpShouldSetCookies = false
        config.urlCache = nil
        return URLSession(configuration: config, delegate: ChatGPTNoRedirectDelegate(), delegateQueue: nil)
    }
}

private final class ChatGPTNoRedirectDelegate: NSObject, URLSessionTaskDelegate {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) { completionHandler(nil) }
}
