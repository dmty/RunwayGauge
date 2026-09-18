import Foundation
import Security
import UsageCore

/// Reads Claude OAuth access tokens from Keychain. Never logs or refreshes tokens.
enum KeychainTokenReader {
    static func credentialData(service: String, account: String?) -> Data? {
        let trimmedService = service.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedService.isEmpty else { return nil }
        let trimmedAccount = account?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let trimmedAccount, !trimmedAccount.isEmpty {
            return copyMatching(service: trimmedService, account: trimmedAccount)
        }
        return uniqueServiceData(service: trimmedService)
    }

    private static func uniqueServiceData(service: String) -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitAll,
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess, let items = item as? [Data], items.count == 1 else {
            return nil
        }
        return items[0]
    }

    private static func copyMatching(service: String, account: String) -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess, let data = item as? Data else {
            return nil
        }
        return data
    }
}
