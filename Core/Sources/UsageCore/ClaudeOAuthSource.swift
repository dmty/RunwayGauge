import Foundation

public struct ClaudeOAuthSource: UsageSource {
    public static let genericKeychainService = "Claude Code-credentials"

    public let kind = SourceKind.claudeOAuth
    public let displayName = "Claude Code"
    public let settingsFields: [SourceFieldDescriptor] = [
        SourceFieldDescriptor(key: "configDir", label: "Config directory", required: false),
        SourceFieldDescriptor(key: "keychainService", label: "Keychain service", required: false),
        SourceFieldDescriptor(key: "keychainAccount", label: "Keychain account", required: false),
    ]

    private let home: URL?

    public init(home: URL? = nil) {
        self.home = home
    }

    public func discover(
        home: URL,
        keychainItems: [KeychainItemDescriptor]
    ) -> [DiscoveredAccount] {
        let fs = LocalSourceFileSystem()
        let configPath = AccountValidation.normalizePath("~/.claude", home: home)
        let configURL = URL(fileURLWithPath: configPath, isDirectory: true)
        let hasDefaultConfig = fs.directoryExists(at: configURL)

        // ponytail: string fingerprint, Hashable tuple if dedup set grows
        var seen = Set<String>()
        let keychainCandidates = keychainItems.compactMap { item -> KeychainReference? in
            guard Self.accepts(service: item.service) else { return nil }
            let fingerprint = "\(item.service)\0\(item.account ?? "")"
            guard seen.insert(fingerprint).inserted else { return nil }
            return KeychainReference(service: item.service, account: item.account)
        }

        if hasDefaultConfig,
           keychainCandidates.count == 1,
           keychainCandidates[0].service == Self.genericKeychainService {
            return [discovered(label: displayName, configDir: configURL.path, keychain: keychainCandidates[0])]
        }

        var results: [DiscoveredAccount] = []
        if hasDefaultConfig {
            results.append(discovered(label: displayName, configDir: configURL.path))
        }
        results += keychainCandidates.map { reference in
            let accountLabel = reference.account?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let label = accountLabel.flatMap { $0.isEmpty ? nil : $0 }
                ?? displayName.trimmingCharacters(in: .whitespacesAndNewlines)
            return discovered(label: label, keychain: reference)
        }
        return results
    }

    public func validate(
        _ account: Account,
        fileSystem: any SourceFileSystem
    ) -> SourceHealth {
        let hasConfig = account.credentials.configDir.map {
            let normalized = AccountValidation.normalizePath($0, home: home)
            return fileSystem.directoryExists(at: URL(fileURLWithPath: normalized))
        } ?? false
        let hasKeychain = AccountValidation.isPollCapable(account)

        switch (hasConfig, hasKeychain) {
        case (true, true): return .ready
        case (true, false): return .statuslineOnly(reason: "Keychain credentials are missing")
        case (false, true): return .pollerOnly(reason: "Config directory is missing")
        case (false, false): return .unavailable(reason: "Config directory and Keychain credentials are missing")
        }
    }

    public func paneModel(account: Account, record: UsageRecord?) -> UsagePaneModel {
        .usage(sourceKind: kind, label: account.label, record: record)
    }

    private func discovered(
        label: String,
        configDir: String? = nil,
        keychain: KeychainReference? = nil
    ) -> DiscoveredAccount {
        DiscoveredAccount(
            label: label,
            sourceKind: kind,
            credentials: AccountCredentials(configDir: configDir, keychain: keychain)
        )
    }

    private static func accepts(service: String) -> Bool {
        service == genericKeychainService
            || (service.hasPrefix("\(genericKeychainService)-") && service.count > genericKeychainService.count + 1)
    }
}
