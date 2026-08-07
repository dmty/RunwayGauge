import AppIntents
import UsageCore
import WidgetKit

struct UsageDisplayIntent: WidgetConfigurationIntent {
    static let title: LocalizedStringResource = "Claude Code Usage"
    static let description = IntentDescription("Choose which usage meters appear.")

    @Parameter(title: "Model-scoped limits", default: false)
    var showModelScopedLimits: Bool

    @Parameter(title: "Sonnet weekly", default: false)
    var showSonnetWeekly: Bool

    @Parameter(title: "Extra usage", default: false)
    var showExtraUsage: Bool

    @Parameter(title: "Use API severity colors", default: false)
    var useAPISeverity: Bool

    @Parameter(title: "Session not-started label", default: false)
    var showSessionNotStarted: Bool

    @Parameter(title: "Plan name", default: false)
    var showPlanLabel: Bool

    @Parameter(title: "Fetch errors / rate limits", default: false)
    var showFetchStatus: Bool

    func asOptions() -> UsageDisplayOptions {
        UsageDisplayOptions(
            showModelScopedLimits: showModelScopedLimits,
            showSonnetWeekly: showSonnetWeekly,
            showExtraUsage: showExtraUsage,
            useAPISeverity: useAPISeverity,
            showSessionNotStarted: showSessionNotStarted,
            showPlanLabel: showPlanLabel,
            showFetchStatus: showFetchStatus
        )
    }
}
