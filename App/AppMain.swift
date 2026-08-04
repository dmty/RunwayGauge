import SwiftUI
import UsageCore

struct StatusView: View {
    private let url = UsageStore.url(source: "claude-code")

    private var now: Date { Date() }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Usage Widget").font(.headline)

            Text("Add widgets from Notification Center → Edit Widgets.")
                .font(.callout)
                .foregroundStyle(.secondary)

            Divider()

            VStack(alignment: .leading, spacing: 6) {
                Text("Data file").font(.caption).bold()
                Text(url.path)
                    .font(.system(size: 10, design: .monospaced))
                    .textSelection(.enabled)
                    .foregroundStyle(.secondary)
                Text(statusLine).font(.callout)
            }

            Text("Refresh this window to re-check.")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .padding(24)
        .frame(width: 460, alignment: .leading)
    }

    private var statusLine: String {
        let now = self.now
        switch UsageStore.state(for: UsageStore.load(from: url), now: now, path: url.path) {
        case .empty:
            return "No usage data yet — start a Claude Code session."
        case .unreadable:
            return "File exists but could not be read or decoded."
        case .data(let record, let freshness):
            let formatter = UsageFormatter(timeZone: .current)
            let windows = record.windows
                .map { "\($0.label) \(Int($0.usedPercent.rounded()))%" }
                .joined(separator: ", ")
            switch freshness {
            case .fresh:
                return "OK — \(windows), written by \(record.origin)."
            case .stale(let age):
                return "Stale (\(formatter.ageDescription(age))) — \(windows), written by \(record.origin)."
            }
        }
    }
}

@main
struct MacUsageWidgetApp: App {
    var body: some Scene {
        WindowGroup("Usage Widget") {
            StatusView()
        }
        .windowResizability(.contentSize)
    }
}
