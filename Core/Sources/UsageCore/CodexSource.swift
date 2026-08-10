import Foundation

public struct CodexSource: UsageSource {
    public let kind = SourceKind.codex
    public let displayName = "Codex"
    public let settingsFields: [SourceFieldDescriptor] = []
    public let presentation = UsageSourcePresentation(
        compactHeader: "CODEX",
        emptyMessage: "No Codex usage data yet.",
        supportsSessionNotStarted: false
    )

    public init() {}

    public func discover(
        home: URL,
        keychainItems: [KeychainItemDescriptor]
    ) -> [DiscoveredAccount] { [] }

    public func validate(
        _ account: Account,
        fileSystem: any SourceFileSystem
    ) -> SourceHealth {
        guard let raw = account.credentials.nonSecretFields[
            CodexAccount.executablePathKey
        ]?.trimmingCharacters(in: .whitespacesAndNewlines),
              !raw.isEmpty,
              fileSystem.itemExists(at: URL(fileURLWithPath: raw))
        else {
            return .unavailable(reason: "Codex executable is missing")
        }
        return .ready
    }

    public func paneModel(account: Account, record: UsageRecord?) -> UsagePaneModel {
        .usage(sourceKind: kind, label: account.label, record: record)
    }
}
