import Foundation

// ponytail: one coming-soon adapter; split types when behavior diverges
struct ComingSoonAPISource: UsageSource {
    let kind: SourceKind
    let displayName: String
    let settingsFields: [SourceFieldDescriptor]

    func discover(home: URL, keychainItems: [KeychainItemDescriptor]) -> [DiscoveredAccount] { [] }
    func validate(_ account: Account, fileSystem: any SourceFileSystem) -> SourceHealth { .comingSoon }
    func paneModel(account: Account, record: UsageRecord?) -> UsagePaneModel {
        .comingSoon(sourceKind: kind, label: account.label)
    }
}

extension ComingSoonAPISource {
    static let openAI = ComingSoonAPISource(
        kind: .openAIAPI,
        displayName: "OpenAI API",
        settingsFields: [
            SourceFieldDescriptor(key: "organization", label: "Organization", required: false),
            SourceFieldDescriptor(key: "project", label: "Project", required: false),
        ]
    )

    static let anthropic = ComingSoonAPISource(
        kind: .anthropicAPI,
        displayName: "Anthropic API",
        settingsFields: [
            SourceFieldDescriptor(key: "workspace", label: "Workspace", required: false),
        ]
    )
}
