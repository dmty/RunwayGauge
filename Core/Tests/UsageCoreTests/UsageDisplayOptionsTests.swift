import Foundation
import Testing
@testable import UsageCore

@Suite("UsageDisplayOptionsTests")
struct UsageDisplayOptionsTests {
    private let now = Date(timeIntervalSince1970: 1_700_000_000)

    private func window(id: String, usedPercent: Double = 50, severity: String? = nil) -> UsageWindow {
        UsageWindow(
            id: id,
            label: id,
            usedPercent: usedPercent,
            resetsAt: now.addingTimeInterval(3600),
            severity: severity
        )
    }

    private func record(windows: [UsageWindow]) -> UsageRecord {
        UsageRecord(source: "claude-code", updatedAt: now, origin: "poll", windows: windows)
    }

    @Test("default disables optional display toggles")
    func defaultOptions() {
        let o = UsageDisplayOptions.default
        #expect(!o.showModelScopedLimits && !o.showSonnetWeekly && !o.showExtraUsage)
        #expect(!o.useAPISeverity && !o.showSessionNotStarted && !o.showPlanLabel && !o.showFetchStatus)
    }

    @Test("default visibleWindows keeps session and week only")
    func defaultVisibleWindows() {
        let windows = [
            window(id: "five_hour"), window(id: "seven_day"),
            window(id: "seven_day_sonnet"), window(id: "weekly_scoped_fable"), window(id: "extra_usage"),
        ]
        #expect(UsageDisplayOptions.default.visibleWindows(from: record(windows: windows)).map(\.id)
            == ["five_hour", "seven_day"])
    }

    @Test("showSonnetWeekly includes sonnet window")
    func sonnetToggle() {
        var o = UsageDisplayOptions.default
        o.showSonnetWeekly = true
        let windows = [window(id: "five_hour"), window(id: "seven_day_sonnet")]
        #expect(o.visibleWindows(from: record(windows: windows)).map(\.id) == ["five_hour", "seven_day_sonnet"])
    }

    @Test("showModelScopedLimits includes weekly_scoped windows")
    func modelScopedToggle() {
        var o = UsageDisplayOptions.default
        o.showModelScopedLimits = true
        let windows = [window(id: "seven_day"), window(id: "weekly_scoped_fable"), window(id: "weekly_scoped_opus")]
        #expect(o.visibleWindows(from: record(windows: windows)).map(\.id)
            == ["seven_day", "weekly_scoped_fable", "weekly_scoped_opus"])
    }

    @Test("showExtraUsage includes extra_usage window")
    func extraUsageToggle() {
        var o = UsageDisplayOptions.default
        o.showExtraUsage = true
        let windows = [window(id: "five_hour"), window(id: "extra_usage")]
        #expect(o.visibleWindows(from: record(windows: windows)).map(\.id) == ["five_hour", "extra_usage"])
    }

    @Test("visibleWindows preserves mapper order")
    func preservesOrder() {
        var o = UsageDisplayOptions.default
        o.showSonnetWeekly = true
        o.showModelScopedLimits = true
        o.showExtraUsage = true
        let windows = [
            window(id: "five_hour"), window(id: "seven_day"), window(id: "seven_day_sonnet"),
            window(id: "weekly_scoped_fable"), window(id: "extra_usage"),
        ]
        #expect(o.visibleWindows(from: record(windows: windows)).map(\.id) == windows.map(\.id))
    }

    @Test("level ignores severity when useAPISeverity is false")
    func levelPercentOnly() {
        #expect(UsageDisplayOptions.default.level(for: window(id: "five_hour", usedPercent: 10, severity: "critical")) == .normal)
    }

    @Test("level prefers severity when useAPISeverity is true")
    func levelUsesSeverity() {
        var o = UsageDisplayOptions.default
        o.useAPISeverity = true
        #expect(o.level(for: window(id: "five_hour", usedPercent: 10, severity: "critical")) == .critical)
    }
}
