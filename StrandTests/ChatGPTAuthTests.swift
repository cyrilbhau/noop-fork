import CryptoKit
import Foundation
import JOSESwift
import Security
import XCTest
@testable import Strand

final class ChatGPTAuthTests: XCTestCase {
    private let redirect = URL(string: "http://127.0.0.1:1455/auth/callback")!

    func testInitialAuthorizationUsesDynamicRegistrationAndFreshPKCE() throws {
        let first = try ChatGPTAuth.makeAttempt(redirectURI: redirect, hostID: "urn:uuid:host", profile: nil)
        let second = try ChatGPTAuth.makeAttempt(redirectURI: redirect, hostID: "urn:uuid:host", profile: nil)
        let query = Dictionary(uniqueKeysWithValues: URLComponents(url: first.authorizationURL, resolvingAgainstBaseURL: false)!.queryItems!.map { ($0.name, $0.value!) })
        XCTAssertEqual(query["client_id"], "dynamic_agent_client")
        XCTAssertEqual(query["agent_name_hint"], "Noop")
        XCTAssertEqual(query["ext_agent_host_id"], "urn:uuid:host")
        XCTAssertEqual(query["scope"], ChatGPTAuth.scopes)
        XCTAssertEqual(query["resource"], "https://api.openai.com/v1")
        XCTAssertEqual(query["redirect_uri"], redirect.absoluteString)
        XCTAssertEqual(query["code_challenge_method"], "S256")
        XCTAssertEqual(query["code_challenge"], ChatGPTAuth.base64URL(Data(SHA256.hash(data: Data(first.verifier.utf8)))))
        XCTAssertNotEqual(first.state, second.state)
        XCTAssertNotEqual(first.nonce, second.nonce)
        XCTAssertNotEqual(first.verifier, second.verifier)
        XCTAssertFalse(first.verifier.contains("="))
    }

    func testReturningRegistrationRetainsIdentityHintsAndRequestsConsentOnlyExplicitly() throws {
        let profile = ChatGPTProfile(id: "p", clientID: "oaiapp_saved", issuer: ChatGPTAuth.issuer, subject: "sub", email: "me@example.com", name: nil, label: "Connection 1")
        let attempt = try ChatGPTAuth.makeAttempt(redirectURI: redirect, hostID: "urn:uuid:host", profile: profile, retainedIDToken: "retained", requestConsent: true)
        let query = URLComponents(url: attempt.authorizationURL, resolvingAgainstBaseURL: false)!.queryItems!
        XCTAssertFalse(query.contains { $0.name == "agent_name_hint" })
        XCTAssertEqual(query.first { $0.name == "client_id" }?.value, "oaiapp_saved")
        XCTAssertEqual(query.first { $0.name == "id_token_hint" }?.value, "retained")
        XCTAssertEqual(query.first { $0.name == "prompt" }?.value, "consent")
        let result = try ChatGPTAuth.parseCallback(url: callback(attempt, "code=returning"), attempt: attempt)
        XCTAssertEqual(result.clientID, profile.clientID)
        XCTAssertThrowsError(try ChatGPTAuth.parseCallback(url: callback(attempt, "code=x&client_id=oaiapp_other"), attempt: attempt))
    }

    func testRejectsCallbackConfusionAndMismatchedStateBeforeDenial() throws {
        let attempt = try ChatGPTAuth.makeAttempt(redirectURI: redirect, hostID: "urn:uuid:host", profile: nil)
        for suffix in ["code=x", "code=x&client_id=dynamic_agent_client", "code=x&client_id=oaiapp_ok&state=duplicate", "code=x&client_id=oaiapp_ok&error=access_denied", "code=x&client_id=oaiapp_ok&iss=https%3A%2F%2Fevil.example"] {
            XCTAssertThrowsError(try ChatGPTAuth.parseCallback(url: callback(attempt, suffix), attempt: attempt))
        }
        let good = try ChatGPTAuth.parseCallback(url: callback(attempt, "code=one&client_id=oaiapp_ok"), attempt: attempt)
        XCTAssertEqual(good.code, "one")
        XCTAssertThrowsError(try ChatGPTAuth.parseCallback(url: URL(string: redirect.absoluteString + "?state=wrong&error=access_denied")!, attempt: attempt)) {
            guard case ChatGPTAuthError.stateMismatch = $0 else { return XCTFail("Expected state mismatch") }
        }
    }

