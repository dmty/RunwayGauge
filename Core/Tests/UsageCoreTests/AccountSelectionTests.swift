import Foundation
import Testing
@testable import UsageCore

@Suite("AccountSelectionTests")
struct AccountSelectionTests {
    private func account(_ id: String, pinned: Bool = true) -> Account {
        Account(
            id: id,
            label: id,
            sourceKind: .claudeOAuth,
            pinned: pinned,
            credentials: AccountCredentials()
        )
    }

    private func registry(
        selected: String? = nil,
        rotateEnabled: Bool = false,
        interval: Int = 300,
        anchor: Double? = nil,
        revision: UInt64 = 7,
        accounts: [Account]
    ) -> AccountRegistry {
        AccountRegistry(
            revision: revision,
            prefs: AccountPreferences(
                selectedAccountId: selected,
                rotateEnabled: rotateEnabled,
                rotateIntervalSec: interval,
                rotationAnchorAt: anchor
            ),
            accounts: accounts
        )
    }

    @Test("pinned accounts preserve registry order and skip unpinned accounts")
    func pinnedAccountsPreserveOrder() {
        let value = registry(accounts: [
            account("acc_one"),
            account("acc_hidden", pinned: false),
            account("acc_two")
        ])
        #expect(AccountSelection.pinnedAccounts(in: value).map(\.id) == ["acc_one", "acc_two"])
    }

