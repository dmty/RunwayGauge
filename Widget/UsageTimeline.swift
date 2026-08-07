import Foundation
import UsageCore
import WidgetKit

enum TimelineRefresh {
    static let interval: TimeInterval = 300
}

struct UsageEntry: TimelineEntry {
    let date: Date
    let accountID: String?
    let accountLabel: String?
    let sourceKind: SourceKind?
    let paneModel: UsagePaneModel?
    let record: UsageRecord?
    let loadResult: UsageLoadResult?
    let freshness: Freshness?
    let pinnedAccountCount: Int
    let options: UsageDisplayOptions

    static func setup(at date: Date, options: UsageDisplayOptions = .default) -> UsageEntry {
        UsageEntry(
            date: date,
            accountID: nil,
            accountLabel: nil,
            sourceKind: nil,
            paneModel: nil,
            record: nil,
            loadResult: nil,
            freshness: nil,
            pinnedAccountCount: 0,
            options: options
        )
    }
}

struct UsageTimelinePlan {
    let entries: [UsageEntry]
    let refreshAfter: Date?
}

struct UsageTimelineBuilder {
    let now: () -> Date
    let loadRegistry: () throws -> AccountRegistry
    let loadUsage: (String) -> UsageLoadResult

    static func plan(
        options: UsageDisplayOptions = .default,
        now: Date = Date()
    ) -> UsageTimelinePlan {
        (try? UsageTimelineBuilder(now: { now }).makePlan(options: options))
            ?? UsageTimelinePlan(
                entries: [.setup(at: now, options: options)],
                refreshAfter: now.addingTimeInterval(TimelineRefresh.interval)
            )
    }

    init(
        now: @escaping () -> Date = Date.init,
        loadRegistry: @escaping () throws -> AccountRegistry = {
            try AccountStore.load(from: AccountStore.url())
        },
        loadUsage: @escaping (String) -> UsageLoadResult = {
            UsageStore.load(accountId: $0)
        }
    ) {
        self.now = now
        self.loadRegistry = loadRegistry
        self.loadUsage = loadUsage
    }

    func makePlan(options: UsageDisplayOptions = .default) throws -> UsageTimelinePlan {
        let currentDate = now()
        var registry = try loadRegistry()
        let pinned = AccountSelection.pinnedAccounts(in: registry)
        guard !pinned.isEmpty else {
            return staticRefresh([.setup(at: currentDate, options: options)], at: currentDate)
        }

        repairSelection(in: &registry, pinned: pinned, at: currentDate)

        guard let current = entry(
            at: currentDate,
            registry: registry,
            pinnedCount: pinned.count,
            options: options
        ) else {
            return staticRefresh([.setup(at: currentDate, options: options)], at: currentDate)
        }

        guard registry.prefs.rotateEnabled,
              pinned.count > 1,
              registry.prefs.rotateIntervalSec > 0,
              let anchor = registry.prefs.rotationAnchorAt else {
            return staticRefresh([current], at: currentDate)
        }

        let interval = Double(registry.prefs.rotateIntervalSec)
        let elapsed = max(0, currentDate.timeIntervalSince1970 - anchor)
        let boundary = Date(timeIntervalSince1970: anchor + (floor(elapsed / interval) + 1) * interval)
        let nextDate = max(boundary, currentDate.addingTimeInterval(TimelineRefresh.interval))
        guard let next = entry(
            at: nextDate,
            registry: registry,
            pinnedCount: pinned.count,
            options: options
        ) else {
            return UsageTimelinePlan(entries: [current], refreshAfter: nil)
        }
        return UsageTimelinePlan(entries: [current, next], refreshAfter: nil)
    }

    private func staticRefresh(_ entries: [UsageEntry], at date: Date) -> UsageTimelinePlan {
        UsageTimelinePlan(entries: entries, refreshAfter: date.addingTimeInterval(TimelineRefresh.interval))
    }

    // ponytail: in-memory only; host owns registry migration
    private func repairSelection(in registry: inout AccountRegistry, pinned: [Account], at date: Date) {
        guard registry.prefs.selectedAccountId.flatMap({ id in pinned.first { $0.id == id } }) == nil else {
            return
        }
        registry.prefs.selectedAccountId = pinned[0].id
        registry.prefs.rotationAnchorAt = date.timeIntervalSince1970
    }

    private func entry(
        at date: Date,
        registry: AccountRegistry,
        pinnedCount: Int,
        options: UsageDisplayOptions
    ) -> UsageEntry? {
        guard let account = AccountSelection.displayedAccount(at: date, in: registry) else {
            return nil
        }
        let result = loadUsage(account.id)
        let record: UsageRecord? = if case .record(let value) = result { value } else { nil }
        return UsageEntry(
            date: date,
            accountID: account.id,
            accountLabel: account.label,
            sourceKind: account.sourceKind,
            paneModel: SourceCatalog.paneModel(for: account, record: record),
            record: record,
            loadResult: result,
            freshness: record.map {
                Freshness.evaluate($0, now: date, windows: options.visibleWindows(from: $0))
            },
            pinnedAccountCount: pinnedCount,
            options: options
        )
    }
}
