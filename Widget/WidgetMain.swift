import SwiftUI
import UsageCore
import WidgetKit

struct UsageEntry: TimelineEntry {
    let date: Date
    let state: WidgetState
}

struct UsageProvider: TimelineProvider {
    private func currentEntry(now: Date = Date()) -> UsageEntry {
        let url = UsageStore.url(source: "claude-code")
        let result = UsageStore.load(from: url)
        return UsageEntry(date: now, state: UsageStore.state(for: result, now: now, path: url.path))
    }

    func placeholder(in context: Context) -> UsageEntry {
        UsageEntry(date: Date(), state: .empty)
    }

    func getSnapshot(in context: Context, completion: @escaping (UsageEntry) -> Void) {
        completion(currentEntry())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<UsageEntry>) -> Void) {
        let now = Date()
        // One entry only: a precomputed multi-entry timeline would carry data read now
        // into future entries, displaying numbers already known to be stale.
        completion(Timeline(entries: [currentEntry(now: now)],
                            policy: .after(now.addingTimeInterval(300))))
    }
}

struct UsageWidgetEntryView: View {
    @Environment(\.widgetFamily) private var family
    var entry: UsageEntry

    var body: some View {
        ClaudeUsageView(state: entry.state, now: entry.date, compact: family == .systemSmall)
    }
}

struct UsageWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "UsageWidget", provider: UsageProvider()) { entry in
            UsageWidgetEntryView(entry: entry)
        }
        .configurationDisplayName("Claude Code Usage")
        .description("Session and weekly usage limits.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

@main
struct UsageWidgetBundle: WidgetBundle {
    var body: some Widget { UsageWidget() }
}
