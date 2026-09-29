import Foundation
import Security

enum KeychainStore {
    private static let services = ["com.ebanx.devnotify", "com.local.prpilot"]
    private static let account = "github-personal-access-token"

    static func loadToken() -> String {
        for service in services {
            let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
                kSecAttrAccount as String: account, kSecReturnData as String: true, kSecMatchLimit as String: kSecMatchLimitOne]
            var result: CFTypeRef?
            if SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess, let data = result as? Data,
               let token = String(data: data, encoding: .utf8) { return token }
        }
        return ""
    }

    static func saveToken(_ token: String) {
        let lookup: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: services[0], kSecAttrAccount as String: account]
        if token.isEmpty { SecItemDelete(lookup as CFDictionary); return }
        let attributes = [kSecValueData as String: Data(token.utf8)]
        if SecItemUpdate(lookup as CFDictionary, attributes as CFDictionary) == errSecItemNotFound {
            var insertion = lookup
            insertion[kSecValueData as String] = Data(token.utf8)
            SecItemAdd(insertion as CFDictionary, nil)
        }
    }
}
