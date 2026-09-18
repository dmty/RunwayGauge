import CoreGraphics
import UsageCore

struct UsageGaugeDensity: Equatable, Sendable {
    var compact: Bool
    var contentPadding: CGFloat
    var rowSpacing: CGFloat
    var barSpacing: CGFloat
    var barHeight: CGFloat
    var labelSize: CGFloat
    var resetSize: CGFloat
    var headerSize: CGFloat

    /// Small widgets are 155–169pt. Budget 158 so three compact rows clear the rounded clip.
    func estimatedHeight(windowCount: Int, showsHeader: Bool) -> CGFloat {
        let header = showsHeader ? headerSize + 4 : 0
        let bar = labelSize + 3 + barSpacing + barHeight + barSpacing + resetSize + 3
        let gaps = CGFloat(max(windowCount - 1, 0)) * rowSpacing
        return contentPadding * 2 + header + CGFloat(windowCount) * bar + gaps
    }
}

enum UsageGaugePolicy {
    static func showsSessionNotStarted(
        sourceKind: SourceKind,
        window: UsageWindow,
        options: UsageDisplayOptions
    ) -> Bool {
        SourceCatalog.presentation(for: sourceKind).supportsSessionNotStarted
            && options.showSessionNotStarted
            && window.id == "five_hour"
            && window.usedPercent <= 0
    }

    static func density(compact: Bool, windowCount: Int) -> UsageGaugeDensity {
        if !compact { return medium }
        return windowCount >= 3 ? compactTight : compactRegular
    }

    static func compactTitle(header: String, plan: String?, showPlan: Bool) -> String {
        guard showPlan, let plan, !plan.isEmpty else { return header }
        return "\(header) · \(plan)"
    }

    private static let medium = UsageGaugeDensity(
        compact: false,
        contentPadding: 16,
        rowSpacing: 16,
        barSpacing: 5,
        barHeight: 8,
        labelSize: 13,
        resetSize: 11,
        headerSize: 9
    )

    private static let compactRegular = UsageGaugeDensity(
        compact: true,
        contentPadding: 14,
        rowSpacing: 10,
        barSpacing: 3,
        barHeight: 8,
        labelSize: 12,
        resetSize: 10,
        headerSize: 9
    )

    private static let compactTight = UsageGaugeDensity(
        compact: true,
        contentPadding: 10,
        rowSpacing: 5,
        barSpacing: 2,
        barHeight: 7,
        labelSize: 11,
        resetSize: 9,
        headerSize: 8
    )
}
