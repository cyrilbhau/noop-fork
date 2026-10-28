import Foundation
import XCTest

/// Exercises the callback's HTTP boundary without presenting a browser or contacting a provider.
final class ChatGPTLoopbackListenerTests: XCTestCase {
    private let redirect = URL(string: "http://127.0.0.1:43210/auth/callback")!

    private func request(_ target: String, method: String = "GET", host: String = "127.0.0.1:43210",
                         extraHeaders: String = "", body: String = "") -> Data {
        Data("\(method) \(target) HTTP/1.1\r\nHost: \(host)\r\n\(extraHeaders)\r\n\(body)".utf8)
    }

    private func parse(_ data: Data) throws -> URL {
        try ChatGPTLoopbackRequestParser.callbackURL(from: data, redirectURI: redirect, expectedState: "nonce")
    }

    func testAcceptsEncodedCodeAndPreservesDynamicClientID() throws {
        let callback = try parse(request("/auth/callback?state=nonce&code=a%2Bb%2Fc%3D&client_id=personal-client"))
        XCTAssertEqual(callback.host, "127.0.0.1")
        XCTAssertEqual(callback.port, 43210)
        XCTAssertEqual(callback.path, "/auth/callback")
        let query = URLComponents(url: callback, resolvingAgainstBaseURL: false)?.queryItems
        XCTAssertEqual(query?.first(where: { $0.name == "code" })?.value, "a+b/c=")
        XCTAssertEqual(query?.first(where: { $0.name == "client_id" })?.value, "personal-client")
    }

    func testAcceptsProviderErrorOnlyWithMatchingState() throws {
        XCTAssertNoThrow(try parse(request("/auth/callback?state=nonce&error=access_denied")))
        XCTAssertThrowsError(try parse(request("/auth/callback?state=other&error=access_denied")))
    }

    func testRejectsMissingEmptyMismatchedAndDuplicateState() {
        for query in ["code=x", "state=&code=x", "state=other&code=x",
                      "state=nonce&state=nonce&code=x", "state=nonce&state=other&code=x"] {
            XCTAssertThrowsError(try parse(request("/auth/callback?\(query)")))
        }
    }

    func testRejectsAmbiguousOrMissingAuthorizationResult() {
        for query in ["state=nonce", "state=nonce&code=", "state=nonce&code=x&code=y",
                      "state=nonce&error=", "state=nonce&code=x&error=denied",
                      "state=nonce&code=&error=denied", "state=nonce&code=x&client_id=a&client_id=b"] {
            XCTAssertThrowsError(try parse(request("/auth/callback?\(query)")))
        }
    }

    func testRejectsOtherPathsMethodsAndAuthorityForms() {
        for target in ["/favicon.ico?state=nonce&code=x", "/auth/callback/?state=nonce&code=x",
                       "/%61uth/callback?state=nonce&code=x", "//example.com/auth/callback?state=nonce&code=x",
                       "http://127.0.0.1:43210/auth/callback?state=nonce&code=x",
                       "/auth/callback?state=nonce&code=x#fragment", "/auth/callback?state=nonce&code=%ZZ"] {
            XCTAssertThrowsError(try parse(request(target)))
        }
        XCTAssertThrowsError(try parse(request("/auth/callback?state=nonce&code=x", method: "POST")))
        XCTAssertThrowsError(try parse(request("/auth/callback?state=nonce&code=x", method: "HEAD")))
    }

    func testRejectsWrongOrDuplicateHostAndRequestBodies() {
        let target = "/auth/callback?state=nonce&code=x"
        for host in ["localhost:43210", "127.0.0.1:43211", "example.com", "127.0.0.1"] {
            XCTAssertThrowsError(try parse(request(target, host: host)))
        }
        XCTAssertThrowsError(try parse(request(target, extraHeaders: "Host: 127.0.0.1:43210\r\n")))
        XCTAssertThrowsError(try parse(request(target, extraHeaders: "Transfer-Encoding: chunked\r\n")))
        XCTAssertThrowsError(try parse(request(target, extraHeaders: "Content-Length: 1\r\n", body: "x")))
        XCTAssertThrowsError(try parse(request(target, body: "x")))
        XCTAssertNoThrow(try parse(request(target, extraHeaders: "Content-Length: 0\r\n")))
    }

    func testRejectsOversizedIncompleteAndInvalidUTF8Requests() {
        XCTAssertThrowsError(try parse(Data(repeating: 65, count: ChatGPTLoopbackRequestParser.maximumRequestBytes + 1)))
        XCTAssertThrowsError(try parse(Data("GET /auth/callback?state=nonce&code=x HTTP/1.1\r\nHost: 127.0.0.1:43210\r\n".utf8)))
        XCTAssertThrowsError(try parse(Data([0xff, 0xfe, 0xfd])))
    }
}
