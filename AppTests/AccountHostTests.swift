import Foundation
import Testing
import UsageCore
import CodexAppServer
@testable import RunwayGauge

private enum DiscoveryFailure: Error {
    case unavailable
}

private func temporaryHome() throws -> URL {
    let url = FileManager.default.temporaryDirectory
        .appending(path: "RunwayGauge-AppHostTests-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}

private func registry(revision: UInt64, accountID: String) -> AccountRegistry {
    AccountRegistry(
        revision: revision,
        prefs: AccountPreferences(),
        accounts: [
            Account(
                id: accountID,
                label: accountID,
                sourceKind: .claudeOAuth,
                pinned: false,
                credentials: AccountCredentials()
            ),
        ]
    )
}

struct AccountHostTests {
    @Test("Keychain failure does not block loading an existing registry")
    func bootstrapLoadsExistingRegistryAfterDiscoveryFailure() async throws {
        let home = try temporaryHome()
        defer { try? FileManager.default.removeItem(at: home) }
        let stored = try AccountStore.mutate(at: AccountStore.url(home: home)) {
            $0.accounts.append(Account(
                id: "acc_existing",
                label: "Existing",
                sourceKind: .claudeOAuth,
                pinned: false,
                credentials: AccountCredentials()
            ))
        }

        let result = try await AppModel.bootstrapRegistry(
            home: home,
            discoverKeychain: { throw DiscoveryFailure.unavailable },
            discoverCodex: { .notInstalled }
        )

        #expect(result.registry == stored)
        #expect(result.discoveryWarning != nil)
    }

    @Test("Keychain failure still bootstraps an empty registry")
    func bootstrapCreatesRegistryAfterDiscoveryFailure() async throws {
        let home = try temporaryHome()
        defer { try? FileManager.default.removeItem(at: home) }

        let result = try await AppModel.bootstrapRegistry(
            home: home,
            discoverKeychain: { throw DiscoveryFailure.unavailable },
            discoverCodex: { .notInstalled }
        )

        #expect(result.registry.accounts.isEmpty)
        #expect(FileManager.default.fileExists(atPath: AccountStore.url(home: home).path))
        #expect(result.discoveryWarning != nil)
    }

    @Test("ready Codex discovery persists one unpinned default account")
    func bootstrapPersistsCodex() async throws {
        let home = try temporaryHome()
        defer { try? FileManager.default.removeItem(at: home) }

        let result = try await AppModel.bootstrapRegistry(
            home: home,
            discoverKeychain: { [] },
            discoverCodex: { .ready(executablePath: "/opt/homebrew/bin/codex") }
        )

        let codex = try #require(result.registry.accounts.first {
            $0.id == CodexAccount.id
        })
        #expect(!codex.pinned)
        #expect(codex.credentials.keychain == nil)
        #expect(codex.credentials.nonSecretFields[
            CodexAccount.executablePathKey
        ] == "/opt/homebrew/bin/codex")
        #expect(result.codexStatus == .ready(
            executablePath: "/opt/homebrew/bin/codex"
        ))
        #expect(try AccountStore.load(from: AccountStore.url(home: home))
            .accounts.contains { $0.id == CodexAccount.id })
    }

    @Test("failed rediscovery preserves an existing pinned Codex row")
    func bootstrapPreservesCodexOnFailure() async throws {
        let home = try temporaryHome()
        defer { try? FileManager.default.removeItem(at: home) }
        _ = try AccountStore.mutate(at: AccountStore.url(home: home)) {
            $0.accounts.append(Account(
                id: CodexAccount.id,
                label: CodexAccount.label,
                sourceKind: .codex,
                pinned: true,
                credentials: AccountCredentials(nonSecretFields: [
                    CodexAccount.executablePathKey: "/old/codex",
                ])
            ))
            $0.prefs.selectedAccountId = CodexAccount.id
        }

        let result = try await AppModel.bootstrapRegistry(
            home: home,
            discoverKeychain: { [] },
            discoverCodex: { .notInstalled }
        )

        #expect(result.registry.accounts.first { $0.id == CodexAccount.id }?.pinned == true)
        #expect(result.registry.prefs.selectedAccountId == CodexAccount.id)
        #expect(result.codexStatus == .notInstalled)
    }

    @Test("Codex is managed but not coming soon")
    func codexSettingsPolicy() {
        let account = Account(
            id: CodexAccount.id,
            label: CodexAccount.label,
            sourceKind: .codex,
            pinned: false,
            credentials: AccountCredentials(nonSecretFields: [
                CodexAccount.executablePathKey: "/opt/homebrew/bin/codex",
            ])
        )
        #expect(AccountSettingsPolicy.capabilities(for: account) == .init(
            canEdit: false,
            canDelete: false,
            canTestAccess: false
        ))
        #expect(!AccountSettingsPolicy.requiresPinConfirmation(account))
    }

    @Test("API placeholders still require confirmation")
    func placeholderSettingsPolicy() {
        let account = Account(
            id: "acc_openai",
            label: "OpenAI",
            sourceKind: .openAIAPI,
            pinned: false,
            credentials: AccountCredentials()
        )
        #expect(AccountSettingsPolicy.requiresPinConfirmation(account))
    }

    @Test("discovery merges Keychain credentials into matching normalized config")
    func discoveryMergesMatchingClaudeConfig() throws {
        let home = try temporaryHome()
        defer { try? FileManager.default.removeItem(at: home) }
        var value = AccountRegistry(
            revision: 4,
            prefs: AccountPreferences(),
            accounts: [
                Account(
                    id: "acc_existing",
                    label: "Existing",
                    sourceKind: .claudeOAuth,
                    pinned: false,
                    credentials: AccountCredentials(configDir: "~/.claude")
                ),
            ]
        )
        let discovered = DiscoveredAccount(
            label: "Discovered",
            sourceKind: .claudeOAuth,
            credentials: AccountCredentials(
                configDir: home.appending(path: ".claude").path,
                keychain: KeychainReference(
                    service: "Claude Code-credentials",
                    account: "person@example.com"
                )
            )
        )

        DiscoveredAccountMerge.merge([discovered], into: &value, home: home)

        #expect(value.accounts.count == 1)
        #expect(value.accounts[0].id == "acc_existing")
        #expect(value.accounts[0].credentials.keychain == KeychainReference(
            service: "Claude Code-credentials",
            account: "person@example.com"
        ))
    }

    @Test("discovery merges matching Keychain identity instead of duplicating it")
    func discoveryMergesMatchingClaudeKeychain() throws {
        let home = try temporaryHome()
        defer { try? FileManager.default.removeItem(at: home) }
        var value = AccountRegistry(
            revision: 4,
            prefs: AccountPreferences(),
            accounts: [
                Account(
                    id: "acc_existing",
                    label: "Existing",
                    sourceKind: .claudeOAuth,
                    pinned: false,
                    credentials: AccountCredentials(
                        keychain: KeychainReference(
                            service: "Claude Code-credentials",
                            account: "person@example.com"
                        )
                    )
                ),
            ]
        )
        let discovered = DiscoveredAccount(
            label: "Discovered",
            sourceKind: .claudeOAuth,
            credentials: AccountCredentials(
                configDir: home.appending(path: ".claude").path,
                keychain: KeychainReference(
                    service: "Claude Code-credentials",
                    account: "person@example.com"
                )
            )
        )

        DiscoveredAccountMerge.merge([discovered], into: &value, home: home)

        #expect(value.accounts.count == 1)
        #expect(value.accounts[0].credentials.configDir == home.appending(path: ".claude").path)
    }

    @Test("refresh removes Keychain-only accounts missing from discovery")
    func discoveryPrunesStaleKeychainOnlyAccounts() throws {
        let home = try temporaryHome()
        defer { try? FileManager.default.removeItem(at: home) }
        var value = AccountRegistry(
            revision: 4,
            prefs: AccountPreferences(selectedAccountId: "acc_stale"),
            accounts: [
                Account(
                    id: "acc_stale",
                    label: "Gone",
                    sourceKind: .claudeOAuth,
                    pinned: true,
                    credentials: AccountCredentials(
                        keychain: KeychainReference(
                            service: "Claude Code-credentials-deadbeef",
                            account: "dmitry"
                        )
                    )
                ),
                Account(
                    id: "acc_live",
                    label: "Live",
                    sourceKind: .claudeOAuth,
                    pinned: true,
                    credentials: AccountCredentials(
                        keychain: KeychainReference(
                            service: "Claude Code-credentials",
                            account: "dmitry"
                        )
                    )
                ),
            ]
        )
        let discovered = DiscoveredAccount(
            label: "Live",
            sourceKind: .claudeOAuth,
            credentials: AccountCredentials(
                keychain: KeychainReference(
                    service: "Claude Code-credentials",
                    account: "dmitry"
                )
            )
        )

        DiscoveredAccountMerge.merge([discovered], into: &value, home: home, now: Date(timeIntervalSince1970: 100))

        #expect(value.accounts.map(\.id) == ["acc_live"])
        #expect(value.prefs.selectedAccountId == "acc_live")
    }

    @Test("refresh clears dead Keychain refs but keeps config accounts")
    func discoveryClearsStaleKeychainOnConfigAccounts() throws {
        let home = try temporaryHome()
        defer { try? FileManager.default.removeItem(at: home) }
        var value = AccountRegistry(
            revision: 4,
            prefs: AccountPreferences(),
            accounts: [
                Account(
                    id: "acc_config",
                    label: "Config",
                    sourceKind: .claudeOAuth,
                    pinned: false,
                    credentials: AccountCredentials(
                        configDir: "~/.claude-v",
                        keychain: KeychainReference(
                            service: "Claude Code-credentials-deadbeef",
                            account: "dmitry"
                        )
                    )
                ),
            ]
        )

        DiscoveredAccountMerge.merge([], into: &value, home: home)

        #expect(value.accounts.count == 1)
        #expect(value.accounts[0].id == "acc_config")
        #expect(value.accounts[0].credentials.configDir == "~/.claude-v")
        #expect(value.accounts[0].credentials.keychain == nil)
    }

    @Test("helper fingerprint ignores registry revision and account presentation")
    func helperFingerprintTracksOnlyClaudeConfigDirectories() {
        let home = URL(fileURLWithPath: "/Users/example")
        var first = registry(revision: 1, accountID: "acc_first")
        first.accounts[0].credentials.configDir = "~/.claude-work/"
        var second = first
        second.revision = 99
        second.accounts[0].label = "Renamed"
        second.accounts[0].pinned = true
        second.accounts[0].credentials.keychain = KeychainReference(
            service: "different",
            account: "different"
        )

        #expect(
            HelperSetup.fingerprint(for: first, home: home)
                == HelperSetup.fingerprint(for: second, home: home)
        )

        second.accounts[0].credentials.configDir = "~/.claude-other"
        #expect(
            HelperSetup.fingerprint(for: first, home: home)
                != HelperSetup.fingerprint(for: second, home: home)
        )
    }

    @Test("legacy usage warning requires helper reconfiguration")
    func legacyUsageWarningRequiresReconfiguration() {
        let value = registry(revision: 1, accountID: "acc_first")
        let fingerprint = HelperSetup.fingerprint(for: value)
        let diagnostics = HelperDiagnostics(
            launchAgentInstalled: true,
            installedDirectory: "/tmp/helpers",
            installedDirectoryExists: true,
            bundledHelpersAvailable: true,
            helperBinaryAvailable: true,
            configuredFingerprint: fingerprint,
            hasLegacyUsageWarning: true
        )

        #expect(HelperSetup.needsReconfiguration(registry: value, diagnostics: diagnostics))
    }

    @Test("missing helper binary requires reconfiguration")
    func missingHelperBinaryRequiresReconfiguration() {
        let value = registry(revision: 1, accountID: "acc_first")
        let fingerprint = HelperSetup.fingerprint(for: value)
        let diagnostics = HelperDiagnostics(
            launchAgentInstalled: true,
            installedDirectory: "/tmp/helpers",
            installedDirectoryExists: true,
            bundledHelpersAvailable: true,
            helperBinaryAvailable: false,
            configuredFingerprint: fingerprint,
            hasLegacyUsageWarning: false
        )

        #expect(HelperSetup.needsReconfiguration(registry: value, diagnostics: diagnostics))
    }

    @Test("an older mutation completion cannot replace newer UI state")
    func olderCommitDoesNotRegressRegistry() {
        let current = registry(revision: 8, accountID: "acc_newer")
        let committed = registry(revision: 7, accountID: "acc_older")

        let preferred = RegistryCommitOrdering.preferred(
            current: current,
            committed: committed
        )

        #expect(preferred.revision == 8)
        #expect(preferred.accounts.map(\.id) == ["acc_newer"])
    }
}
