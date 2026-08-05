import Foundation
import Security
import UsageCore

enum KeychainDiscoveryError: LocalizedError, Sendable {
    case queryFailed(OSStatus)

    var errorDescription: String? {
        switch self {
        case .queryFailed(let status):
            secMessage(status, fallback: "Keychain query failed with status \(status).")
        }
    }
}

enum KeychainAccessResult: Sendable {
    case accessible
    case notFound
    case denied
    case failed(OSStatus)

    var message: String {
        switch self {
        case .accessible: "Credential access succeeded."
        case .notFound: "Credential was not found."
        case .denied: "Credential access was denied."
        case .failed(let status):
            secMessage(status, fallback: "Credential access failed with status \(status).")
        }
    }
}

private func secMessage(_ status: OSStatus, fallback: String) -> String {
    (SecCopyErrorMessageString(status, nil) as String?) ?? fallback
}

enum KeychainDiscovery {
    static var discoveryQuery: [CFString: Any] {
        [
            kSecClass: kSecClassGenericPassword,
            kSecMatchLimit: kSecMatchLimitAll,
            kSecReturnAttributes: true,
            kSecReturnData: false,
        ]
    }

    static func discover() async throws -> [KeychainItemDescriptor] {
        try await Task.detached(priority: .userInitiated) {
            try queryAttributes()
        }.value
    }

    static func testAccess(service: String, account: String?) async -> KeychainAccessResult {
        await Task.detached(priority: .userInitiated) {
            var query: [CFString: Any] = [
                kSecClass: kSecClassGenericPassword,
                kSecAttrService: service,
                kSecMatchLimit: kSecMatchLimitOne,
                kSecReturnData: true,
            ]
            if let account, !account.isEmpty {
                query[kSecAttrAccount] = account
            }

            var result: CFTypeRef?
            let status = SecItemCopyMatching(query as CFDictionary, &result)
            result = nil
            switch status {
            case errSecSuccess: return .accessible
            case errSecItemNotFound: return .notFound
            case errSecAuthFailed, errSecUserCanceled, errSecInteractionNotAllowed:
                return .denied
            default: return .failed(status)
            }
        }.value
    }

    static func descriptors(from rows: [[CFString: Any]]) -> [KeychainItemDescriptor] {
        rows.compactMap { row in
            guard let service = row[kSecAttrService] as? String, !service.isEmpty else {
                return nil
            }
            return KeychainItemDescriptor(
                service: service,
                account: row[kSecAttrAccount] as? String
            )
        }
    }

    private static func queryAttributes() throws -> [KeychainItemDescriptor] {
        var result: CFTypeRef?
        let status = SecItemCopyMatching(discoveryQuery as CFDictionary, &result)
        if status == errSecItemNotFound { return [] }
        guard status == errSecSuccess else {
            throw KeychainDiscoveryError.queryFailed(status)
        }
        guard let rows = result as? [[CFString: Any]] else { return [] }
        return descriptors(from: rows)
    }
}
