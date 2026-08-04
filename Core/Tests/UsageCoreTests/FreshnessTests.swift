import Foundation
import Testing
@testable import UsageCore

private let now = Date(timeIntervalSince1970: 1_800_000_000)

private func record(updatedAgo: TimeInterval, resetsIn: [TimeInterval] = []) -> UsageRecord {
    UsageRecord(
        source: "claude-code",
        updatedAt: now.addingTimeInterval(-updatedAgo),
        origin: "statusline",
        windows: resetsIn.enumerated().map { i, offset in
            UsageWindow(id: "w\(i)", label: "W\(i)", usedPercent: 10, resetsAt: now.addingTimeInterval(offset))
        }
    )
}

private func freshness(updatedAgo: TimeInterval, resetsIn: [TimeInterval] = []) -> Freshness {
    Freshness.evaluate(record(updatedAgo: updatedAgo, resetsIn: resetsIn), now: now)
}

@Test("recent data with future resets is fresh")
func freshCase() {
    #expect(freshness(updatedAgo: 60, resetsIn: [3600, 86400]) == .fresh)
}

@Test("age threshold boundaries", arguments: [
    (599.0, Freshness.fresh),
    (600.0, Freshness.stale(age: 600)),
])
func ageThresholds(updatedAgo: TimeInterval, expected: Freshness) {
    #expect(freshness(updatedAgo: updatedAgo, resetsIn: [3600]) == expected)
}

@Test("a rolled-over window forces stale even when updatedAt is seconds old")
func rolledOverForcesStale() {
    #expect(freshness(updatedAgo: 5, resetsIn: [-1]) == .stale(age: 5))
}

@Test("a rolled-over window forces stale even if another window is still in the future")
func oneRolledOverIsEnough() {
    #expect(freshness(updatedAgo: 5, resetsIn: [3600, -30]) == .stale(age: 5))
}

@Test("a record with no windows relies on updatedAt alone")
func noWindows() {
    #expect(freshness(updatedAgo: 5) == .fresh)
    #expect(freshness(updatedAgo: 900) == .stale(age: 900))
}

@Test("a future updatedAt from clock skew clamps age to zero instead of going negative")
func clockSkew() {
    #expect(freshness(updatedAgo: -120, resetsIn: [-5]) == .stale(age: 0))
}
