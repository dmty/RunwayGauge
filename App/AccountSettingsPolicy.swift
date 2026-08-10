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

    static func usageHealth(for record: UsageRecord) -> String {
        if let status = record.fetchStatus, status.state != .ok {
            if let message = status.message, !message.isEmpty { return message }
            return status.state == .rateLimited ? "Rate limited" : "Fetch failed"
        }
        return record.windows.isEmpty ? "No usage windows" : "Usage available"
    }
}
