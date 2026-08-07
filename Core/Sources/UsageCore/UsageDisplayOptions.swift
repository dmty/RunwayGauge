public struct UsageDisplayOptions: Sendable, Equatable {
    public var showModelScopedLimits: Bool
    public var showSonnetWeekly: Bool
    public var showExtraUsage: Bool
    public var useAPISeverity: Bool
    public var showSessionNotStarted: Bool
    public var showPlanLabel: Bool
    public var showFetchStatus: Bool

    public init(
        showModelScopedLimits: Bool,
        showSonnetWeekly: Bool,
        showExtraUsage: Bool,
        useAPISeverity: Bool,
        showSessionNotStarted: Bool,
        showPlanLabel: Bool,
        showFetchStatus: Bool
    ) {
        self.showModelScopedLimits = showModelScopedLimits
        self.showSonnetWeekly = showSonnetWeekly
        self.showExtraUsage = showExtraUsage
        self.useAPISeverity = useAPISeverity
        self.showSessionNotStarted = showSessionNotStarted
        self.showPlanLabel = showPlanLabel
        self.showFetchStatus = showFetchStatus
    }

    public static let `default` = UsageDisplayOptions(
        showModelScopedLimits: false,
        showSonnetWeekly: false,
        showExtraUsage: false,
        useAPISeverity: false,
        showSessionNotStarted: false,
        showPlanLabel: false,
        showFetchStatus: false
    )

    public func visibleWindows(from record: UsageRecord) -> [UsageWindow] {
        record.windows.filter(isVisible)
    }

    public func level(for window: UsageWindow) -> UsageLevel {
        useAPISeverity
            ? UsageLevel(usedPercent: window.usedPercent, severity: window.severity)
            : UsageLevel(usedPercent: window.usedPercent)
    }

    private func isVisible(_ window: UsageWindow) -> Bool {
        switch window.id {
        case "five_hour", "seven_day":
            return true
        case "seven_day_sonnet":
            return showSonnetWeekly
        case "extra_usage":
            return showExtraUsage
        default:
            if window.id.hasPrefix("weekly_scoped_") {
                return showModelScopedLimits
            }
            return false
        }
    }
}
