import SwiftUI
import WidgetKit

struct ProbeEntry: TimelineEntry {
    let date: Date
    let readResult: String

    init(date: Date = Date()) {
        self.date = date
        self.readResult = probeRead()
    }
}

func probeRead() -> String {
    let url = FileManager.default.homeDirectoryForCurrentUser
        .appending(path: "Library/Application Support/MacUsageWidget/probe.txt")
    do {
        return try String(contentsOf: url, encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines)
    } catch {
        return "ERR: \((error as NSError).code)"
    }
}

struct ProbeProvider: TimelineProvider {
    func placeholder(in context: Context) -> ProbeEntry { ProbeEntry() }

    func getSnapshot(in context: Context, completion: @escaping (ProbeEntry) -> Void) {
        completion(ProbeEntry())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<ProbeEntry>) -> Void) {
        let now = Date()
        completion(Timeline(entries: [ProbeEntry(date: now)], policy: .after(now.addingTimeInterval(300))))
    }
}

struct ProbeView: View {
    var entry: ProbeEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(entry.readResult).font(.caption).bold()
            Text(entry.date, style: .time).font(.caption2).foregroundStyle(.secondary)
        }
        .containerBackground(for: .widget) { Color.black.opacity(0.9) }
    }
}

struct UsageWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "UsageWidget", provider: ProbeProvider()) { entry in
            ProbeView(entry: entry)
        }
        .configurationDisplayName("Claude Code Usage")
        .description("Session and weekly usage.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

@main
struct UsageWidgetBundle: WidgetBundle {
    var body: some Widget { UsageWidget() }
}
