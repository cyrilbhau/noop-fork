import Foundation
import Security

struct ChatGPTRegistration: Codable, Equatable {
    var profile: ChatGPTProfile
    var tokens: ChatGPTTokens?
    // A rotated token is saved before refreshed ID-token verification can await JWKS.
    // It is never usable for inference until verification and final persistence succeed.
    var pendingRefresh: ChatGPTTokens?
    var identityOnlyIDToken: String? = nil
    var identityOnlyScopes: Set<String>? = nil
}

struct ChatGPTStoredState: Codable, Equatable {
    var version = 1
    var hostID: String
    var registrations: [ChatGPTRegistration] = []
    var pendingClientID: String?
    var activeProfileID: String?
}

@MainActor
protocol ChatGPTCredentialStoring {
    func load() throws -> ChatGPTStoredState?
    func save(_ value: ChatGPTStoredState) throws
}

@MainActor
final class ChatGPTCredentialStore: ChatGPTCredentialStoring {
    private let service: String
    private let account = "subscription-state-v1"

    init(service: String = "com.noop.chatgpt.subscription") { self.service = service }

    func load() throws -> ChatGPTStoredState? {
        var query = baseQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = result as? Data,
              let decoded = try? JSONDecoder().decode(ChatGPTStoredState.self, from: data), decoded.version == 1 else {
            // An inaccessible or malformed entry is not permission to replace credentials.
            throw ChatGPTAuthError.persistenceFailed
        }
        return decoded
    }

    func save(_ value: ChatGPTStoredState) throws {
        let data = try JSONEncoder().encode(value)
        let attributes: [String: Any] = [kSecValueData as String: data,
                                       kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly]
        var status = SecItemUpdate(baseQuery as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            var insertion = baseQuery
            insertion.merge(attributes, uniquingKeysWith: { _, new in new })
            status = SecItemAdd(insertion as CFDictionary, nil)
            if status == errSecDuplicateItem { status = SecItemUpdate(baseQuery as CFDictionary, attributes as CFDictionary) }
        }
        guard status == errSecSuccess else { throw ChatGPTAuthError.persistenceFailed }
    }

    private var baseQuery: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
         kSecAttrAccount as String: account, kSecAttrSynchronizable as String: false]
    }
}
