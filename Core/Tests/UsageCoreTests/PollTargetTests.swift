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
        #expect(targets[0].keychainService == "shared-service")
        #expect(targets[0].keychainAccount == "secondary-user")
        #expect(targets[1].keychainAccount == "primary-user")
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
    }

    @Test("resolves account id from configDir")
    func resolveConfigDir() throws {
        let data = try Data(contentsOf: fixtureURL("accounts-poller.json"))
        let registry = try JSONDecoder().decode(AccountRegistry.self, from: data)
        let id = try ClaudeAccountResolve.accountId(in: registry, configDir: "/tmp/primary")
        #expect(id == "acc_primary")
    }
}
