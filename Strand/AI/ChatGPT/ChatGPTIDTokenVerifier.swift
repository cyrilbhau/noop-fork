import Foundation
import JOSESwift
import Security

struct ChatGPTOIDCConfiguration: Decodable {
    let issuer: String
    let authorizationEndpoint: URL
    let tokenEndpoint: URL
    let jwksURI: URL
    let revocationEndpoint: URL?
    enum CodingKeys: String, CodingKey {
        case issuer, authorizationEndpoint = "authorization_endpoint", tokenEndpoint = "token_endpoint"
        case jwksURI = "jwks_uri", revocationEndpoint = "revocation_endpoint"
    }

    func validate() throws {
        guard issuer == ChatGPTAuth.issuer else { throw ChatGPTAuthError.invalidDiscovery }
        for url in [authorizationEndpoint, tokenEndpoint, jwksURI] + [revocationEndpoint].compactMap({ $0 }) {
            guard url.scheme == "https", url.host == "auth.openai.com", url.port == nil || url.port == 443,
                  url.user == nil, url.password == nil, url.fragment == nil else { throw ChatGPTAuthError.invalidDiscovery }
        }
    }
}

@MainActor
protocol ChatGPTIDTokenVerifying {
    func verify(_ token: String, clientID: String, nonce: String?, expectedSubject: String?, receivedAt: Date) async throws -> ChatGPTIdentity
}

@MainActor
final class ChatGPTIDTokenVerifier: ChatGPTIDTokenVerifying {
    private let session: URLSession
    private let now: () -> Date
    private var cachedConfiguration: ChatGPTOIDCConfiguration?
    private var cachedKeys: [[String: Any]] = []
    private var keysLoadedAt: Date?
    private var lastUnknownKeyRefresh: Date?

    init(session: URLSession = ChatGPTAuth.makeURLSession(), now: @escaping () -> Date = Date.init) {
        self.session = session
        self.now = now
    }

    func configuration() async throws -> ChatGPTOIDCConfiguration {
        if let cachedConfiguration { return cachedConfiguration }
        do {
            let data = try await fetch(ChatGPTAuth.discoveryURL)
            let config = try JSONDecoder().decode(ChatGPTOIDCConfiguration.self, from: data)
            try config.validate()
            cachedConfiguration = config
            return config
        } catch let error as ChatGPTAuthError { throw error }
        catch { throw ChatGPTAuthError.identityUnavailable }
    }

    func verify(_ token: String, clientID: String, nonce: String?, expectedSubject: String?, receivedAt: Date) async throws -> ChatGPTIdentity {
        let segments = token.split(separator: ".", omittingEmptySubsequences: false)
        guard segments.count == 3, token.utf8.count <= 128_000,
              let headerData = Self.base64Data(String(segments[0])),
              let header = (try? JSONSerialization.jsonObject(with: headerData)) as? [String: Any],
              header["alg"] as? String == "RS256", let kid = header["kid"] as? String, !kid.isEmpty,
              header["jku"] == nil, header["x5u"] == nil, header["jwk"] == nil,
              header["crit"] == nil, header["b64"] == nil else { throw ChatGPTAuthError.invalidIdentity }
        let config = try await configuration()
        if keysLoadedAt == nil || now().timeIntervalSince(keysLoadedAt!) > 900 {
            try await loadKeys(config.jwksURI)
        }
        var matching = matchingKeys(kid)
        if matching.isEmpty, lastUnknownKeyRefresh == nil || now().timeIntervalSince(lastUnknownKeyRefresh!) > 30 {
            lastUnknownKeyRefresh = now()
            try await loadKeys(config.jwksURI)
            matching = matchingKeys(kid)
        }
        guard matching.count == 1 else { throw ChatGPTAuthError.identityUnavailable }
        do {
            let keyData = try JSONSerialization.data(withJSONObject: matching[0])
            let publicKey: SecKey = try RSAPublicKey(data: keyData).converted(to: SecKey.self)
            guard let verifier = Verifier(signatureAlgorithm: .RS256, key: publicKey) else { throw ChatGPTAuthError.invalidIdentity }
            let verified = try JWS(compactSerialization: token).validate(using: verifier)
            let claims = try JSONDecoder().decode(Claims.self, from: verified.payload.data())
            guard claims.iss == config.issuer, !claims.sub.isEmpty, claims.aud.values.contains(clientID),
                  claims.exp.isFinite, claims.iat.isFinite,
                  claims.exp > now().timeIntervalSince1970 - 5,
                  claims.iat <= receivedAt.timeIntervalSince1970 + 5,
                  claims.nbf == nil || claims.nbf! <= now().timeIntervalSince1970 + 5,
                  nonce == nil || claims.nonce == nonce,
                  expectedSubject == nil || claims.sub == expectedSubject,
                  claims.azp == nil || claims.azp == clientID,
                  claims.aud.values.count < 2 || claims.azp == clientID else { throw ChatGPTAuthError.invalidIdentity }
            return ChatGPTIdentity(issuer: claims.iss, subject: claims.sub, email: claims.email, name: claims.name)
        } catch { throw ChatGPTAuthError.invalidIdentity }
    }

    private func matchingKeys(_ kid: String) -> [[String: Any]] {
        cachedKeys.filter {
            ($0["kid"] as? String) == kid && ($0["kty"] as? String) == "RSA"
                && ($0["alg"] == nil || ($0["alg"] as? String) == "RS256")
                && ($0["use"] == nil || ($0["use"] as? String) == "sig")
                && ($0["key_ops"] == nil || ($0["key_ops"] as? [String])?.contains("verify") == true)
        }
    }

    private func loadKeys(_ url: URL) async throws {
        do {
            let data = try await fetch(url)
            guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let keys = object["keys"] as? [[String: Any]], !keys.isEmpty, keys.count <= 100 else {
                throw ChatGPTAuthError.identityUnavailable
            }
            cachedKeys = keys
            keysLoadedAt = now()
        } catch { throw ChatGPTAuthError.identityUnavailable }
    }

    private func fetch(_ url: URL) async throws -> Data {
        let (data, response) = try await session.data(for: URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 15))
        guard let http = response as? HTTPURLResponse, http.statusCode == 200,
              response.url == url, data.count <= 1_000_000 else { throw ChatGPTAuthError.identityUnavailable }
        return data
    }

    private static func base64Data(_ value: String) -> Data? {
        var base64 = value.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        base64 += String(repeating: "=", count: (4 - base64.count % 4) % 4)
        return Data(base64Encoded: base64)
    }

    private struct Claims: Decodable {
        let iss: String
        let sub: String
        let aud: Audience
        let exp: Double
        let iat: Double
        let nbf: Double?
        let nonce: String?
        let azp: String?
        let email: String?
        let name: String?
    }
    private enum Audience: Decodable {
        case one(String), many([String])
        init(from decoder: Decoder) throws {
            let value = try decoder.singleValueContainer()
            if let string = try? value.decode(String.self) { self = .one(string) }
            else { self = .many(try value.decode([String].self)) }
        }
        var values: [String] {
            switch self { case let .one(value): return [value]; case let .many(values): return values }
        }
    }
}
