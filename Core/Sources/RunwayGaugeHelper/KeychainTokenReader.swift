import Foundation
import Security
import UsageCore

/// Reads Claude OAuth access tokens from Keychain. Never logs or refreshes tokens.
enum KeychainTokenReader {
    static let securityTool = URL(fileURLWithPath: "/usr/bin/security")

    static func credentialData(
        service: String,
        account: String?,
        tool: URL = securityTool
    ) -> Data? {
        let trimmedService = service.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedService.isEmpty else { return nil }
        let trimmedAccount = account?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let trimmedAccount, !trimmedAccount.isEmpty {
            return readPassword(service: trimmedService, account: trimmedAccount, tool: tool)
        }
        guard let uniqueAccount = uniqueServiceAccount(service: trimmedService) else { return nil }
        return readPassword(service: trimmedService, account: uniqueAccount, tool: tool)
    }

    /// Attribute-only lookups never prompt. Returns the sole item's account ("" when it has none).
    private static func uniqueServiceAccount(service: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecReturnAttributes as String: true,
            kSecMatchLimit as String: kSecMatchLimitAll,
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess,
              let items = item as? [[String: Any]], items.count == 1 else {
            return nil
        }
        return items[0][kSecAttrAccount as String] as? String ?? ""
    }

    /// Claude Code writes its items with /usr/bin/security, so that tool stays on their ACL.
    /// Reading via SecItemCopyMatching instead makes macOS prompt after Claude Code token refreshes.
    static func readPassword(service: String, account: String, tool: URL = securityTool) -> Data? {
        var arguments = ["find-generic-password", "-s", service]
        if !account.isEmpty {
            arguments += ["-a", account]
        }
        arguments.append("-w")

        let process = Process()
        process.executableURL = tool
        process.arguments = arguments
        let stdout = Pipe()
        process.standardOutput = stdout
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
        } catch {
            return nil
        }
        let output = stdout.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { return nil }
        return decodePasswordOutput(output)
    }

    /// `security -w` prints the secret plus a newline, or hex when the bytes are not printable.
    static func decodePasswordOutput(_ output: Data) -> Data? {
        var bytes = output
        if bytes.last == UInt8(ascii: "\n") {
            bytes.removeLast()
        }
        guard !bytes.isEmpty else { return nil }
        return hexDecoded(bytes) ?? bytes
    }

    private static func hexDecoded(_ bytes: Data) -> Data? {
        guard bytes.count.isMultiple(of: 2) else { return nil }
        var decoded = Data(capacity: bytes.count / 2)
        var index = bytes.startIndex
        while index < bytes.endIndex {
            guard let high = hexValue(bytes[index]),
                  let low = hexValue(bytes[bytes.index(after: index)]) else { return nil }
            decoded.append(high << 4 | low)
            index = bytes.index(index, offsetBy: 2)
        }
        return decoded
    }

    private static func hexValue(_ byte: UInt8) -> UInt8? {
        switch byte {
        case UInt8(ascii: "0")...UInt8(ascii: "9"): byte - UInt8(ascii: "0")
        case UInt8(ascii: "a")...UInt8(ascii: "f"): byte - UInt8(ascii: "a") + 10
        case UInt8(ascii: "A")...UInt8(ascii: "F"): byte - UInt8(ascii: "A") + 10
        default: nil
        }
    }
}
