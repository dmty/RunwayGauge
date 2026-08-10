import UsageCore

enum UsageGaugePolicy {
    static func showsSessionNotStarted(
        sourceKind: SourceKind,
        window: UsageWindow,
        options: UsageDisplayOptions
    ) -> Bool {
        SourceCatalog.presentation(for: sourceKind).supportsSessionNotStarted
            && options.showSessionNotStarted
            && window.id == "five_hour"
            && window.usedPercent <= 0
    }
}
