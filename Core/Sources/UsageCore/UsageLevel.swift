public enum UsageLevel: String, Sendable, Equatable, CaseIterable {
    case normal
    case warning
    case critical

    public init(usedPercent: Double) {
        self.init(usedPercent: usedPercent, severity: nil)
    }

    public init(usedPercent: Double, severity: String?) {
        if let severity {
            switch severity {
            case "warning":
                self = .warning
                return
            case "critical":
                self = .critical
                return
            case "normal":
                self = .normal
                return
            default:
                break
            }
        }
        switch usedPercent {
        case ..<80: self = .normal
        case ..<95: self = .warning
        default: self = .critical
        }
    }
}
