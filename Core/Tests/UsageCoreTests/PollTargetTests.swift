import Foundation
import Testing
@testable import UsageCore

private func fixtureURL(_ name: String) throws -> URL {
    var dir = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
    while dir.path != "/" {
        let candidate = dir.appendingPathComponent("tests/fixtures/\(name)")
        if FileManager.default.fileExists(atPath: candidate.path) {
            return candidate
        }
        dir.deleteLastPathComponent()
    }
    Issue.record("Fixture not found: \(name)")
    throw CocoaError(.fileNoSuchFile)
}

@Suite("PollTargetTests")
struct PollTargetTests {
    @Test("lists pinned keychain accounts with selected first")
    func listsFromPollerFixture() throws {
        let data = try Data(contentsOf: fixtureURL("accounts-poller.json"))
        let registry = try JSONDecoder().decode(AccountRegistry.self, from: data)
        let targets = PollTargets.list(from: registry)

        #expect(targets.map(\.accountId) == ["acc_secondary", "acc_primary"])
        guard case .claude(
            let secondaryId,
            let secondaryLabel,
            let secondaryConfig,
            let secondaryService,
            let secondaryAccount
        ) = targets[0] else {
            Issue.record("expected .claude target at [0]")
            return
        }
        #expect(secondaryId == "acc_secondary")
        #expect(secondaryLabel == "Secondary")
        #expect(secondaryConfig == "/tmp/secondary")
        #expect(secondaryService == "shared-service")
        #expect(secondaryAccount == "secondary-user")

        guard case .claude(
            let primaryId,
            _,
            let primaryConfig,
            let primaryService,
            let primaryAccount
        ) = targets[1] else {
            Issue.record("expected .claude target at [1]")
            return
        }
        #expect(primaryId == "acc_primary")
        #expect(primaryConfig == "/tmp/primary")
        #expect(primaryService == "shared-service")
        #expect(primaryAccount == "primary-user")
    }

    @Test("skips pinned accounts without both keychain selectors")
    func skipsConfigOnly() {
        let registry = AccountRegistry(
            schema: AccountRegistry.currentSchema,
            revision: 1,
            prefs: AccountPreferences(selectedAccountId: "acc_a"),
            accounts: [
                Account(
                    id: "acc_a",
                    label: "A",
                    sourceKind: .claudeOAuth,
                    pinned: true,
                    credentials: AccountCredentials(configDir: "/tmp/a", keychain: nil)
                ),
                Account(
                    id: "acc_b",
                    label: "B",
                    sourceKind: .claudeOAuth,
                    pinned: true,
                    credentials: AccountCredentials(
                        configDir: "/tmp/b",
                        keychain: KeychainReference(service: "svc", account: "user")
                    )
                ),
                Account(
                    id: "acc_c",
                    label: "C",
                    sourceKind: .claudeOAuth,
                    pinned: false,
                    credentials: AccountCredentials(
                        configDir: "/tmp/c",
                        keychain: KeychainReference(service: "svc", account: "other")
                    )
                ),
            ]
        )

        let targets = PollTargets.list(from: registry)
        #expect(targets.map(\.accountId) == ["acc_b"])
        guard case .claude(
            let id,
            let label,
            let configDir,
            let service,
            let account
        ) = targets[0] else {
            Issue.record("expected .claude target")
            return
        }
        #expect(id == "acc_b")
        #expect(label == "B")
        #expect(configDir == "/tmp/b")
        #expect(service == "svc")
        #expect(account == "user")
    }

    @Test("lists one pinned Codex target with its absolute executable")
    func listsPinnedCodex() throws {
        let registry = AccountRegistry(
            revision: 2,
            prefs: AccountPreferences(selectedAccountId: CodexAccount.id),
            accounts: [
                Account(
                    id: CodexAccount.id,
                    label: "Codex",
                    sourceKind: .codex,
                    pinned: true,
                    credentials: AccountCredentials(nonSecretFields: [
                        CodexAccount.executablePathKey: "/opt/homebrew/bin/codex",
                    ])
                ),
            ]
        )

        #expect(PollTargets.list(from: registry) == [
            .codex(
                accountId: CodexAccount.id,
                label: "Codex",
                executablePath: "/opt/homebrew/bin/codex"
            ),
        ])
    }

    @Test("skips a pinned Codex row without an executable path")
    func skipsInvalidCodex() {
        let registry = AccountRegistry(
            revision: 2,
            prefs: AccountPreferences(),
            accounts: [Account(
                id: CodexAccount.id,
                label: "Codex",
                sourceKind: .codex,
                pinned: true,
                credentials: AccountCredentials()
            )]
        )

        #expect(PollTargets.list(from: registry).isEmpty)
    }

    @Test("skips the valid default Codex row while it is unpinned")
    func skipsUnpinnedCodex() {
        let registry = AccountRegistry(
            revision: 2,
            prefs: AccountPreferences(),
            accounts: [Account(
                id: CodexAccount.id,
                label: "Codex",
                sourceKind: .codex,
                pinned: false,
                credentials: AccountCredentials(nonSecretFields: [
                    CodexAccount.executablePathKey: "/opt/homebrew/bin/codex",
                ])
            )]
        )

        #expect(PollTargets.list(from: registry).isEmpty)
    }

    @Test("resolves account id from configDir")
    func resolveConfigDir() throws {
        let data = try Data(contentsOf: fixtureURL("accounts-poller.json"))
        let registry = try JSONDecoder().decode(AccountRegistry.self, from: data)
        let id = try ClaudeAccountResolve.accountId(in: registry, configDir: "/tmp/primary")
        #expect(id == "acc_primary")
    }
}
