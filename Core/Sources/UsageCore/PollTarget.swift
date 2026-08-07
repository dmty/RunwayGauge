import Foundation

public struct PollTarget: Equatable, Sendable {
    public let accountId: String
    public let label: String
    public let configDir: String?
    public let keychainService: String
    public let keychainAccount: String
}

public enum PollTargets {
    public static func list(from registry: AccountRegistry) -> [PollTarget] {
        let selected = registry.prefs.selectedAccountId
        let targets = registry.accounts.compactMap { account -> PollTarget? in
            guard account.pinned, account.sourceKind == .claudeOAuth,
                  let keychain = account.credentials.keychain else { return nil }
            guard let service = trimmed(keychain.service),
                  let accountName = trimmed(keychain.account) else { return nil }
            return PollTarget(
                accountId: account.id,
                label: account.label,
                configDir: account.credentials.configDir.flatMap(trimmed),
                keychainService: service,
                keychainAccount: accountName
            )
        }
        return targets.sorted { a, b in
            let aSel = a.accountId == selected
            let bSel = b.accountId == selected
            if aSel != bSel { return aSel }
            return a.accountId < b.accountId
        }
    }
}

public enum ClaudeAccountResolve {
    public enum Error: Swift.Error, Equatable {
        case notFound
        case ambiguous
    }

    public static func accountId(
        in registry: AccountRegistry,
        configDir: String,
        home: URL? = nil
    ) throws -> String {
        let normalized = AccountValidation.normalizePath(configDir, home: home)
        var match: String?
        for account in registry.accounts where account.sourceKind == .claudeOAuth {
            guard let raw = account.credentials.configDir.flatMap(trimmed) else { continue }
            guard AccountValidation.normalizePath(raw, home: home) == normalized else { continue }
            if match != nil { throw Error.ambiguous }
            match = account.id
        }
        guard let match else { throw Error.notFound }
        return match
    }
}

private func trimmed(_ raw: String?) -> String? {
    guard let raw else { return nil }
    let s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
    return s.isEmpty ? nil : s
}
