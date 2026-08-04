import Foundation
import Testing
@testable import UsageCore

private let tz = TimeZone(identifier: "Pacific/Auckland")!
private let fmt = UsageFormatter(timeZone: tz)

private extension ISO8601DateFormatter {
    static func fixed(_ s: String) -> Date {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f.date(from: s)!
    }
}

private func fixedDate(_ iso: String) -> Date { ISO8601DateFormatter.fixed(iso) }

/// 2026-08-04 14:00 NZST
private let now = fixedDate("2026-08-04T14:00:00+12:00")

@Test("same calendar day shows time only")
func sameDay() {
    let reset = fixedDate("2026-08-04T18:19:00+12:00")
    #expect(fmt.resetDescription(reset, now: now, style: .short) == "6:19pm")
}

@Test("same day near midnight is still same-day")
func sameDayLate() {
    let reset = fixedDate("2026-08-04T23:58:00+12:00")
    #expect(fmt.resetDescription(reset, now: now, style: .short) == "11:58pm")
}

@Test("tomorrow shows weekday and time")
func withinWeek() {
    let reset = fixedDate("2026-08-08T06:59:00+12:00")
    #expect(fmt.resetDescription(reset, now: now, style: .short) == "Sat 6:59am")
}

@Test("just past midnight tomorrow is a weekday, not a time-only string")
func justAfterMidnight() {
    let reset = fixedDate("2026-08-05T00:30:00+12:00")
    #expect(fmt.resetDescription(reset, now: now, style: .short) == "Wed 12:30am")
}

@Test("beyond a week shows date and time")
func beyondWeek() {
    let reset = fixedDate("2026-08-20T06:59:00+12:00")
    #expect(fmt.resetDescription(reset, now: now, style: .short) == "Aug 20, 6:59am")
}

@Test("long style appends the timezone identifier")
func longStyle() {
    let reset = fixedDate("2026-08-04T18:19:00+12:00")
    #expect(fmt.resetDescription(reset, now: now, style: .long) == "6:19pm (Pacific/Auckland)")
}

@Test("age strings", arguments: [
    (0.0, "just now"),
    (59.0, "just now"),
    (60.0, "1m ago"),
    (720.0, "12m ago"),
    (3599.0, "59m ago"),
    (3600.0, "1h ago"),
    (10800.0, "3h ago"),
    (172_799.0, "47h ago"),
    (172_800.0, "2d ago"),
    (864_000.0, "10d ago"),
])
func ages(seconds: Double, expected: String) {
    #expect(fmt.ageDescription(seconds) == expected)
}
