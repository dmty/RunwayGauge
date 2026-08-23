import Foundation

public enum PollTarget: Equatable, Sendable {
    case claude(
        accountId: String,
        label: String,
        configDir: String?,
        keychainService: String?,
        keychainAccount: String?
    )
    case codex(
        accountId: String,
        label: String,
        executablePath: String
    )

    public var accountId: String {
        switch self {
        case .claude(let accountId, _, _, _, _),
             .codex(let accountId, _, _): accountId
        }
    }
}

public enum PollTargets {
    public static func list(from registry: AccountRegistry) -> [PollTarget] {
        let selected = registry.prefs.selectedAccountId
        let targets = registry.accounts.compactMap { account -> PollTarget? in
            guard account.pinned else { return nil }
            switch account.sourceKind {
            case .claudeOAuth:
                let configDir = account.credentials.configDir.flatMap(trimmed)
                let service = account.credentials.keychain.flatMap { trimmed($0.service) }
                let keychainAccount = account.credentials.keychain.flatMap { trimmed($0.account) }
                guard configDir != nil || (service != nil && keychainAccount != nil) else {
                    return nil
                }
                return .claude(
                    accountId: account.id,
                    label: account.label,
                    configDir: configDir,
                    keychainService: service,
                    keychainAccount: keychainAccount
                )
            case .codex:
                guard let path = account.credentials.nonSecretFields[
                    CodexAccount.executablePathKey
                ].flatMap(trimmed), path.hasPrefix("/") else { return nil }
                return .codex(
                    accountId: account.id,
                    label: account.label,
                    executablePath: URL(fileURLWithPath: path).standardizedFileURL.path
                )
            default:
                return nil
            }
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
