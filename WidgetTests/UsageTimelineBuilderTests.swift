import Foundation
import Testing
import UsageCore

struct UsageTimelineBuilderTests {
    @Test("rotation emits current and delayed boundary entries without mutating registry")
    func rotatingTimeline() throws {
        let now = Date(timeIntervalSince1970: 1_000)
        let original = registry(
            selected: "acc_a",
            rotate: true,
            interval: 400,
            anchor: 700
        )
        var loaded = original
        var loadedCount = 0
        let builder = UsageTimelineBuilder(
            now: { now },
            loadRegistry: {
                loadedCount += 1
                return loaded
            },
            loadUsage: { id in .record(record(accountID: id, updatedAt: now)) }
        )

        let plan = try builder.makePlan()

        #expect(loadedCount == 1)
        #expect(loaded == original)
        #expect(plan.refreshAfter == nil)
        #expect(plan.entries.map(\.date) == [now, now.addingTimeInterval(300)])
        #expect(plan.entries.map(\.accountID) == ["acc_a", "acc_b"])
        #expect(plan.entries[1].freshness == .fresh)
    }

    @Test("non-rotating timeline repairs selection in memory and refreshes in five minutes")
    func staticTimelineRepairsSelectionInMemory() throws {
        let now = Date(timeIntervalSince1970: 2_000)
        let original = registry(selected: "missing", rotate: false, interval: 900, anchor: nil)
        var loaded = original
        let builder = UsageTimelineBuilder(
            now: { now },
            loadRegistry: { loaded },
            loadUsage: { _ in .missing }
        )

        let plan = try builder.makePlan()

        #expect(loaded == original)
        #expect(plan.refreshAfter == now.addingTimeInterval(300))
        #expect(plan.entries.count == 1)
        #expect(plan.entries[0].accountID == "acc_a")
        #expect(plan.entries[0].paneModel == .usage(
            sourceKind: .claudeOAuth,
            label: "A",
            record: nil
        ))
        #expect(plan.entries[0].loadResult == .missing)
    }

    private func registry(
        selected: String?,
        rotate: Bool,
        interval: Int,
        anchor: Double?
    ) -> AccountRegistry {
        AccountRegistry(
            revision: 4,
            prefs: AccountPreferences(
                selectedAccountId: selected,
                rotateEnabled: rotate,
                rotateIntervalSec: interval,
                rotationAnchorAt: anchor
            ),
            accounts: [
                account(id: "acc_a", label: "A"),
                account(id: "acc_b", label: "B"),
            ]
        )
    }

    private func account(id: String, label: String) -> Account {
        Account(
            id: id,
            label: label,
            sourceKind: .claudeOAuth,
            pinned: true,
            credentials: AccountCredentials()
        )
    }

    private func record(accountID: String, updatedAt: Date) -> UsageRecord {
        UsageRecord(
            accountId: accountID,
            source: "claude-code",
            updatedAt: updatedAt,
            origin: "test",
            windows: [
                UsageWindow(
                    id: "five_hour",
                    label: "Session",
                    usedPercent: 10,
                    resetsAt: updatedAt.addingTimeInterval(600)
                ),
            ]
        )
    }
}
