import Foundation
import Security

/// Keychain-backed storage for the Anthropic API key.
///
/// The key never goes into UserDefaults or the history JSON — both are
/// plain-text files any process running as the user can read.
enum KeychainStore {

    private static let service = "com.matsumedia.flow"
    private static let account = "anthropic-api-key"

    static var apiKey: String? {
        get { read() }
        set {
            if let newValue, !newValue.isEmpty {
                write(newValue)
            } else {
                delete()
            }
        }
    }

    static var hasAPIKey: Bool {
        guard let key = read() else { return false }
        return !key.isEmpty
    }

    // MARK: -

    private static func read() -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]

        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
            let data = item as? Data
        else { return nil }

        return String(data: data, encoding: .utf8)
    }

    private static func write(_ value: String) {
        guard let data = value.data(using: .utf8) else { return }

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]

        // Update in place if it exists, otherwise add.
        let status = SecItemUpdate(
            query as CFDictionary,
            [kSecValueData as String: data] as CFDictionary
        )

        if status == errSecItemNotFound {
            var attributes = query
            attributes[kSecValueData as String] = data
            attributes[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
            SecItemAdd(attributes as CFDictionary, nil)
        }
    }

    private static func delete() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(query as CFDictionary)
    }
}
