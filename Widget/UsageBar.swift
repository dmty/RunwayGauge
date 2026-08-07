import SwiftUI
import UsageCore

struct UsageBar: View {
    let label: String
    let window: UsageWindow
    let level: UsageLevel
    var trailingText: String? = nil
    let resetLine: String
    let dimmed: Bool
    let compact: Bool

    private var fraction: Double { min(max(window.usedPercent / 100, 0), 1) }
    private var percentLabel: String {
        if let trailingText { return trailingText }
        let percent = "\(Int(window.usedPercent.rounded()))%"
        return compact ? percent : "\(percent) used"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: compact ? 3 : 5) {
            HStack(alignment: .firstTextBaseline) {
                Text(label)
                    .font(.system(size: compact ? 12 : 13, weight: .semibold))
                Spacer(minLength: 4)
                Text(percentLabel)
                    .font(.system(size: compact ? 12 : 13, weight: .bold))
                    .monospacedDigit()
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(.white.opacity(0.16))
                    Capsule().fill(level.color).frame(width: geo.size.width * fraction)
                }
            }
            .frame(height: 8)
            Text(resetLine)
                .font(.system(size: compact ? 10 : 11))
                .foregroundStyle(dimmed ? .tertiary : .secondary)
                .lineLimit(1)
        }
    }
}
