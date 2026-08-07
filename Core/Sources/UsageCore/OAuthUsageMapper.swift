import Foundation

/// Maps Anthropic OAuth usage JSON into schema-2 `UsageRecord` windows.
public enum OAuthUsageMapper {
    public enum Error: Swift.Error, Equatable {
        case malformed
    }

    /// When `extra_usage` is enabled but has no `resets_at`, use `observedAt + 32 days`
    /// as a sentinel so `UsageWindow.resetsAt` stays required.
    public static let extraUsageResetSentinelDays: TimeInterval = 32 * 24 * 60 * 60

    public static func map(
        data: Data,
        accountId: String,
        observedAt: Date,
        origin: String
    ) throws -> UsageRecord {
        let decoder = JSONDecoder()
        guard let dto = try? decoder.decode(OAuthBody.self, from: data) else {
            throw Error.malformed
        }

        var windows: [UsageWindow] = []

        if let window = timeWindow(dto.fiveHour, id: "five_hour", label: "Session") {
            windows.append(window)
        }
        if let window = timeWindow(dto.sevenDay, id: "seven_day", label: "Week") {
            windows.append(window)
        }
        if let window = timeWindow(dto.sevenDaySonnet, id: "seven_day_sonnet", label: "Sonnet") {
            windows.append(window)
        }

        for limit in dto.limits ?? [] where limit.kind == "weekly_scoped" {
            guard let percent = limit.percent,
                  let resetsRaw = limit.resetsAt,
                  let resetsAt = parseISO8601(resetsRaw)
            else { continue }
            let displayName = limit.scope?.model?.displayName?.trimmingCharacters(in: .whitespacesAndNewlines)
            guard let displayName, !displayName.isEmpty else { continue }
            windows.append(
                UsageWindow(
                    id: "weekly_scoped_\(sanitize(displayName))",
                    label: displayName,
                    usedPercent: percent,
                    resetsAt: resetsAt,
                    severity: limit.severity,
                    kind: limit.kind
                )
            )
        }

        if let extra = dto.extraUsage, extra.isEnabled == true {
            let usedPercent: Double?
            if let utilization = extra.utilization {
                usedPercent = utilization
            } else if let used = extra.usedCredits, let limit = extra.monthlyLimit, limit > 0 {
                usedPercent = (used / limit) * 100
            } else {
                usedPercent = nil
            }

            if let usedPercent {
                let resetsAt: Date
                if let raw = extra.resetsAt, let parsed = parseISO8601(raw) {
                    resetsAt = parsed
                } else {
                    // Sentinel: extra_usage often has no resets_at; keep UsageWindow.resetsAt required.
                    resetsAt = observedAt.addingTimeInterval(extraUsageResetSentinelDays)
                }
                windows.append(
                    UsageWindow(
                        id: "extra_usage",
                        label: "Extra usage",
                        usedPercent: usedPercent,
                        resetsAt: resetsAt,
                        severity: nil,
                        kind: "extra_usage"
                    )
                )
            }
        }

        return UsageRecord(
            accountId: accountId,
            source: "claude-code",
            updatedAt: observedAt,
            origin: origin,
            windows: windows
        )
    }

    private static func timeWindow(
        _ value: TimeWindowDTO?,
        id: String,
        label: String
    ) -> UsageWindow? {
        guard let value else { return nil }
        guard let usedPercent = value.utilization,
              let resetsRaw = value.resetsAt,
              let resetsAt = parseISO8601(resetsRaw)
        else { return nil }
        return UsageWindow(
            id: id,
            label: label,
            usedPercent: usedPercent,
            resetsAt: resetsAt
        )
    }

    private static func sanitize(_ displayName: String) -> String {
        let lowered = displayName.lowercased()
        let mapped = lowered.map { ch -> Character in
            ch.isLetter || ch.isNumber ? ch : "_"
        }
        let collapsed = String(mapped)
            .split(separator: "_", omittingEmptySubsequences: true)
            .joined(separator: "_")
        return collapsed.isEmpty ? "unknown" : collapsed
    }

    private static func parseISO8601(_ raw: String) -> Date? {
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = fractional.date(from: raw) { return date }

        let basic = ISO8601DateFormatter()
        basic.formatOptions = [.withInternetDateTime]
        if let date = basic.date(from: raw) { return date }

        // Fixture-style "+00:00" without converting fractional seconds via formatter options alone.
        var normalized = raw
        if let range = normalized.range(of: #"\.\d+"#, options: .regularExpression) {
            normalized.removeSubrange(range)
        }
        if normalized.hasSuffix("+00:00") {
            normalized = String(normalized.dropLast(6)) + "Z"
        }
        return basic.date(from: normalized)
    }
}

private struct OAuthBody: Decodable {
    let fiveHour: TimeWindowDTO?
    let sevenDay: TimeWindowDTO?
    let sevenDaySonnet: TimeWindowDTO?
    let extraUsage: ExtraUsageDTO?
    let limits: [LimitDTO]?

    enum CodingKeys: String, CodingKey {
        case fiveHour = "five_hour"
        case sevenDay = "seven_day"
        case sevenDaySonnet = "seven_day_sonnet"
        case extraUsage = "extra_usage"
        case limits
    }
}

private struct TimeWindowDTO: Decodable {
    let utilization: Double?
    let resetsAt: String?

    enum CodingKeys: String, CodingKey {
        case utilization
        case resetsAt = "resets_at"
    }
}

private struct ExtraUsageDTO: Decodable {
    let isEnabled: Bool?
    let utilization: Double?
    let usedCredits: Double?
    let monthlyLimit: Double?
    let resetsAt: String?

    enum CodingKeys: String, CodingKey {
        case isEnabled = "is_enabled"
        case utilization
        case usedCredits = "used_credits"
        case monthlyLimit = "monthly_limit"
        case resetsAt = "resets_at"
    }
}

private struct LimitDTO: Decodable {
    let kind: String?
    let percent: Double?
    let severity: String?
    let resetsAt: String?
    let scope: ScopeDTO?

    enum CodingKeys: String, CodingKey {
        case kind
        case percent
        case severity
        case resetsAt = "resets_at"
        case scope
    }
}

private struct ScopeDTO: Decodable {
    let model: ModelDTO?
}

private struct ModelDTO: Decodable {
    let displayName: String?

    enum CodingKeys: String, CodingKey {
        case displayName = "display_name"
    }
}
