public enum UsageLevel: String, Sendable, Equatable, CaseIterable {
    case normal
    case warning
    case critical

    public init(usedPercent: Double) {
        self.init(usedPercent: usedPercent, severity: nil)
    }

    public init(usedPercent: Double, severity: String?) {
        if let severity, let level = Self(rawValue: severity) {
            self = level
            return
        }
        switch usedPercent {
        case ..<80: self = .normal
        case ..<95: self = .warning
        default: self = .critical
        }
    }
}
