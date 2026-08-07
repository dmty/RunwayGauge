import Foundation
import UsageCore

enum AccountEnumeration {
    static func pollTargets(from url: URL = HelperPaths.accountsURL()) throws -> [PollTarget] {
        PollTargets.list(from: try AccountStore.load(from: url))
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
        let registry = try AccountStore.load(from: accountsURL)
        let trimmed = configDirEnv?.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedDir: String
        if let trimmed, !trimmed.isEmpty {
            resolvedDir = trimmed
        } else {
            resolvedDir = (home ?? FileManager.default.homeDirectoryForCurrentUser)
                .appendingPathComponent(".claude").path
        }
        return try ClaudeAccountResolve.accountId(in: registry, configDir: resolvedDir, home: home)
    }
}
