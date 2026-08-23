import Foundation
import Security
import UsageCore

/// Reads Claude OAuth access tokens from Keychain. Never logs or refreshes tokens.
enum KeychainTokenReader {
    /// Returns the access token for the given Keychain selectors, or nil on soft failure.
    /// When `account` is nil/empty, succeeds only if the service has exactly one item.
    static func accessToken(service: String, account: String?) -> String? {
        let trimmedService = service.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedService.isEmpty else { return nil }
        let trimmedAccount = account?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let trimmedAccount, !trimmedAccount.isEmpty {
            return copyMatching(service: trimmedService, account: trimmedAccount)
        }
        return uniqueServiceToken(service: trimmedService)
    }

    private static func uniqueServiceToken(service: String) -> String? {
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
        return ClaudeOAuthToken.parseAccessToken(from: items[0])
    }

    private static func copyMatching(service: String, account: String) -> String? {
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
        return ClaudeOAuthToken.parseAccessToken(from: data)
    }
}