    func testOnlyDocumentedLoopbackURIIsAccepted() {
        for value in ["http://localhost:1455/auth/callback", "noop://auth/callback", "http://127.0.0.1:1455/callback", "http://127.0.0.1:1455/auth/callback?x=y", "http://127.0.0.1/auth/callback"] {
            XCTAssertThrowsError(try ChatGPTAuth.makeAttempt(redirectURI: URL(string: value)!, hostID: "host", profile: nil))
        }
    }

    func testFormEncodingDoesNotTurnReservedCodeCharactersIntoParameters() {
        let request = ChatGPTAuth.formRequest(url: ChatGPTAuth.tokenEndpoint, fields: ["code": "a+b&x=1 /é"])
        XCTAssertEqual(String(data: request.httpBody!, encoding: .utf8), "code=a%2Bb%26x%3D1%20%2F%C3%A9")
    }

    func testRefreshHintUsesOfficialDevkitUnitsAndPreservesUnknownHint() throws {
        let seconds = try JSONDecoder().decode(ChatGPTRefreshHint.self, from: Data("1790032532".utf8))
        XCTAssertEqual(seconds.date, Date(timeIntervalSince1970: 1_790_032_532))
        let string = try JSONDecoder().decode(ChatGPTRefreshHint.self, from: Data("\"2026-10-28T10:00:00Z\"".utf8))
        XCTAssertNotNil(string.date)
        let unknown = try JSONDecoder().decode(ChatGPTRefreshHint.self, from: Data("true".utf8))
        XCTAssertNil(unknown.date)
    }

    @MainActor
    func testRealSignedIDTokenAndStrictClaimRejection() async throws {
        let fixture = try ChatGPTJWTFixture()
        let session = ChatGPTTestURLProtocol.session { request in
            if request.url == ChatGPTAuth.discoveryURL { return (200, ChatGPTTestURLProtocol.discovery) }
            return (200, try JSONSerialization.data(withJSONObject: ["keys": [fixture.jwk]]))
        }
        let date = Date(timeIntervalSince1970: 1_800_000_000)
        let verifier = ChatGPTIDTokenVerifier(session: session, now: { date })
        let valid = try fixture.token(at: date)
        let identity = try await verifier.verify(valid, clientID: "oaiapp_test", nonce: "nonce", expectedSubject: "subject", receivedAt: date)
        XCTAssertEqual(identity.subject, "subject")
        let overrides: [[String: Any]] = [["iss": "https://evil.example"], ["aud": "oaiapp_other"], ["nonce": "wrong"], ["exp": date.timeIntervalSince1970 - 60], ["iat": date.timeIntervalSince1970 + 60], ["azp": "other"]]
        for override in overrides {
            do {
                _ = try await verifier.verify(fixture.token(at: date, overriding: override), clientID: "oaiapp_test", nonce: "nonce", expectedSubject: "subject", receivedAt: date)
                XCTFail("Invalid ID-token claims accepted")
            } catch { XCTAssertTrue(error is ChatGPTAuthError) }
        }
        let otherKey = try ChatGPTJWTFixture()
        do {
            _ = try await verifier.verify(otherKey.token(at: date), clientID: "oaiapp_test", nonce: "nonce", expectedSubject: "subject", receivedAt: date)
            XCTFail("Invalid signature accepted")
        } catch { XCTAssertTrue(error is ChatGPTAuthError) }
        let laterVerifier = ChatGPTIDTokenVerifier(session: session, now: { date.addingTimeInterval(7200) })
        do {
            _ = try await laterVerifier.verify(valid, clientID: "oaiapp_test", nonce: "nonce", expectedSubject: "subject", receivedAt: date)
            XCTFail("A pending checkpoint must not validate an already expired ID token")
        } catch { XCTAssertTrue(error is ChatGPTAuthError) }
    }