    @Test("selection requires a pinned account and resets the rotation phase")
    func selectionRequiresPinnedAccount() throws {
        let now = Date(timeIntervalSince1970: 1_000)
        var value = registry(
            selected: "acc_one",
            rotateEnabled: true,
            anchor: 100,
            accounts: [account("acc_one"), account("acc_two"), account("acc_hidden", pinned: false)]
        )

        try AccountSelection.select(id: "acc_two", now: now, in: &value)
        #expect(value.prefs.selectedAccountId == "acc_two")
        #expect(value.prefs.rotationAnchorAt == 1_000)

        #expect(throws: AccountSelectionError.accountNotPinned("acc_hidden")) {
            try AccountSelection.select(id: "acc_hidden", now: now, in: &value)
        }
        #expect(throws: AccountSelectionError.accountNotFound("acc_missing")) {
            try AccountSelection.select(id: "acc_missing", now: now, in: &value)
        }
    }

    @Test("cycling handles zero, one, and multiple pinned accounts")
    func cyclingPinnedCounts() {
        let now = Date(timeIntervalSince1970: 1_000)

        var empty = registry(
            selected: "acc_missing",
            anchor: 100,
            accounts: [account("acc_hidden", pinned: false)]
        )
        AccountSelection.cycleSelected(now: now, in: &empty)
        #expect(empty.prefs.selectedAccountId == nil)

        var single = registry(selected: "acc_one", anchor: 100, accounts: [account("acc_one")])
        AccountSelection.cycleSelected(now: now, in: &single)
        #expect(single.prefs.selectedAccountId == "acc_one")
        #expect(single.prefs.rotationAnchorAt == 100)

        let accounts = [
            account("acc_one"),
            account("acc_hidden", pinned: false),
            account("acc_two"),
            account("acc_three")
        ]
        var value = registry(selected: "acc_one", anchor: 100, accounts: accounts)
        AccountSelection.cycleSelected(now: Date(timeIntervalSince1970: 1_000), in: &value)
        #expect(value.prefs.selectedAccountId == "acc_two")
        #expect(value.prefs.rotationAnchorAt == 1_000)

        AccountSelection.cycleSelected(now: Date(timeIntervalSince1970: 1_100), in: &value)
        #expect(value.prefs.selectedAccountId == "acc_three")

        AccountSelection.cycleSelected(now: Date(timeIntervalSince1970: 1_200), in: &value)
        #expect(value.prefs.selectedAccountId == "acc_one")
    }

    @Test("pin and unpin select stable next pinned account when needed")
    func pinUnpinSelection() throws {
        let now = Date(timeIntervalSince1970: 1_000)

        var firstPin = registry(
            accounts: [account("acc_one", pinned: false), account("acc_two", pinned: false)]
        )
        try AccountSelection.setPinned(id: "acc_two", pinned: true, now: now, in: &firstPin)
        #expect(firstPin.accounts.map(\.pinned) == [false, true])
        #expect(firstPin.prefs.selectedAccountId == "acc_two")
        #expect(firstPin.prefs.rotationAnchorAt == 1_000)

        var unpin = registry(
            selected: "acc_two",
            accounts: [account("acc_one"), account("acc_two"), account("acc_three")]
        )
        try AccountSelection.setPinned(id: "acc_two", pinned: false, now: now, in: &unpin)
        #expect(unpin.prefs.selectedAccountId == "acc_three")
        #expect(unpin.prefs.rotationAnchorAt == 1_000)
    }

    @Test("deleting selected account chooses the next pinned account before removal")
    func deletingSelectedChoosesStableNext() throws {
        let now = Date(timeIntervalSince1970: 1_000)
        let accounts = [account("acc_one"), account("acc_two"), account("acc_three")]

        var middle = registry(selected: "acc_two", accounts: accounts)
        try AccountSelection.deleteAccount(id: "acc_two", now: now, in: &middle)
        #expect(middle.accounts.map(\.id) == ["acc_one", "acc_three"])
        #expect(middle.prefs.selectedAccountId == "acc_three")

        var last = registry(selected: "acc_three", accounts: accounts)
        try AccountSelection.deleteAccount(
            id: "acc_three",
            now: Date(timeIntervalSince1970: 1_100),
            in: &last
        )
        #expect(last.prefs.selectedAccountId == "acc_one")
    }

    @Test("display rotation handles account counts, intervals, and fallbacks")
    func displayRotation() {
        let date = Date(timeIntervalSince1970: 1_600)
        let pair = [account("acc_one"), account("acc_two")]

        #expect(
            AccountSelection.displayedAccount(
                at: date,
                in: registry(
                    selected: nil,
                    rotateEnabled: true,
                    anchor: 1_000,
                    accounts: [account("acc_hidden", pinned: false)]
                )
            ) == nil
        )

        for ids in [["acc_one"], ["acc_one", "acc_two"], ["acc_one", "acc_two", "acc_three"]] {
            let value = registry(
                selected: "acc_one",
                rotateEnabled: true,
                anchor: 1_000,
                accounts: ids.map { account($0) }
            )
            #expect(AccountSelection.displayedAccount(at: date, in: value)?.id == ids[2 % ids.count])
        }

        let delayed = registry(
            selected: "acc_two",
            rotateEnabled: true,
            interval: 300,
            anchor: 1_000,
            accounts: [account("acc_one"), account("acc_two"), account("acc_three")]
        )
        #expect(
            AccountSelection.displayedAccount(
                at: Date(timeIntervalSince1970: 2_250),
                in: delayed
            )?.id == "acc_three"
        )

        let fallbackDate = Date(timeIntervalSince1970: 2_000)
        #expect(AccountSelection.displayedAccount(at: fallbackDate, in: registry(selected: "acc_two", accounts: pair))?.id == "acc_two")
        #expect(AccountSelection.displayedAccount(at: fallbackDate, in: registry(selected: "acc_two", rotateEnabled: true, accounts: pair))?.id == "acc_two")
        #expect(AccountSelection.displayedAccount(at: fallbackDate, in: registry(selected: "acc_two", rotateEnabled: true, anchor: 3_000, accounts: pair))?.id == "acc_two")
        #expect(AccountSelection.displayedAccount(at: fallbackDate, in: registry(selected: "acc_missing", rotateEnabled: true, anchor: 1_000, accounts: pair)) == nil)
    }

    @Test("malformed loaded rotation values return the selected account without trapping")
    func malformedLoadedRotationValuesAreSafe() {
        let accounts = [account("acc_one"), account("acc_two")]
        let invalidInterval = registry(
            selected: "acc_two",
            rotateEnabled: true,
            interval: 0,
            anchor: 1_000,
            accounts: accounts
        )
        #expect(
            AccountSelection.displayedAccount(
                at: Date(timeIntervalSince1970: 2_000),
                in: invalidInterval
            )?.id == "acc_two"
        )

        let extremeElapsed = registry(
            selected: "acc_two",
            rotateEnabled: true,
            interval: 300,
            anchor: 0,
            accounts: accounts
        )
        #expect(
            AccountSelection.displayedAccount(
                at: Date(timeIntervalSince1970: .greatestFiniteMagnitude),
                in: extremeElapsed
            )?.id == "acc_two"
        )
    }

    @Test("display rotation never mutates registry or revision")
    func displayRotationIsPure() {
        let value = registry(
            selected: "acc_one",
            rotateEnabled: true,
            anchor: 1_000,
            revision: 42,
            accounts: [account("acc_one"), account("acc_two"), account("acc_three")]
        )
        let original = value

        _ = AccountSelection.displayedAccount(
            at: Date(timeIntervalSince1970: 8_200),
            in: value
        )

        #expect(value == original)
        #expect(value.revision == 42)
    }
}
