import AppIntents
import AppKit

struct OpenSettingsIntent: AppIntent {
    static let title: LocalizedStringResource = "Open RunwayGauge Settings"
    static let description = IntentDescription("Opens the RunwayGauge Settings window.")
    static var openAppWhenRun: Bool { true }

    @MainActor
    func perform() async throws -> some IntentResult {
        NSApp.activate(ignoringOtherApps: true)
        NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
        return .result()
    }
}
