import AppIntents
import SwiftUI
import UsageCore
import WidgetKit

struct UsageProvider: AppIntentTimelineProvider {
    private func plan(
        options: UsageDisplayOptions,
        at now: Date = Date()
    ) -> UsageTimelinePlan {
        (try? UsageTimelineBuilder(now: { now }).makePlan(options: options))
            ?? UsageTimelinePlan(
                entries: [.setup(at: now, options: options)],
                refreshAfter: now.addingTimeInterval(TimelineRefresh.interval)
            )
    }

    func placeholder(in context: Context) -> UsageEntry {
        .setup(at: Date())
    }

    func snapshot(for configuration: UsageDisplayIntent, in context: Context) async -> UsageEntry {
        plan(options: configuration.asOptions()).entries[0]
    }

    func timeline(
        for configuration: UsageDisplayIntent,
        in context: Context
    ) async -> Timeline<UsageEntry> {
        let plan = plan(options: configuration.asOptions())
        return Timeline(
            entries: plan.entries,
            policy: plan.refreshAfter.map(TimelineReloadPolicy.after) ?? .atEnd
        )
    }
}

struct UsageWidgetEntryView: View {
    @Environment(\.widgetFamily) private var family
    var entry: UsageEntry

    var body: some View {
        content
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .overlay(alignment: .topTrailing) {
                HStack(spacing: 2) {
                    if entry.pinnedAccountCount >= 2 {
                        Button(intent: CycleAccountIntent()) {
                            Image(systemName: "arrow.triangle.2.circlepath")
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(.tertiary)
                                .frame(width: 18, height: 18)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Show next pinned account")
                    }
                    Button(intent: OpenSettingsIntent()) {
                        Image(systemName: "gearshape")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(.tertiary)
                            .frame(width: 18, height: 18)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Open RunwayGauge Settings")
                }
                .padding(.top, 8)
                .padding(.trailing, 8)
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
                        compact: family == .systemSmall,
                        options: entry.options
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
        AppIntentConfiguration(kind: "UsageWidget", intent: UsageDisplayIntent.self, provider: UsageProvider()) { entry in
            UsageWidgetEntryView(entry: entry)
        }
        .configurationDisplayName("Claude Code Usage")
        .description("Session and weekly usage limits.")
        .supportedFamilies([.systemSmall, .systemMedium])
        .contentMarginsDisabled()
    }
}

@main
struct UsageWidgetBundle: WidgetBundle {
    var body: some Widget { UsageWidget() }
}
