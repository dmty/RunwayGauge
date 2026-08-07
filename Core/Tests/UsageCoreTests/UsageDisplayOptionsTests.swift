import Foundation
import Testing
@testable import UsageCore

@Suite("UsageDisplayOptionsTests")
struct UsageDisplayOptionsTests {
    private let now = Date(timeIntervalSince1970: 1_700_000_000)

    private func window(
        id: String,
        label: String = "",
        usedPercent: Double = 50,
        severity: String? = nil
    ) -> UsageWindow {
        UsageWindow(
            id: id,
            label: label.isEmpty ? id : label,
            usedPercent: usedPercent,
            resetsAt: now.addingTimeInterval(3600),
            severity: severity
        )
    }

    private func record(windows: [UsageWindow]) -> UsageRecord {
        UsageRecord(
            source: "claude-code",
            updatedAt: now,
            origin: "poll",
            windows: windows
        )
    }

    @Test("default disables optional display toggles")
    func defaultOptions() {
        let options = UsageDisplayOptions.default
        #expect(!options.showModelScopedLimits)
        #expect(!options.showSonnetWeekly)
        #expect(!options.showExtraUsage)
        #expect(!options.useAPISeverity)
        #expect(!options.showSessionNotStarted)
        #expect(!options.showPlanLabel)
        #expect(!options.showFetchStatus)
    }

    @Test("default visibleWindows keeps session and week only")
    func defaultVisibleWindows() {
        let windows = [
            window(id: "five_hour", label: "Session"),
            window(id: "seven_day", label: "Week"),
            window(id: "seven_day_sonnet", label: "Sonnet"),
            window(id: "weekly_scoped_fable", label: "Fable"),
            window(id: "extra_usage", label: "Extra usage"),
        ]
        let visible = UsageDisplayOptions.default.visibleWindows(from: record(windows: windows))
        #expect(visible.map(\.id) == ["five_hour", "seven_day"])
    }

    @Test("showSonnetWeekly includes sonnet window")
    func sonnetToggle() {
        var options = UsageDisplayOptions.default
        options.showSonnetWeekly = true
        let windows = [
            window(id: "five_hour", label: "Session"),
            window(id: "seven_day_sonnet", label: "Sonnet"),
        ]
        let visible = options.visibleWindows(from: record(windows: windows))
        #expect(visible.map(\.id) == ["five_hour", "seven_day_sonnet"])
    }

    @Test("showModelScopedLimits includes weekly_scoped windows")
    func modelScopedToggle() {
        var options = UsageDisplayOptions.default
        options.showModelScopedLimits = true
        let windows = [
            window(id: "seven_day", label: "Week"),
            window(id: "weekly_scoped_fable", label: "Fable"),
            window(id: "weekly_scoped_opus", label: "Opus"),
        ]
        let visible = options.visibleWindows(from: record(windows: windows))
        #expect(visible.map(\.id) == ["seven_day", "weekly_scoped_fable", "weekly_scoped_opus"])
    }

    @Test("showExtraUsage includes extra_usage window")
    func extraUsageToggle() {
        var options = UsageDisplayOptions.default
        options.showExtraUsage = true
        let windows = [
            window(id: "five_hour", label: "Session"),
            window(id: "extra_usage", label: "Extra usage"),
        ]
        let visible = options.visibleWindows(from: record(windows: windows))
        #expect(visible.map(\.id) == ["five_hour", "extra_usage"])
    }

    @Test("visibleWindows preserves mapper order")
    func preservesOrder() {
        var options = UsageDisplayOptions.default
        options.showSonnetWeekly = true
        options.showModelScopedLimits = true
        options.showExtraUsage = true
        let windows = [
            window(id: "five_hour", label: "Session"),
            window(id: "seven_day", label: "Week"),
            window(id: "seven_day_sonnet", label: "Sonnet"),
            window(id: "weekly_scoped_fable", label: "Fable"),
            window(id: "extra_usage", label: "Extra usage"),
        ]
        let visible = options.visibleWindows(from: record(windows: windows))
        #expect(visible.map(\.id) == windows.map(\.id))
    }

    @Test("level ignores severity when useAPISeverity is false")
    func levelPercentOnly() {
        let options = UsageDisplayOptions.default
        let window = window(id: "five_hour", usedPercent: 10, severity: "critical")
        #expect(options.level(for: window) == .normal)
    }

    @Test("level prefers severity when useAPISeverity is true")
    func levelUsesSeverity() {
        var options = UsageDisplayOptions.default
        options.useAPISeverity = true
        let window = window(id: "five_hour", usedPercent: 10, severity: "critical")
        #expect(options.level(for: window) == .critical)
    }
}
