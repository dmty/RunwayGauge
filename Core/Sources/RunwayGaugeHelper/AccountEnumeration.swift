import Foundation
import UsageCore

/// Read-only account registry helpers for the CLI (poll targets + configDir resolve).
enum AccountEnumeration {
    static func loadRegistry(from url: URL = HelperPaths.accountsURL()) throws -> AccountRegistry {
        try AccountStore.load(from: url)
    }

    static func pollTargets(from url: URL = HelperPaths.accountsURL()) throws -> [PollTarget] {
        let registry = try loadRegistry(from: url)
        return PollTargets.list(from: registry)
    }

    static func resolveAccountId(
        explicit: String?,
        configDirEnv: String? = ProcessInfo.processInfo.environment["CLAUDE_CONFIG_DIR"],
        home: URL? = nil,
        accountsURL: URL = HelperPaths.accountsURL()
    ) throws -> String {
        if let explicit, !explicit.isEmpty {
            try AccountValidation.validateID(explicit)
            return explicit
        }

        let registry = try loadRegistry(from: accountsURL)
        let configDir = configDirEnv?.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedDir: String
        if let configDir, !configDir.isEmpty {
            resolvedDir = configDir
        } else {
            let homeURL = home ?? FileManager.default.homeDirectoryForCurrentUser
            resolvedDir = homeURL.appendingPathComponent(".claude").path
        }
        return try ClaudeAccountResolve.accountId(in: registry, configDir: resolvedDir, home: home)
    }
}
