import Foundation
import UsageCore

public enum CodexUsageMappingError: Error, Equatable, Sendable {
    case missingCodexBucket
    case noValidWindows
}

public enum CodexUsageMapper {
    public static func mainBucket(
        in response: CodexRateLimitsReadResult
    ) -> CodexRateLimitBucket? {
        response.rateLimitsByLimitId?["codex"] ?? response.rateLimits
    }

    public static func map(
        _ response: CodexRateLimitsReadResult,
        accountId: String = CodexAccount.id,
        observedAt: Date = Date()
    ) throws -> UsageRecord {
        guard let bucket = mainBucket(in: response) else {
            throw CodexUsageMappingError.missingCodexBucket
        }

        var byID: [String: UsageWindow] = [:]
        for candidate in [bucket.primary, bucket.secondary].compactMap({ $0 }) {
            guard let usedPercent = candidate.usedPercent,
                  usedPercent.isFinite,
                  let duration = candidate.windowDurationMins,
                  let reset = candidate.resetsAt,
                  reset.isFinite,
                  reset > 0
            else { continue }

            let identity: (id: String, label: String)? = switch duration {
            case 300: ("five_hour", "Current session")
            case 10_080: ("seven_day", "Current week (all models)")
            default: nil
            }
            guard let identity, byID[identity.id] == nil else { continue }
            byID[identity.id] = UsageWindow(
                id: identity.id,
                label: identity.label,
                usedPercent: usedPercent,
                resetsAt: Date(timeIntervalSince1970: reset)
            )
        }

        let windows = ["five_hour", "seven_day"].compactMap { byID[$0] }
        guard !windows.isEmpty else {
            throw CodexUsageMappingError.noValidWindows
        }
        let complete = windows.count == 2
        return UsageRecord(
            accountId: accountId,
            source: "codex",
            updatedAt: observedAt,
            origin: "poll",
            windows: windows,
            plan: bucket.planType,
            fetchStatus: FetchStatus(
                state: complete ? .ok : .failed,
                message: complete ? nil : "Codex returned incomplete limits",
                updatedAt: observedAt
            )
        )
    }
}