    @MainActor
    func testUnsignedTokenAndUntrustedDiscoveryOriginAreRejected() async throws {
        let date = Date(timeIntervalSince1970: 1_800_000_000)
        let session = ChatGPTTestURLProtocol.session { _ in
            (200, Data("{\"issuer\":\"https://auth.openai.com\",\"authorization_endpoint\":\"https://auth.openai.com/authorize\",\"token_endpoint\":\"https://auth.openai.com/token\",\"jwks_uri\":\"https://evil.example/keys\"}".utf8))
        }
        let verifier = ChatGPTIDTokenVerifier(session: session, now: { date })
        let unsigned = ChatGPTAuth.base64URL(Data("{\"alg\":\"none\",\"kid\":\"test-key\"}".utf8)) + ".e30."
        do {
            _ = try await verifier.verify(unsigned, clientID: "oaiapp_test", nonce: nil, expectedSubject: nil, receivedAt: date)
            XCTFail("Unsigned ID token accepted")
        } catch { XCTAssertTrue(error is ChatGPTAuthError) }
        do { _ = try await verifier.configuration(); XCTFail("Untrusted JWKS origin accepted") }
        catch { XCTAssertTrue(error is ChatGPTAuthError) }
    }

    @MainActor
    func testUnknownSigningKeyTriggersOneBoundedJWKSRefresh() async throws {
        let old = try ChatGPTJWTFixture(kid: "old-key")
        let new = try ChatGPTJWTFixture(kid: "new-key")
        let loads = ChatGPTJWTKeyLoads()
        let session = ChatGPTTestURLProtocol.session { request in
            if request.url == ChatGPTAuth.discoveryURL { return (200, ChatGPTTestURLProtocol.discovery) }
            let key = loads.next() == 1 ? old.jwk : new.jwk
            return (200, try JSONSerialization.data(withJSONObject: ["keys": [key]]))
        }
        let date = Date(timeIntervalSince1970: 1_800_000_000)
        let verifier = ChatGPTIDTokenVerifier(session: session, now: { date })
        _ = try await verifier.verify(old.token(at: date), clientID: "oaiapp_test", nonce: "nonce", expectedSubject: "subject", receivedAt: date)
        _ = try await verifier.verify(new.token(at: date), clientID: "oaiapp_test", nonce: "nonce", expectedSubject: "subject", receivedAt: date)
        XCTAssertEqual(loads.count, 2)
    }

    private func callback(_ attempt: ChatGPTAuthorizationAttempt, _ suffix: String) -> URL {
        URL(string: redirect.absoluteString + "?state=" + attempt.state + "&" + suffix)!
    }
}

private struct ChatGPTJWTFixture {
    let privateKey: SecKey
    let jwk: [String: Any]
    let kid: String
    init(kid: String = "test-key") throws {
        let attributes = [kSecAttrKeyType as String: kSecAttrKeyTypeRSA, kSecAttrKeySizeInBits as String: 2048] as CFDictionary
        var error: Unmanaged<CFError>?
        guard let key = SecKeyCreateRandomKey(attributes, &error), let publicKey = SecKeyCopyPublicKey(key) else {
            throw ChatGPTAuthError.invalidIdentity
        }
        privateKey = key
        self.kid = kid
        let json = try RSAPublicKey(publicKey: publicKey).jsonString()!
        var object = try JSONSerialization.jsonObject(with: Data(json.utf8)) as! [String: Any]
        object["kid"] = kid
        object["alg"] = "RS256"
        object["use"] = "sig"
        jwk = object
    }
    func token(at date: Date, overriding: [String: Any] = [:]) throws -> String {
        var claims: [String: Any] = ["iss": ChatGPTAuth.issuer, "sub": "subject", "aud": "oaiapp_test", "nonce": "nonce", "iat": date.timeIntervalSince1970, "exp": date.addingTimeInterval(3600).timeIntervalSince1970]
        claims.merge(overriding, uniquingKeysWith: { _, new in new })
        var header = JWSHeader(algorithm: .RS256)
        header.kid = kid
        let signer = Signer(signatureAlgorithm: .RS256, key: privateKey)!
        return try JWS(header: header, payload: Payload(JSONSerialization.data(withJSONObject: claims)), signer: signer).compactSerializedString
    }
}

private final class ChatGPTJWTKeyLoads {
    private let lock = NSLock()
    private var value = 0
    var count: Int { lock.lock(); defer { lock.unlock() }; return value }
    func next() -> Int { lock.lock(); defer { lock.unlock() }; value += 1; return value }
}
