import SwiftUI
import UsageCore

struct ClaudeUsageView: View {
    let state: WidgetState
    let now: Date
    let compact: Bool

    private let formatter = UsageFormatter(timeZone: .current)
    private var contentPadding: CGFloat { compact ? 14 : 16 }

    var body: some View {
        content.containerBackground(for: .widget) { Color.black.opacity(0.92) }
    }

    @ViewBuilder private var content: some View {
        switch state {
        case .empty:
            message("No usage data yet — start a Claude Code session.")
        case .unreadable(let path):
            VStack(alignment: .leading, spacing: 4) {
                Text("Can't read usage data").font(.system(size: 12, weight: .semibold))
                Text(path).font(.system(size: 9)).foregroundStyle(.tertiary).lineLimit(3)
            }
            .padding(contentPadding)
        case .data(let record, let freshness):
            rows(record: record, freshness: freshness)
        }
    }

    private func message(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 11))
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.leading)
            .padding(contentPadding)
    }

    private func rows(record: UsageRecord, freshness: Freshness) -> some View {
        let stale = freshness != .fresh
        let ageSuffix = switch freshness {
        case .fresh: ""
        case .stale(let age): " · \(formatter.ageDescription(age))"
        }

        return VStack(alignment: .leading, spacing: compact ? 10 : 16) {
            if compact {
                Text("CLAUDE CODE")
                    .font(.system(size: 9, weight: .bold))
                    .kerning(0.6)
                    .foregroundStyle(.tertiary)
            }
            ForEach(record.windows, id: \.id) { window in
                UsageBar(
                    label: label(for: window),
                    window: window,
                    resetLine: resetLine(for: window, ageSuffix: ageSuffix),
                    dimmed: stale,
                    compact: compact
                )
            }
        }
        .padding(contentPadding)
        .padding(.horizontal, compact ? 0 : 2)
    }

    private func label(for window: UsageWindow) -> String {
        guard !compact else { return window.label }
        switch window.id {
        case "five_hour": return "Current session"
        case "seven_day": return "Current week (all models)"
        default: return window.label
        }
    }

    private func resetLine(for window: UsageWindow, ageSuffix: String) -> String {
        let reset = formatter.resetDescription(
            window.resetsAt,
            now: now,
            style: compact ? .short : .long
        )
        return compact ? "resets \(reset)\(ageSuffix)" : "Resets \(reset)\(ageSuffix)"
    }
}

#if DEBUG
private let previewNow = Date(timeIntervalSince1970: 1_800_000_000)

private func previewRecord(session: Double, week: Double, updatedAgo: TimeInterval) -> UsageRecord {
    UsageRecord(
        source: "claude-code",
        updatedAt: previewNow.addingTimeInterval(-updatedAgo),
        origin: "statusline",
        windows: [
            UsageWindow(id: "five_hour", label: "Session", usedPercent: session,
                        resetsAt: previewNow.addingTimeInterval(3600)),
            UsageWindow(id: "seven_day", label: "Week", usedPercent: week,
                        resetsAt: previewNow.addingTimeInterval(4 * 86400)),
        ]
    )
}

#Preview("small fresh", as: .systemSmall) {
    UsageWidget()
} timeline: {
    UsageEntry(date: previewNow,
               state: .data(record: previewRecord(session: 19, week: 73, updatedAgo: 30), freshness: .fresh))
}

#Preview("medium fresh", as: .systemMedium) {
    UsageWidget()
} timeline: {
    UsageEntry(date: previewNow,
               state: .data(record: previewRecord(session: 19, week: 73, updatedAgo: 30), freshness: .fresh))
}

#Preview("medium stale", as: .systemMedium) {
    UsageWidget()
} timeline: {
    UsageEntry(date: previewNow,
               state: .data(record: previewRecord(session: 19, week: 73, updatedAgo: 720),
                            freshness: .stale(age: 720)))
}

#Preview("small warning and critical", as: .systemSmall) {
    UsageWidget()
} timeline: {
    UsageEntry(date: previewNow,
               state: .data(record: previewRecord(session: 88, week: 97, updatedAgo: 30), freshness: .fresh))
}

#Preview("medium empty", as: .systemMedium) {
    UsageWidget()
} timeline: {
    UsageEntry(date: previewNow, state: .empty)
}

#Preview("medium unreadable", as: .systemMedium) {
    UsageWidget()
} timeline: {
    UsageEntry(date: previewNow,
               state: .unreadable(path: "/Users/dmitry/Library/Application Support/RunwayGauge/claude-code.json"))
}
#endif
