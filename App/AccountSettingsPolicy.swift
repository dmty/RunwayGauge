import UsageCore

struct AccountRowCapabilities: Equatable {
    let canEdit: Bool
    let canDelete: Bool
    let canTestAccess: Bool
}

enum AccountSettingsPolicy {
    static func capabilities(for account: Account) -> AccountRowCapabilities {
        if account.sourceKind == .codex {
            return AccountRowCapabilities(
                canEdit: false,
                canDelete: false,
                canTestAccess: false
            )
        }
        return AccountRowCapabilities(
            canEdit: true,
            canDelete: true,
            canTestAccess: account.credentials.keychain != nil
        )
    }

    static func requiresPinConfirmation(_ account: Account) -> Bool {
        guard let source = SourceCatalog.adapter(for: account.sourceKind) else {
            return true
        }
        return source.validate(
            account,
            fileSystem: LocalSourceFileSystem()
        ) == .comingSoon
    }
}
