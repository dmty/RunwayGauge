import SwiftUI
import UsageCore

struct UsageGaugeView: View {
    let record: UsageRecord
    let sourceKind: SourceKind
    let freshness: Freshness
    let now: Date
    let compact: Bool
    var options: UsageDisplayOptions = .default

    private let formatter = UsageFormatter(timeZone: .current)
    private var presentation: UsageSourcePresentation {
        SourceCatalog.presentation(for: sourceKind)
    }

    var body: some View {
        let windows = options.visibleWindows(from: record)
        if windows.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                message(presentation.emptyMessage)
                if let fetchLine = fetchStatusLine {
                    message(fetchLine)
                }
            }
        } else {
            rows(windows: windows, freshness: freshness)
        }
    }

    private func message(_ text: String) -> some View {
        let density = UsageGaugePolicy.density(compact: compact, windowCount: 0)
        return Text(text)
            .font(.system(size: 11))
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.leading)
            .padding(density.contentPadding)
    }

    private func rows(
        windows: [UsageWindow],
        freshness: Freshness
    ) -> some View {
        let stale = freshness != .fresh
        let ageSuffix = switch freshness {
        case .fresh: ""
        case .stale(let age): " · \(formatter.ageDescription(age))"
        }
        let density = UsageGaugePolicy.density(compact: compact, windowCount: windows.count)

        return VStack(alignment: .leading, spacing: density.rowSpacing) {
            if compact {
                Text(UsageGaugePolicy.compactTitle(
                    header: presentation.compactHeader,
                    plan: record.plan,
                    showPlan: options.showPlanLabel
                ))
                    .font(.system(size: density.headerSize, weight: .bold))
                    .kerning(0.6)
                    .foregroundStyle(.tertiary)
                    .padding(.trailing, 44)
            }
            if !compact, options.showPlanLabel, let plan = record.plan, !plan.isEmpty {
                Text(plan)
                    .font(.system(size: compact ? 10 : 11, weight: .medium))
                    .foregroundStyle(.secondary)
                    .padding(.trailing, compact ? 44 : 0)
            }
            ForEach(windows, id: \.id) { window in
                let notStarted = UsageGaugePolicy.showsSessionNotStarted(
                    sourceKind: sourceKind,
                    window: window,
                    options: options
                )
                UsageBar(
                    label: label(for: window),
                    window: window,
                    level: options.level(for: window),
                    trailingText: notStarted ? "Not started" : nil,
                    resetLine: notStarted
                        ? "Not started"
                        : resetLine(for: window, ageSuffix: ageSuffix),
                    dimmed: stale,
                    density: density
                )
            }
            if let fetchLine = fetchStatusLine {
                Text(fetchLine)
                    .font(.system(size: compact ? 10 : 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
        .padding(density.contentPadding)
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

    private func resetLine(
        for window: UsageWindow,
        ageSuffix: String
    ) -> String {
        let reset = formatter.resetDescription(
            window.resetsAt,
            now: now,
            style: compact ? .short : .long
        )
        return compact
            ? "resets \(reset)\(ageSuffix)"
            : "Resets \(reset)\(ageSuffix)"
    }

    private var fetchStatusLine: String? {
        guard options.showFetchStatus,
              let status = record.fetchStatus,
              status.state != .ok
        else { return nil }
        if let message = status.message, !message.isEmpty { return message }
        return status.state == .rateLimited ? "Rate limited" : "Fetch failed"
    }
}
