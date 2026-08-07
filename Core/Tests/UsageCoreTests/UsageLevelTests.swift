import Testing
@testable import UsageCore

@Test("levels map at documented boundaries", arguments: [
    (0.0, UsageLevel.normal),
    (19.0, UsageLevel.normal),
    (79.99, UsageLevel.normal),
    (80.0, UsageLevel.warning),
    (94.99, UsageLevel.warning),
    (95.0, UsageLevel.critical),
    (100.0, UsageLevel.critical),
    (140.0, UsageLevel.critical),
])
func levelBoundaries(percent: Double, expected: UsageLevel) {
    #expect(UsageLevel(usedPercent: percent) == expected)
}

@Test("negative percent is treated as normal, not critical")
func negativePercent() {
    #expect(UsageLevel(usedPercent: -5) == .normal)
}

@Test func levelPrefersSeverityWhenProvided() {
    #expect(UsageLevel(usedPercent: 10, severity: "critical") == .critical)
    #expect(UsageLevel(usedPercent: 99, severity: "normal") == .normal)
    #expect(UsageLevel(usedPercent: 90, severity: nil) == .warning)
}
