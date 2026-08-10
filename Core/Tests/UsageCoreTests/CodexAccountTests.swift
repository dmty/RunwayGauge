import Testing
@testable import UsageCore

@Suite("CodexAccountTests")
struct CodexAccountTests {
    @Test("first ready discovery creates one unpinned managed account")
    func createsDefaultAccount() {
        var registry = AccountRegistry(
            revision: 7,
            prefs: AccountPreferences(selectedAccountId: "acc_claude"),
            accounts: []
        )

        let changed = CodexAccount.merge(
            executablePath: "/opt/homebrew/bin/codex",
            into: &registry
        )

        #expect(changed)
        #expect(registry.accounts == [Account(
            id: "acc_codex_default",
            label: "Codex",
            sourceKind: .codex,
            pinned: false,
            credentials: AccountCredentials(nonSecretFields: [
                "executablePath": "/opt/homebrew/bin/codex",
            ])
        )])
        #expect(registry.prefs.selectedAccountId == "acc_claude")
    }

    @Test("rediscovery updates only the executable path")
    func preservesPreferencesOnRediscovery() {
        var registry = AccountRegistry(
            revision: 8,
            prefs: AccountPreferences(
                selectedAccountId: CodexAccount.id,
                rotateEnabled: true,
                rotateIntervalSec: 900,
                rotationAnchorAt: 42
            ),
            accounts: [Account(
                id: CodexAccount.id,
                label: "Codex",
                sourceKind: .codex,
                pinned: true,
                credentials: AccountCredentials(nonSecretFields: [
                    CodexAccount.executablePathKey: "/usr/local/bin/codex",
                ])
            )]
        )

        #expect(CodexAccount.merge(
            executablePath: "/opt/homebrew/bin/codex",
            into: &registry
        ))
        #expect(registry.accounts.count == 1)
        #expect(registry.accounts[0].pinned)
        #expect(registry.prefs.selectedAccountId == CodexAccount.id)
        #expect(registry.prefs.rotationAnchorAt == 42)
        #expect(registry.accounts[0].credentials.nonSecretFields[
            CodexAccount.executablePathKey
        ] == "/opt/homebrew/bin/codex")
        #expect(!CodexAccount.merge(
            executablePath: "/opt/homebrew/bin/codex",
            into: &registry
        ))
    }
}
