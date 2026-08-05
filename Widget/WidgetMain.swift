import AppIntents
import SwiftUI
import UsageCore
import WidgetKit

struct UsageProvider: TimelineProvider {
    private func plan(at now: Date = Date()) -> UsageTimelinePlan {
        (try? UsageTimelineBuilder(now: { now }).makePlan())
            ?? UsageTimelinePlan(
                entries: [.setup(at: now)],
                refreshAfter: now.addingTimeInterval(TimelineRefresh.interval)
            )
    }

    func placeholder(in context: Context) -> UsageEntry {
        .setup(at: Date())
    }

    func getSnapshot(in context: Context, completion: @escaping (UsageEntry) -> Void) {
        completion(plan().entries[0])
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<UsageEntry>) -> Void) {
        let plan = plan()
        completion(Timeline(
            entries: plan.entries,
            policy: plan.refreshAfter.map(TimelineReloadPolicy.after) ?? .atEnd
        ))
    }
}

struct UsageWidgetEntryView: View {
    @Environment(\.widgetFamily) private var family
    var entry: UsageEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let label = entry.accountLabel {
                Text(label).font(.caption2).bold()
            }
            content
            if entry.pinnedAccountCount >= 2 {
                Button(intent: CycleAccountIntent()) {
                    Label("Next account", systemImage: "arrow.triangle.2.circlepath")
                        .labelStyle(.iconOnly)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Show next pinned account")
            }
        }
        .containerBackground(for: .widget) { Color.black.opacity(0.92) }
    }

    @ViewBuilder
    private var content: some View {
        switch entry.paneModel {
        case nil:
            message("Open RunwayGauge Settings to pin an account.")
        case .unsupported(let kind, let label):
            StubSourceView(label: label, detail: "Unsupported source: \(kind.rawValue)")
        case .comingSoon(_, let label):
            StubSourceView(label: label, detail: "Coming soon")
        case .usage:
            switch entry.loadResult {
            case .missing:
                message("No data yet. Check helper status in RunwayGauge.")
            case .unreadable:
                message("Usage data is unreadable or belongs to another account.")
            case .record:
                if let record = entry.record, let freshness = entry.freshness {
                    ClaudeUsageView(
                        record: record,
                        freshness: freshness,
                        now: entry.date,
                        compact: family == .systemSmall
                    )
                } else {
                    message("No usage data yet.")
                }
            case nil:
                message("No usage data yet.")
            }
        }
    }

    private func message(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 11))
            .foregroundStyle(.secondary)
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
