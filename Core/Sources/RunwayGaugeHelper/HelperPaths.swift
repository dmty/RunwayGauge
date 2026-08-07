import Foundation
import UsageCore

enum HelperPaths {
    static func usageDirectory(home: URL? = nil) -> URL {
        if let override = ProcessInfo.processInfo.environment["USAGE_DIR_OVERRIDE"],
           !override.isEmpty {
            return URL(fileURLWithPath: override, isDirectory: true)
        }
        return UsageStore.defaultDirectory(home: home)
    }

    static func accountsURL(home: URL? = nil) -> URL {
        usageDirectory(home: home).appendingPathComponent("accounts.json")
    }

    static func usageURL(accountId: String, home: URL? = nil) throws -> URL {
        try AccountValidation.validateID(accountId)
        return usageDirectory(home: home).appendingPathComponent("usage-\(accountId).json")
    }
}
