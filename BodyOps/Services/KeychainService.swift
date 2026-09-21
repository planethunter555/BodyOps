import Foundation
import Security

final class KeychainService: @unchecked Sendable {
    static let shared = KeychainService()
    private static let intakeTokenKey = "com.bodyops.intake.token"

    private init() {}

    private func key(for provider: LLMProvider) -> String {
        "com.bodyops.apikey.\(provider.rawValue)"
    }

    private func save(_ value: String, keyString: String) throws {
        let keychainKey = keyString as CFString

        if value.isEmpty {
            try? delete(keyString: keyString)
            return
        }

        guard let data = value.data(using: .utf8) else { return }

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

    private func load(keyString: String) -> String? {
        let keychainKey = keyString as CFString
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

    private func delete(keyString: String) throws {
        let keychainKey = keyString as CFString
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: keychainKey
        ]
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError.deleteFailed(status)
        }
    }

    func save(apiKey: String, forProvider provider: LLMProvider) throws {
        try save(apiKey, keyString: key(for: provider))
    }

    func load(forProvider provider: LLMProvider) -> String? {
        load(keyString: key(for: provider))
    }

    func delete(forProvider provider: LLMProvider) throws {
        try delete(keyString: key(for: provider))
    }

    func saveIntakeToken(_ token: String) throws {
        try save(token, keyString: Self.intakeTokenKey)
    }

    func loadIntakeToken() -> String? {
        load(keyString: Self.intakeTokenKey)
    }

    func deleteIntakeToken() throws {
        try delete(keyString: Self.intakeTokenKey)
    }
}

enum KeychainError: Error {
    case saveFailed(OSStatus)
    case deleteFailed(OSStatus)
}
