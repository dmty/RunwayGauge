import SwiftUI
import UsageCore

struct UsageBar: View {
    let label: String
    let window: UsageWindow
    let level: UsageLevel
    var trailingText: String? = nil
    let resetLine: String
    let dimmed: Bool
    let density: UsageGaugeDensity

    private var fraction: Double { min(max(window.usedPercent / 100, 0), 1) }
    private var percentLabel: String {
        if let trailingText { return trailingText }
        let percent = "\(Int(window.usedPercent.rounded()))%"
        return density.compact ? percent : "\(percent) used"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: density.barSpacing) {
            HStack(alignment: .firstTextBaseline) {
                Text(label)
                    .font(.system(size: density.labelSize, weight: .semibold))
                Spacer(minLength: 4)
                Text(percentLabel)
                    .font(.system(size: density.labelSize, weight: .bold))
                    .monospacedDigit()
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(.white.opacity(0.16))
                    Capsule().fill(level.color).frame(width: geo.size.width * fraction)
                }
            }
            .frame(height: density.barHeight)
            Text(resetLine)
                .font(.system(size: density.resetSize))
                .foregroundStyle(dimmed ? .tertiary : .secondary)
                .lineLimit(1)
        }
    }
}
