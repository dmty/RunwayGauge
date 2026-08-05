import SwiftUI
import UsageCore

struct ClaudeUsageView: View {
    let record: UsageRecord
    let freshness: Freshness
    let now: Date
    let compact: Bool

    private let formatter = UsageFormatter(timeZone: .current)
    private var contentPadding: CGFloat { compact ? 14 : 16 }

    var body: some View {
        if record.windows.isEmpty {
            message("No usage data yet — start a Claude Code session.")
        } else {
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
                    // Leave room for cycle + settings controls in the top-trailing corner.
                    .padding(.trailing, 44)
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
