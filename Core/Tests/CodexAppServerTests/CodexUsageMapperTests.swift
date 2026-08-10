import Foundation
import Testing
import UsageCore
@testable import CodexAppServer

private func window(
    percent: Double,
    duration: Int?,
    reset: Double = 2_000
) -> CodexRateLimitWindow {
    CodexRateLimitWindow(
        usedPercent: percent,
        windowDurationMins: duration,
        resetsAt: reset
    )
}

private func result(
    primary: CodexRateLimitWindow?,
    secondary: CodexRateLimitWindow?,
    plan: String? = "plus",
    byID: [String: CodexRateLimitBucket]? = nil
) -> CodexRateLimitsReadResult {
    CodexRateLimitsReadResult(
        rateLimits: CodexRateLimitBucket(
            limitId: "codex",
            primary: primary,
            secondary: secondary,
            planType: plan
        ),
        rateLimitsByLimitId: byID
    )
}

@Suite("CodexUsageMapperTests")
struct CodexUsageMapperTests {
    @Test("maps duration rather than primary or secondary position")
    func mapsReversedWindows() throws {
        let mapped = try CodexUsageMapper.map(
            result(
                primary: window(percent: 55, duration: 10_080),
                secondary: window(percent: 12, duration: 300)
            ),
            observedAt: Date(timeIntervalSince1970: 1_000)
        )

        #expect(mapped.accountId == CodexAccount.id)
        #expect(mapped.source == "codex")
        #expect(mapped.origin == "poll")
        #expect(mapped.plan == "plus")
        #expect(mapped.windows.map(\.id) == ["five_hour", "seven_day"])
        #expect(mapped.windows.map(\.usedPercent) == [12, 55])
        #expect(mapped.fetchStatus?.state == .ok)
    }

    @Test("weekly-only primary slot is not mislabeled as a session")
    func weeklyOnlyPrimary() throws {
        let mapped = try CodexUsageMapper.map(
            result(primary: window(percent: 73, duration: 10_080), secondary: nil),
            observedAt: Date(timeIntervalSince1970: 1_000)
        )

        #expect(mapped.windows.map(\.id) == ["seven_day"])
        #expect(mapped.fetchStatus == FetchStatus(
            state: .failed,
            message: "Codex returned incomplete limits",
            updatedAt: Date(timeIntervalSince1970: 1_000)
        ))
    }

    @Test("prefers the codex limit id and preserves finite percentages")
    func prefersNamedBucketAndRawPercent() throws {
        let named = CodexRateLimitBucket(
            limitId: "codex",
            primary: window(percent: 150, duration: 300),
            secondary: window(percent: -2, duration: 10_080),
            planType: "team"
        )
        let unrelated = CodexRateLimitBucket(
            limitId: "spark",
            primary: window(percent: 99, duration: 300),
            secondary: nil,
            planType: nil
        )
        let mapped = try CodexUsageMapper.map(
            result(
                primary: window(percent: 1, duration: 300),
                secondary: nil,
                byID: ["spark": unrelated, "codex": named]
            ),
            observedAt: Date(timeIntervalSince1970: 1_000)
        )

        #expect(mapped.windows.map(\.usedPercent) == [150, -2])
        #expect(mapped.plan == "team")
    }

    @Test("drops malformed windows and rejects an empty mapping")
    func invalidValues() throws {
        let partial = try CodexUsageMapper.map(
            result(
                primary: window(percent: .infinity, duration: 300),
                secondary: window(percent: 40, duration: 10_080)
            ),
            observedAt: Date(timeIntervalSince1970: 1_000)
        )
        #expect(partial.windows.map(\.id) == ["seven_day"])
        #expect(partial.fetchStatus?.state == .failed)

        #expect(throws: CodexUsageMappingError.noValidWindows) {
            try CodexUsageMapper.map(
                result(
                    primary: window(percent: .nan, duration: 300),
                    secondary: window(percent: 1, duration: 60)
                ),
                observedAt: Date(timeIntervalSince1970: 1_000)
            )
        }
    }

    @Test("duplicate durations keep one window and report incompleteness")
    func duplicateDurations() throws {
        let mapped = try CodexUsageMapper.map(
            result(
                primary: window(percent: 10, duration: 300),
                secondary: window(percent: 20, duration: 300)
            ),
            observedAt: Date(timeIntervalSince1970: 1_000)
        )

        #expect(mapped.windows.map(\.id) == ["five_hour"])
        #expect(mapped.windows[0].usedPercent == 10)
        #expect(mapped.fetchStatus?.state == .failed)
    }

    @Test("decodes the documented rate-limit response shape")
    func decodesWireShape() throws {
        let data = Data(#"""
        {
          "rateLimits": null,
          "rateLimitsByLimitId": {
            "codex": {
              "limitId": "codex",
              "primary": {
                "usedPercent": 22.5,
                "windowDurationMins": 300,
                "resetsAt": 2000
              },
              "secondary": {
                "usedPercent": 64,
                "windowDurationMins": 10080,
                "resetsAt": 3000
              },
              "planType": "plus"
            }
          }
        }
        """#.utf8)

        let decoded = try JSONDecoder().decode(CodexRateLimitsReadResult.self, from: data)
        let mapped = try CodexUsageMapper.map(
            decoded,
            observedAt: Date(timeIntervalSince1970: 1_000)
        )

        #expect(mapped.windows.map(\.usedPercent) == [22.5, 64])
        #expect(mapped.windows.map(\.resetsAt) == [
            Date(timeIntervalSince1970: 2_000),
            Date(timeIntervalSince1970: 3_000),
        ])
    }

    @Test("a window with a missing percentage does not discard its valid sibling")
    func decodesPartialWireShape() throws {
        let data = Data(#"""
        {
          "rateLimits": {
            "limitId": "codex",
            "primary": {"windowDurationMins": 300, "resetsAt": 2000},
            "secondary": {
              "usedPercent": 64,
              "windowDurationMins": 10080,
              "resetsAt": 3000
            },
            "planType": "plus"
          },
          "rateLimitsByLimitId": null
        }
        """#.utf8)

        let decoded = try JSONDecoder().decode(CodexRateLimitsReadResult.self, from: data)
        let mapped = try CodexUsageMapper.map(
            decoded,
            observedAt: Date(timeIntervalSince1970: 1_000)
        )

        #expect(mapped.windows.map(\.id) == ["seven_day"])
        #expect(mapped.fetchStatus?.state == .failed)
    }
}
