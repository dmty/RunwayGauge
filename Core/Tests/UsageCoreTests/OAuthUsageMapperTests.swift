import Foundation
import Testing
@testable import UsageCore

private func fixtureURL(_ name: String) throws -> URL {
    var dir = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
    while dir.path != "/" {
        let candidate = dir.appendingPathComponent("tests/fixtures/\(name)")
        if FileManager.default.fileExists(atPath: candidate.path) {
            return candidate
        }
        dir.deleteLastPathComponent()
    }
    Issue.record("Fixture not found: \(name)")
    throw CocoaError(.fileNoSuchFile)
}

@Test func mapsFixtureSessionWeekFableAndExtraDisabled() throws {
    let data = try Data(contentsOf: fixtureURL("oauth-usage-response.json"))
    let observedAt = Date(timeIntervalSince1970: 1_700_000_000)
    let record = try OAuthUsageMapper.map(
        data: data,
        accountId: "acc_test",
        observedAt: observedAt,
        origin: "poll"
    )

    #expect(record.accountId == "acc_test")
    #expect(record.source == "claude-code")
    #expect(record.origin == "poll")
    #expect(record.updatedAt == observedAt)

    let ids = Set(record.windows.map(\.id))
    #expect(ids.contains("five_hour"))
    #expect(ids.contains("seven_day"))
    #expect(ids.contains { $0.hasPrefix("weekly_scoped_") })
    #expect(!ids.contains("extra_usage"))

    let session = record.windows.first { $0.id == "five_hour" }
    #expect(session?.label == "Session")
    #expect(session?.usedPercent == 38)

    let week = record.windows.first { $0.id == "seven_day" }
    #expect(week?.label == "Week")
    #expect(week?.usedPercent == 76)

    let fable = record.windows.first { $0.label == "Fable" }
    #expect(fable?.id == "weekly_scoped_fable")
    #expect(fable?.usedPercent == 100)
    #expect(fable?.severity == "critical")
    #expect(fable?.kind == "weekly_scoped")
}

@Test func mapsEnabledExtraUsageWithSentinelReset() throws {
    let json = """
    {
      "five_hour": null,
      "seven_day": null,
      "seven_day_sonnet": null,
      "extra_usage": {
        "is_enabled": true,
        "utilization": 42.5,
        "used_credits": 100,
        "monthly_limit": 200
      },
      "limits": []
    }
    """.data(using: .utf8)!
    let observedAt = Date(timeIntervalSince1970: 1_700_000_000)
    let record = try OAuthUsageMapper.map(
        data: json,
        accountId: "acc_extra",
        observedAt: observedAt,
        origin: "poll"
    )
    let extra = record.windows.first { $0.id == "extra_usage" }
    #expect(extra?.label == "Extra usage")
    #expect(extra?.usedPercent == 42.5)
    #expect(extra?.severity == nil)
    #expect(extra?.resetsAt == observedAt.addingTimeInterval(32 * 24 * 60 * 60))
}

@Test func mapsSevenDaySonnetWhenPresent() throws {
    let json = """
    {
      "five_hour": null,
      "seven_day": null,
      "seven_day_sonnet": {
        "utilization": 12,
        "resets_at": "2026-08-10T00:00:00+00:00"
      },
      "extra_usage": { "is_enabled": false },
      "limits": []
    }
    """.data(using: .utf8)!
    let record = try OAuthUsageMapper.map(
        data: json,
        accountId: "acc_sonnet",
        observedAt: Date(timeIntervalSince1970: 1_700_000_000),
        origin: "poll"
    )
    let sonnet = record.windows.first { $0.id == "seven_day_sonnet" }
    #expect(sonnet?.label == "Sonnet")
    #expect(sonnet?.usedPercent == 12)
}

@Test func mapsStatuslineBothFixture() throws {
    let data = try Data(contentsOf: fixtureURL("statusline-both.json"))
    let observedAt = Date(timeIntervalSince1970: 1_700_000_000)
    let record = try StatuslineUsageMapper.map(
        data: data,
        accountId: "acc_sl",
        observedAt: observedAt
    )

    #expect(record.accountId == "acc_sl")
    #expect(record.source == "claude-code")
    #expect(record.origin == "statusline")
    #expect(record.updatedAt == observedAt)
    #expect(record.windows.count == 2)

    let session = record.windows.first { $0.id == "five_hour" }
    #expect(session?.label == "Session")
    #expect(session?.usedPercent == 19.4)
    #expect(session?.resetsAt == Date(timeIntervalSince1970: 1_785_823_140))

    let week = record.windows.first { $0.id == "seven_day" }
    #expect(week?.label == "Week")
    #expect(week?.usedPercent == 73.2)
    #expect(week?.resetsAt == Date(timeIntervalSince1970: 1_786_143_540))
}
