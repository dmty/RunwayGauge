import AppIntents
import OSLog
import UsageCore
import WidgetKit

struct CycleAccountIntent: AppIntent {
    static let title: LocalizedStringResource = "Show Next Account"
    static let description = IntentDescription("Shows the next pinned usage account.")

    private static let logger = Logger(
        subsystem: "com.mirabilia.RunwayGauge",
        category: "CycleAccountIntent"
    )

    func perform() async throws -> some IntentResult {
        let url = AccountStore.url()
        do {
            try AccountStore.loadValidated(from: url)
        } catch AccountLoadError.missing {
            return .result()
        } catch {
            Self.logger.error("Account registry could not be read")
            return .result()
        }

        do {
            try AccountStore.mutate(at: url) { AccountSelection.cycleSelected(now: Date(), in: &$0) }
            WidgetCenter.shared.reloadTimelines(ofKind: "UsageWidget")
        } catch {
            Self.logger.error("Account registry mutation failed")
        }
        return .result()
    }
}
