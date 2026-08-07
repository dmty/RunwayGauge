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
        #expect(plan.entries.map(\.options) == [.default, .default])
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

    @Test("default options keep only session and week visible on entry record")
    func defaultOptionsFilterOptionalWindows() throws {
        let now = Date(timeIntervalSince1970: 3_000)
        let builder = UsageTimelineBuilder(
            now: { now },
            loadRegistry: { registry(selected: "acc_a", rotate: false, interval: 900, anchor: nil) },
            loadUsage: { id in .record(enrichedRecord(accountID: id, updatedAt: now)) }
        )

        let plan = try builder.makePlan(options: .default)
        let entry = try #require(plan.entries.first)
        let record = try #require(entry.record)

        #expect(entry.options == .default)
        #expect(entry.options.visibleWindows(from: record).map(\.id) == ["five_hour", "seven_day"])
    }

    @Test("enabled display options expose sonnet, scoped, and extra windows")
    func enabledOptionsIncludeOptionalWindows() throws {
        let now = Date(timeIntervalSince1970: 3_100)
        var options = UsageDisplayOptions.default
        options.showSonnetWeekly = true
        options.showModelScopedLimits = true
        options.showExtraUsage = true

        let builder = UsageTimelineBuilder(
            now: { now },
            loadRegistry: { registry(selected: "acc_a", rotate: false, interval: 900, anchor: nil) },
            loadUsage: { id in .record(enrichedRecord(accountID: id, updatedAt: now)) }
        )

        let plan = try builder.makePlan(options: options)
        let entry = try #require(plan.entries.first)
        let record = try #require(entry.record)

        #expect(entry.options == options)
        #expect(entry.options.visibleWindows(from: record).map(\.id) == [
            "five_hour",
            "seven_day",
            "seven_day_sonnet",
            "weekly_scoped_fable",
            "extra_usage",
        ])
    }

    @Test("freshness ignores rolled-over hidden optional windows")
    func freshnessUsesVisibleWindowsOnly() throws {
        let now = Date(timeIntervalSince1970: 4_000)
        let builder = UsageTimelineBuilder(
            now: { now },
            loadRegistry: { registry(selected: "acc_a", rotate: false, interval: 900, anchor: nil) },
            loadUsage: { id in
                .record(
                    UsageRecord(
                        accountId: id,
                        source: "claude-code",
                        updatedAt: now.addingTimeInterval(-30),
                        origin: "test",
                        windows: [
                            UsageWindow(
                                id: "five_hour",
                                label: "Session",
                                usedPercent: 10,
                                resetsAt: now.addingTimeInterval(600)
                            ),
                            UsageWindow(
                                id: "seven_day_sonnet",
                                label: "Sonnet",
                                usedPercent: 20,
                                resetsAt: now.addingTimeInterval(-60)
                            ),
                        ]
                    )
                )
            }
        )

        let hidden = try builder.makePlan(options: .default)
        #expect(hidden.entries[0].freshness == .fresh)

        var showSonnet = UsageDisplayOptions.default
        showSonnet.showSonnetWeekly = true
        let visible = try builder.makePlan(options: showSonnet)
        #expect(visible.entries[0].freshness == .stale(age: 30))
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

    private func enrichedRecord(accountID: String, updatedAt: Date) -> UsageRecord {
        UsageRecord(
            accountId: accountID,
            source: "claude-code",
            updatedAt: updatedAt,
            origin: "test",
            windows: [
                UsageWindow(id: "five_hour", label: "Session", usedPercent: 10, resetsAt: updatedAt.addingTimeInterval(600)),
                UsageWindow(id: "seven_day", label: "Week", usedPercent: 20, resetsAt: updatedAt.addingTimeInterval(86_400)),
                UsageWindow(id: "seven_day_sonnet", label: "Sonnet", usedPercent: 30, resetsAt: updatedAt.addingTimeInterval(86_400)),
                UsageWindow(id: "weekly_scoped_fable", label: "Fable", usedPercent: 40, resetsAt: updatedAt.addingTimeInterval(86_400)),
                UsageWindow(id: "extra_usage", label: "Extra", usedPercent: 50, resetsAt: updatedAt.addingTimeInterval(86_400)),
            ]
        )
    }
}
