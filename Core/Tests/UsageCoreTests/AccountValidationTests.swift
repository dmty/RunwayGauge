import Darwin
import Foundation
import Testing
@testable import UsageCore

@Suite("AccountValidationTests", .serialized)
struct AccountValidationTests {
    private func account(
        id: String = "acc_valid",
        label: String = "Claude",
        pinned: Bool = true,
        configDir: String? = "~/.claude",
        keychain: KeychainReference? = KeychainReference(
            service: "Claude Code-credentials",
            account: "user@example.com"
        )
    ) -> Account {
        Account(
            id: id,
            label: label,
            sourceKind: .claudeOAuth,
            pinned: pinned,
            credentials: AccountCredentials(configDir: configDir, keychain: keychain)
        )
    }

    private func registry(
        selected: String? = "acc_valid",
        interval: Int = 900,
        accounts: [Account]? = nil
    ) -> AccountRegistry {
        AccountRegistry(
            revision: 0,
            prefs: AccountPreferences(
                selectedAccountId: selected,
                rotateIntervalSec: interval
            ),
            accounts: accounts ?? [account()]
        )
    }

    @Test("rejects an unsupported schema before commit")
    func rejectsUnsupportedSchema() {
        var value = registry()
        value.schema = AccountRegistry.currentSchema + 1

        #expect(throws: AccountValidationError.unsupportedSchema(
            AccountRegistry.currentSchema + 1
        )) {
            try AccountValidation.validateAndRepair(&value)
        }
    }

    @Test("rejects unsafe and duplicate IDs")
    func rejectsUnsafeAndDuplicateIDs() throws {
        var unsafe = registry(accounts: [account(id: "../escape")])
        #expect(throws: AccountValidationError.invalidID("../escape")) {
            try AccountValidation.validateAndRepair(&unsafe)
        }

        var unicode = registry(accounts: [account(id: "acc_é")])
        #expect(throws: AccountValidationError.invalidID("acc_é")) {
            try AccountValidation.validateAndRepair(&unicode)
        }

        var duplicate = registry(accounts: [
            account(id: "acc_same"),
            account(id: "acc_same", configDir: nil)
        ])
        #expect(throws: AccountValidationError.duplicateID("acc_same")) {
            try AccountValidation.validateAndRepair(&duplicate)
        }
    }

    @Test("normalizes labels and enforces documented maximum")
    func validatesLabels() throws {
        var trimmed = registry(accounts: [account(label: "  Claude Work  ")])
        try AccountValidation.validateAndRepair(&trimmed)
        #expect(trimmed.accounts[0].label == "Claude Work")

        var empty = registry(accounts: [account(label: " \n ")])
        #expect(throws: AccountValidationError.invalidLabel(" \n ")) {
            try AccountValidation.validateAndRepair(&empty)
        }

        let tooLong = String(repeating: "a", count: AccountValidation.maximumLabelLength + 1)
        var long = registry(accounts: [account(label: tooLong)])
        #expect(throws: AccountValidationError.invalidLabel(tooLong)) {
            try AccountValidation.validateAndRepair(&long)
        }
    }

    @Test("rejects blank Claude config directories but permits nil")
    func rejectsBlankClaudeConfigDirectories() throws {
        for path in ["", " \n\t "] {
            var blank = registry(accounts: [account(configDir: path)])
            #expect(throws: AccountValidationError.invalidConfigDirectory(path)) {
                try AccountValidation.validateAndRepair(&blank)
            }
        }

        var configless = registry(accounts: [account(configDir: nil)])
        try AccountValidation.validateAndRepair(&configless)
        #expect(configless.accounts[0].credentials.configDir == nil)
    }

    @Test("rejects duplicate normalized tilde and trailing-slash paths")
    func rejectsDuplicateTildePaths() {
        let home = URL(fileURLWithPath: "/tmp/account-validation-home")
        var value = registry(accounts: [
            account(
                id: "acc_one",
                configDir: "~/.claude/",
                keychain: KeychainReference(service: "service", account: "one")
            ),
            account(
                id: "acc_two",
                configDir: "/tmp/account-validation-home/.claude",
                keychain: KeychainReference(service: "service", account: "two")
            ),
        ])

        #expect(throws: AccountValidationError.duplicateConfigDirectory(
            "/tmp/account-validation-home/.claude"
        )) {
            try AccountValidation.validateAndRepair(&value, home: home)
        }
    }

    @Test("rejects duplicate paths through an existing symlink")
    func rejectsDuplicateSymlinkPaths() throws {
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appending(path: "account-validation-\(UUID().uuidString)")
        let real = root.appending(path: "real")
        let link = root.appending(path: "link")
        try FileManager.default.createDirectory(at: real, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: real)

        var value = registry(accounts: [
            account(
                id: "acc_one",
                configDir: real.path,
                keychain: KeychainReference(service: "service", account: "one")
            ),
            account(
                id: "acc_two",
                configDir: link.path,
                keychain: KeychainReference(service: "service", account: "two")
            ),
        ])
        #expect(throws: AccountValidationError.duplicateConfigDirectory(real.path)) {
            try AccountValidation.validateAndRepair(&value)
        }
    }

    @Test("repairs invalid selection to first pinned account")
    func repairsInvalidSelection() throws {
        var value = registry(
            selected: "acc_missing",
            accounts: [
                account(
                    id: "acc_unpinned",
                    pinned: false,
                    keychain: KeychainReference(service: "service", account: "unpinned")
                ),
                account(
                    id: "acc_first",
                    configDir: nil,
                    keychain: KeychainReference(service: "service", account: "first")
                ),
                account(
                    id: "acc_second",
                    configDir: nil,
                    keychain: KeychainReference(service: "service", account: "second")
                ),
            ]
        )
        value.prefs.rotationAnchorAt = 1_000

        try AccountValidation.validateAndRepair(&value)
        #expect(value.prefs.selectedAccountId == "acc_first")
        #expect(value.prefs.rotationAnchorAt == nil)
    }

    @Test("preserves a nil selection because nil is valid")
    func preservesNilSelection() throws {
        var value = registry(
            selected: nil,
            accounts: [account(id: "acc_pinned")]
        )

        try AccountValidation.validateAndRepair(&value)
        #expect(value.prefs.selectedAccountId == nil)
    }

    @Test(arguments: [299, 86_401])
    func rejectsOutOfRangeRotationIntervals(_ interval: Int) {
        var value = registry(interval: interval)
        #expect(throws: AccountValidationError.invalidRotationInterval(interval)) {
            try AccountValidation.validateAndRepair(&value)
        }
    }

    @Test("normalizes empty keychain account and exposes poll capability")
    func validatesKeychainPollCapability() throws {
        let paddedService = " Claude Code-credentials "
        let paddedAccount = " user@example.com "
        var padded = registry(accounts: [
            account(keychain: KeychainReference(
                service: paddedService,
                account: paddedAccount
            ))
        ])
        try AccountValidation.validateAndRepair(&padded)
        #expect(padded.accounts[0].credentials.keychain?.service == paddedService)
        #expect(padded.accounts[0].credentials.keychain?.account == paddedAccount)
        #expect(AccountValidation.isPollCapable(padded.accounts[0]) == true)

        var value = registry(accounts: [
            account(keychain: KeychainReference(
                service: "Claude Code-credentials",
                account: "  "
            ))
        ])
        try AccountValidation.validateAndRepair(&value)
        #expect(value.accounts[0].credentials.keychain?.account == nil)
        #expect(AccountValidation.isPollCapable(value.accounts[0]) == false)

        var invalidService = registry(accounts: [
            account(keychain: KeychainReference(service: " ", account: "user@example.com"))
        ])
        #expect(throws: AccountValidationError.emptyKeychainService("acc_valid")) {
            try AccountValidation.validateAndRepair(&invalidService)
        }
    }

    @Test("rejects duplicate Claude Keychain identities")
    func rejectsDuplicateClaudeKeychainIdentities() {
        var value = registry(accounts: [
            account(
                id: "acc_one",
                configDir: "~/.claude-one",
                keychain: KeychainReference(service: " service ", account: " user@example.com ")
            ),
            account(
                id: "acc_two",
                configDir: "~/.claude-two",
                keychain: KeychainReference(service: "service", account: "user@example.com")
            ),
        ])

        #expect(throws: AccountValidationError.duplicateKeychainReference(
            "service",
            "user@example.com"
        )) {
            try AccountValidation.validateAndRepair(&value)
        }
    }

    @Test("default tilde expansion uses passwd home instead of container home")
    func expandsTildeAgainstRealUserHome() throws {
        let variable = "CFFIXED_USER_HOME"
        let original = getenv(variable).map { String(cString: $0) }
        let containerHome = "/tmp/runway-gauge-container-home"
        setenv(variable, containerHome, 1)
        defer {
            if let original {
                setenv(variable, original, 1)
            } else {
                unsetenv(variable)
            }
        }

        #expect(FileManager.default.homeDirectoryForCurrentUser.path == containerHome)
        let passwd = try #require(getpwuid(getuid()))
        let realHome = String(cString: passwd.pointee.pw_dir)
        #expect(AccountValidation.normalizePath("~") == realHome)
        #expect(AccountValidation.normalizePath("~/claude") == realHome + "/claude")
    }

    @Test("expands only bare and slash-prefixed tilde")
    func expandsOnlySupportedTildeForms() {
        let home = URL(fileURLWithPath: "/Users/example")
        #expect(AccountValidation.normalizePath("~", home: home) == "/Users/example")
        #expect(AccountValidation.normalizePath("~/a/../b/", home: home) == "/Users/example/b")
        #expect(AccountValidation.normalizePath("~root/config", home: home) == "~root/config")
        #expect(AccountValidation.normalizePath("missing/../../target/", home: home) == "../target")
        #expect(AccountValidation.normalizePath("../a/../../b", home: home) == "../../b")
    }
}
