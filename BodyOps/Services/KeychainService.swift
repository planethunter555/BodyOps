import Foundation
import Security

final class KeychainService: @unchecked Sendable {
    static let shared = KeychainService()

    private init() {}

    private func key(for provider: LLMProvider) -> String {
        "com.bodyops.apikey.\(provider.rawValue)"
    }

    func save(apiKey: String, forProvider provider: LLMProvider) throws {
        let keyString = key(for: provider)
        let keychainKey = keyString as CFString

        // Empty string treated as deletion
        if apiKey.isEmpty {
            try? delete(forProvider: provider)
            return
        }

        guard let data = apiKey.data(using: .utf8) else { return }

        // Delete existing entry first
        let deleteQuery: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: keychainKey
        ]
        SecItemDelete(deleteQuery as CFDictionary)

        let addQuery: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: keychainKey,
            kSecValueData: data,
            kSecAttrAccessible: kSecAttrAccessibleWhenUnlocked
        ]
        let status = SecItemAdd(addQuery as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw KeychainError.saveFailed(status)
        }
    }

    func load(forProvider provider: LLMProvider) -> String? {
        let keychainKey = key(for: provider) as CFString
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: keychainKey,
            kSecReturnData: true,
            kSecMatchLimit: kSecMatchLimitOne
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess,
              let data = result as? Data,
              let key = String(data: data, encoding: .utf8),
              !key.isEmpty else {
            return nil
        }
        return key
    }

    func delete(forProvider provider: LLMProvider) throws {
        let keychainKey = key(for: provider) as CFString
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: keychainKey
        ]
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError.deleteFailed(status)
        }
    }
}

enum KeychainError: Error {
    case saveFailed(OSStatus)
    case deleteFailed(OSStatus)
}
