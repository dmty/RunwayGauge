import Foundation
import Testing
@testable import UsageCore

@Suite("SourceAdapterTests")
struct SourceAdapterTests {
    private struct TestFileSystem: SourceFileSystem {
        let existingPaths: Set<String>

        func itemExists(at url: URL) -> Bool {
            existingPaths.contains(url.standardizedFileURL.path)
        }

        func directoryExists(at url: URL) -> Bool {
            existingPaths.contains(url.standardizedFileURL.path)
        }
    }

    private func temporaryHome() throws -> URL {
        let home = URL(fileURLWithPath: NSTemporaryDirectory())
            .appending(path: "source-adapter-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        return home
    }

    private func account(
        configDir: String? = nil,
        keychain: KeychainReference? = nil,
        sourceKind: SourceKind = .claudeOAuth
    ) -> Account {
        Account(
            id: "acc_test",
            label: "Test",
            sourceKind: sourceKind,
            pinned: true,
            credentials: AccountCredentials(configDir: configDir, keychain: keychain)
        )
    }

    @Test("discovers only the default Claude config directory")
    func defaultDiscoveryDoesNotInventCustomDirectories() throws {
        let home = try temporaryHome()
        let config = home.appending(path: ".claude")
        try FileManager.default.createDirectory(at: config, withIntermediateDirectories: true)

        let discovered = ClaudeOAuthSource().discover(
            home: home,
            keychainItems: [
                KeychainItemDescriptor(
                    service: "Claude Code-credentials-work",
                    account: "work@example.com"
                )
            ]
        )

        #expect(discovered.count == 2)
        #expect(discovered.map(\.credentials.configDir).compactMap { $0 } == [config.path])
        #expect(discovered.contains {
            $0.credentials.configDir == nil
                && $0.credentials.keychain?.service == "Claude Code-credentials-work"
        })
    }

    @Test("does not discover a regular file as the default config directory")
    func regularFileIsNotDiscoveredAsConfig() throws {
        let home = try temporaryHome()
        try Data().write(to: home.appending(path: ".claude"))

        let discovered = ClaudeOAuthSource().discover(
            home: home,
            keychainItems: []
        )

        #expect(discovered.isEmpty)
    }

    @Test("deduplicates repeated generic-service metadata")
    func noDuplicateGenericServiceCandidate() {
        let item = KeychainItemDescriptor(
            service: "Claude Code-credentials",
            account: "user@example.com"
        )

        let discovered = ClaudeOAuthSource().discover(
            home: URL(fileURLWithPath: "/missing-home"),
            keychainItems: [item, item]
        )

        #expect(discovered.count == 1)
        #expect(discovered[0].credentials.keychain?.account == "user@example.com")
    }

    @Test("rejects a service with an empty suffix")
    func rejectsEmptyServiceSuffix() {
        let discovered = ClaudeOAuthSource().discover(
            home: URL(fileURLWithPath: "/missing-home"),
            keychainItems: [
                KeychainItemDescriptor(
                    service: "Claude Code-credentials-",
                    account: "user@example.com"
                )
            ]
        )

        #expect(discovered.isEmpty)
    }

    @Test("keeps ambiguous default services separate from config")
    func ambiguousServicesStayUnpaired() throws {
        let home = try temporaryHome()
        let config = home.appending(path: ".claude")
        try FileManager.default.createDirectory(at: config, withIntermediateDirectories: true)

        let discovered = ClaudeOAuthSource().discover(
            home: home,
            keychainItems: [
                KeychainItemDescriptor(
                    service: "Claude Code-credentials",
                    account: "one@example.com"
                ),
                KeychainItemDescriptor(
                    service: "Claude Code-credentials",
                    account: "two@example.com"
                ),
            ]
        )

        #expect(discovered.count == 3)
        #expect(discovered.filter { $0.credentials.configDir != nil }.count == 1)
        #expect(discovered.filter { $0.credentials.keychain != nil }.count == 2)
        #expect(discovered.allSatisfy {
            $0.credentials.configDir == nil || $0.credentials.keychain == nil
        })
    }

    @Test("keeps accounts distinct within one service")
    func sameServiceDifferentAccountsRemainDistinct() {
        let discovered = ClaudeOAuthSource().discover(
            home: URL(fileURLWithPath: "/missing-home"),
            keychainItems: [
                KeychainItemDescriptor(
                    service: "Claude Code-credentials-team",
                    account: "one@example.com"
                ),
                KeychainItemDescriptor(
                    service: "Claude Code-credentials-team",
                    account: "two@example.com"
                ),
            ]
        )

        #expect(discovered.count == 2)
        #expect(Set(discovered.compactMap(\.credentials.keychain?.account)) == [
            "one@example.com",
            "two@example.com",
        ])
    }

    @Test("uses the display name for a blank Keychain account label")
    func blankKeychainAccountUsesDisplayName() {
        let discovered = ClaudeOAuthSource().discover(
            home: URL(fileURLWithPath: "/missing-home"),
            keychainItems: [
                KeychainItemDescriptor(
                    service: "Claude Code-credentials-team",
                    account: "   "
                )
            ]
        )

        #expect(discovered.count == 1)
        #expect(discovered[0].label == "Claude Code")
    }

    @Test("merges one default config and generic Keychain item")
    func unambiguousDefaultPairMerges() throws {
        let home = try temporaryHome()
        let config = home.appending(path: ".claude")
        try FileManager.default.createDirectory(at: config, withIntermediateDirectories: true)

        let discovered = ClaudeOAuthSource().discover(
            home: home,
            keychainItems: [
                KeychainItemDescriptor(
                    service: "Claude Code-credentials",
                    account: "user@example.com"
                )
            ]
        )

        #expect(discovered.count == 1)
        #expect(discovered[0].credentials.configDir == config.path)
        #expect(discovered[0].credentials.keychain?.account == "user@example.com")
    }

    @Test("reports config-only and Keychain-only capability")
    func partialCredentialHealth() {
        let configPath = "/Users/test/.claude"
        let fileSystem = TestFileSystem(existingPaths: [configPath])
        let source = ClaudeOAuthSource()

        #expect(source.validate(
            account(configDir: configPath),
            fileSystem: fileSystem
        ) == .statuslineOnly(reason: "Keychain credentials are missing"))

        #expect(source.validate(
            account(keychain: KeychainReference(
                service: "Claude Code-credentials",
                account: "user@example.com"
            )),
            fileSystem: fileSystem
        ) == .pollerOnly(reason: "Config directory is missing"))
    }

    @Test("normalizes a tilde config path against the injected real home")
    func tildeConfigHealthUsesInjectedHome() {
        let home = URL(fileURLWithPath: "/Users/real-user")
        let configPath = home.appending(path: ".claude").path
        let source = ClaudeOAuthSource(home: home)

        #expect(source.validate(
            account(configDir: "~/.claude"),
            fileSystem: TestFileSystem(existingPaths: [configPath])
        ) == .statuslineOnly(reason: "Keychain credentials are missing"))
    }

    @Test("a regular file at configDir is unavailable")
    func regularFileConfigHealth() throws {
        let home = try temporaryHome()
        let configFile = home.appending(path: ".claude")
        try Data().write(to: configFile)

        #expect(ClaudeOAuthSource(home: home).validate(
            account(configDir: "~/.claude"),
            fileSystem: LocalSourceFileSystem()
        ) == .unavailable(
            reason: "Config directory and Keychain credentials are missing"
        ))
    }

    @Test("Keychain metadata without an account is not poller-ready")
    func keychainWithoutAccountHealth() {
        let source = ClaudeOAuthSource()

        #expect(source.validate(
            account(keychain: KeychainReference(
                service: "Claude Code-credentials",
                account: nil
            )),
            fileSystem: TestFileSystem(existingPaths: [])
        ) == .unavailable(
            reason: "Config directory and Keychain credentials are missing"
        ))
    }

    @Test("unknown sources produce unsupported pane data")
    func unknownSourcePane() {
        let unknown = SourceKind(rawValue: "future-source")
        let unknownAccount = account(sourceKind: unknown)

        #expect(SourceCatalog.adapter(for: unknown) == nil)
        #expect(
            SourceCatalog.paneModel(for: unknownAccount, record: nil)
                == .unsupported(sourceKind: unknown, label: "Test")
        )
    }

    @Test("API source stubs are registered but do not discover accounts")
    func staticStubCatalog() {
        let home = URL(fileURLWithPath: "/missing-home")

        #expect(SourceCatalog.adapter(for: .openAIAPI)?.discover(
            home: home,
            keychainItems: []
        ).isEmpty == true)
        #expect(SourceCatalog.adapter(for: .anthropicAPI)?.validate(
            account(sourceKind: .anthropicAPI),
            fileSystem: TestFileSystem(existingPaths: [])
        ) == .comingSoon)
        #expect(SourceCatalog.adapter(for: .openAIAPI)?.settingsFields.isEmpty == false)
    }
}
