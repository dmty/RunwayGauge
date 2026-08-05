import Foundation
import Testing
@testable import UsageCore

@Suite("MigrationTests")
struct MigrationTests {
    private func tempHome() throws -> URL {
        let home = URL(fileURLWithPath: NSTemporaryDirectory())
            .appending(path: "migration-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        return home
    }

    private func discovered(
        label: String = "Claude",
        configDir: String? = nil,
        account: String? = "user@example.com"
    ) -> DiscoveredAccount {
        DiscoveredAccount(
            label: label,
            sourceKind: .claudeOAuth,
            credentials: AccountCredentials(
                configDir: configDir,
                keychain: account.map {
                    KeychainReference(service: ClaudeOAuthSource.genericKeychainService, account: $0)
                }
            )
        )
    }

    private func legacyURL(home: URL) -> URL {
        UsageStore.url(source: "claude-code", home: home)
    }

    private func prepare(home: URL, legacy: Data? = nil) throws {
        let dir = UsageStore.defaultDirectory(home: home)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        if let legacy {
            try legacy.write(to: legacyURL(home: home))
        }
    }

    @Test("bootstrap without discovery persists an empty valid registry")
    func bootstrapWithoutDiscovery() throws {
        let home = try tempHome()
        let registry = try AccountStore.bootstrapIfMissing(home: home, discovered: [])

        #expect(registry.accounts.isEmpty)
        #expect(registry.prefs.selectedAccountId == nil)
        #expect(try AccountStore.load(from: AccountStore.url(home: home)) == registry)
    }

    @Test("bootstrap deduplicates safe discovery and pins the first usable Claude account")
    func bootstrapDiscovery() throws {
        let home = try tempHome()
        let config = home.appending(path: ".claude").path
        let unavailable = discovered(label: "Unavailable", account: nil)
        let first = discovered(configDir: config)
        let unsafe = discovered(label: "   ", account: "bad@example.com")

        let registry = try AccountStore.bootstrapIfMissing(
            home: home,
            discovered: [unavailable, first, first, unsafe]
        )

        #expect(registry.accounts.count == 2)
        #expect(registry.accounts.allSatisfy { $0.id.hasPrefix("acc_") })
        #expect(!registry.accounts[0].pinned)
        #expect(registry.accounts[1].pinned)
        #expect(registry.prefs.selectedAccountId == registry.accounts[1].id)
    }

    @Test("malformed and newer registries are preserved byte-for-byte")
    func invalidRegistryIsPreserved() throws {
        for bytes in [
            Data("{broken".utf8),
            Data(#"{"schema":2,"revision":8,"prefs":{},"accounts":[]}"#.utf8),
        ] {
            let home = try tempHome()
            try prepare(home: home)
            let registryURL = AccountStore.url(home: home)
            try bytes.write(to: registryURL)

            #expect(throws: AccountLoadError.unreadable) {
                try AccountStore.bootstrapIfMissing(home: home, discovered: [discovered()])
            }
            #expect(try Data(contentsOf: registryURL) == bytes)
        }
    }

    @Test("legacy usage is archived only after persistence and never copied to an account")
    func archivesWithoutGuessing() throws {
        let home = try tempHome()
        let legacyBytes = Data(#"{"schema":1,"source":"claude-code","updatedAt":42,"origin":"legacy","windows":[]}"#.utf8)
        try prepare(home: home, legacy: legacyBytes)
        let legacy = legacyURL(home: home)

        let registry = try AccountStore.bootstrapIfMissing(home: home, discovered: [discovered()])
        let archive = AccountStore.legacyUsageArchiveURL(home: home)

        #expect(archive.lastPathComponent == "claude-code.legacy.json")
        #expect(!FileManager.default.fileExists(atPath: legacy.path))
        #expect(try Data(contentsOf: archive) == legacyBytes)
        #expect(!FileManager.default.fileExists(atPath: AccountStore.legacyUsageArchivePendingURL(home: home).path))
        #expect(try Data(contentsOf: AccountStore.url(home: home)).isEmpty == false)
        #expect(UsageStore.load(accountId: registry.accounts[0].id, home: home) == .missing)
    }

    @Test("interrupted archival after registry save completes on next bootstrap")
    func completesInterruptedArchival() throws {
        let home = try tempHome()
        let legacyBytes = Data(#"{"schema":1,"source":"claude-code","updatedAt":42,"origin":"legacy","windows":[]}"#.utf8)
        try prepare(home: home, legacy: legacyBytes)
        let legacy = legacyURL(home: home)

        let registry = AccountRegistry(
            revision: 1,
            prefs: AccountPreferences(),
            accounts: []
        )
        try AccountStore.save(registry, to: AccountStore.url(home: home))
        try Data().write(to: AccountStore.legacyUsageArchivePendingURL(home: home))

        #expect(FileManager.default.fileExists(atPath: legacy.path))
        #expect(!FileManager.default.fileExists(atPath: AccountStore.legacyUsageArchiveURL(home: home).path))
        #expect(FileManager.default.fileExists(atPath: AccountStore.legacyUsageArchivePendingURL(home: home).path))

        let loaded = try AccountStore.bootstrapIfMissing(home: home, discovered: [])
        let archive = AccountStore.legacyUsageArchiveURL(home: home)

        #expect(loaded == registry)
        #expect(!FileManager.default.fileExists(atPath: legacy.path))
        #expect(try Data(contentsOf: archive) == legacyBytes)
        #expect(!FileManager.default.fileExists(atPath: AccountStore.legacyUsageArchivePendingURL(home: home).path))
        #expect(!AccountStore.hasLegacyUsageWarning(home: home))
    }

    @Test("legacy recreated after registry persistence is left in place and warned")
    func recreatedLegacyIsNotRearchived() throws {
        let home = try tempHome()
        try prepare(home: home, legacy: Data("original legacy".utf8))
        let initial = try AccountStore.bootstrapIfMissing(home: home, discovered: [discovered()])
        let registryBytes = try Data(contentsOf: AccountStore.url(home: home))
        let archive = AccountStore.legacyUsageArchiveURL(home: home)
        #expect(try Data(contentsOf: archive) == Data("original legacy".utf8))

        let legacy = legacyURL(home: home)
        try Data("legacy".utf8).write(to: legacy)

        let recovered = try AccountStore.bootstrapIfMissing(home: home, discovered: [])
        #expect(recovered == initial)
        #expect(try Data(contentsOf: AccountStore.url(home: home)) == registryBytes)
        #expect(try Data(contentsOf: legacy) == Data("legacy".utf8))
        #expect(try Data(contentsOf: archive) == Data("original legacy".utf8))
        #expect(AccountStore.hasLegacyUsageWarning(home: home))

        let repeated = try AccountStore.bootstrapIfMissing(home: home, discovered: [discovered(label: "Ignored")])
        #expect(repeated == initial)
        #expect(try Data(contentsOf: legacy) == Data("legacy".utf8))
    }

    @Test("legacy recreated after bootstrap without legacy is left in place and warned")
    func lateRecreatedLegacyIsNotArchived() throws {
        let home = try tempHome()
        try prepare(home: home)
        let initial = try AccountStore.bootstrapIfMissing(home: home, discovered: [discovered()])
        let registryBytes = try Data(contentsOf: AccountStore.url(home: home))
        let archive = AccountStore.legacyUsageArchiveURL(home: home)
        #expect(!FileManager.default.fileExists(atPath: archive.path))

        let legacy = legacyURL(home: home)
        try Data("recreated legacy".utf8).write(to: legacy)

        let recovered = try AccountStore.bootstrapIfMissing(home: home, discovered: [])
        #expect(recovered == initial)
        #expect(try Data(contentsOf: AccountStore.url(home: home)) == registryBytes)
        #expect(!FileManager.default.fileExists(atPath: archive.path))
        #expect(try Data(contentsOf: legacy) == Data("recreated legacy".utf8))
        #expect(AccountStore.hasLegacyUsageWarning(home: home))
    }

    @Test("an existing archive is never overwritten and recreated legacy data raises a warning")
    func preservesExistingArchive() throws {
        let home = try tempHome()
        _ = try AccountStore.bootstrapIfMissing(home: home, discovered: [])
        let archive = AccountStore.legacyUsageArchiveURL(home: home)
        try Data("original archive".utf8).write(to: archive)
        let legacy = legacyURL(home: home)
        try Data("recreated legacy".utf8).write(to: legacy)

        _ = try AccountStore.bootstrapIfMissing(home: home, discovered: [])

        #expect(try Data(contentsOf: archive) == Data("original archive".utf8))
        #expect(try Data(contentsOf: legacy) == Data("recreated legacy".utf8))
        #expect(AccountStore.hasLegacyUsageWarning(home: home))
    }
}
