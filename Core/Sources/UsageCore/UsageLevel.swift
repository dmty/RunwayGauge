public enum UsageLevel: String, Sendable, Equatable, CaseIterable {
    case normal
    case warning
    case critical

    public init(usedPercent: Double) {
        switch usedPercent {
        case ..<80: self = .normal
        case ..<95: self = .warning
        default: self = .critical
        }
    }
}
