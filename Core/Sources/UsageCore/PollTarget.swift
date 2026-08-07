import Foundation

/// A pinned Claude OAuth account that can be polled (both Keychain selectors present).
public struct PollTarget: Equatable, Sendable {
    public let accountId: String
    public let label: String
    public let configDir: String?
    public let keychainService: String
    public let keychainAccount: String

    public init(
        accountId: String,
        label: String,
        configDir: String?,
        keychainService: String,
        keychainAccount: String
    ) {
        self.accountId = accountId
        self.label = label
        self.configDir = configDir
        self.keychainService = keychainService
        self.keychainAccount = keychainAccount
    }
}

/// Pure enumeration of poll-capable accounts from an already-decoded registry.
public enum PollTargets {
    /// Pinned `claude-oauth` accounts with both Keychain selectors.
    /// Selected account (if pinned+pollable) is listed first — matches `account_enumerate_pinned_claude`.
    public static func list(from registry: AccountRegistry) -> [PollTarget] {
        let selected = registry.prefs.selectedAccountId
        let targets: [PollTarget] = registry.accounts.compactMap { account in
            guard account.pinned,
                  account.sourceKind == .claudeOAuth,
                  let keychain = account.credentials.keychain
            else { return nil }

            let service = keychain.service.trimmingCharacters(in: .whitespacesAndNewlines)
            let accountName = (keychain.account ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            guard !service.isEmpty, !accountName.isEmpty else { return nil }

            let configDir = account.credentials.configDir.map {
                $0.trimmingCharacters(in: .whitespacesAndNewlines)
            }.flatMap { $0.isEmpty ? nil : $0 }

            return PollTarget(
                accountId: account.id,
                label: account.label,
                configDir: configDir,
                keychainService: service,
                keychainAccount: accountName
            )
        }

        return targets.sorted { a, b in
            let aSel = a.accountId == selected
            let bSel = b.accountId == selected
            if aSel != bSel { return aSel && !bSel }
            return a.accountId < b.accountId
        }
    }
}

/// Resolve a Claude OAuth account id from `CLAUDE_CONFIG_DIR` + registry (shell `account_resolve_claude`).
public enum ClaudeAccountResolve {
    public enum Error: Swift.Error, Equatable {
        case notFound
        case ambiguous
    }

    /// Returns the unique matching `claude-oauth` account id for `configDir`, or throws.
    public static func accountId(
        in registry: AccountRegistry,
        configDir: String,
        home: URL? = nil
    ) throws -> String {
        let normalized = AccountValidation.normalizePath(configDir, home: home)
        var match: String?

        for account in registry.accounts where account.sourceKind == .claudeOAuth {
            guard let raw = account.credentials.configDir,
                  !raw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            else { continue }
            let candidate = AccountValidation.normalizePath(raw, home: home)
            guard candidate == normalized else { continue }
            if match != nil { throw Error.ambiguous }
            match = account.id
        }

        guard let match else { throw Error.notFound }
        return match
    }
}
