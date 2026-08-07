import Foundation

/// Maps Anthropic OAuth usage JSON into schema-2 `UsageRecord` windows.
public enum OAuthUsageMapper {
    public enum Error: Swift.Error, Equatable { case malformed }

    /// ponytail: sentinel when extra_usage has no resets_at
    public static let extraUsageResetSentinelDays: TimeInterval = 32 * 24 * 60 * 60

    public static func map(
        data: Data,
        accountId: String,
        observedAt: Date,
        origin: String
    ) throws -> UsageRecord {
        guard let dto = try? JSONDecoder().decode(OAuthBody.self, from: data) else {
            throw Error.malformed
        }

        var windows: [UsageWindow] = []
        for (src, id, label) in [
            (dto.fiveHour, "five_hour", "Session"),
            (dto.sevenDay, "seven_day", "Week"),
            (dto.sevenDaySonnet, "seven_day_sonnet", "Sonnet"),
        ] {
            if let w = timeWindow(src, id: id, label: label) { windows.append(w) }
        }

        for limit in dto.limits ?? [] where limit.kind == "weekly_scoped" {
            guard let percent = limit.percent,
                  let resetsAt = limit.resetsAt.flatMap(parseISO8601),
                  let name = limit.scope?.model?.displayName?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !name.isEmpty
            else { continue }
            windows.append(UsageWindow(
                id: "weekly_scoped_\(sanitize(name))",
                label: name,
                usedPercent: percent,
                resetsAt: resetsAt,
                severity: limit.severity,
                kind: limit.kind
            ))
        }

        if let extra = dto.extraUsage, extra.isEnabled == true,
           let usedPercent = extra.utilization
               ?? extra.usedCredits.flatMap({ u in extra.monthlyLimit.flatMap { l in l > 0 ? (u / l) * 100 : nil } }) {
            let resetsAt = extra.resetsAt.flatMap(parseISO8601)
                ?? observedAt.addingTimeInterval(extraUsageResetSentinelDays)
            windows.append(UsageWindow(
                id: "extra_usage",
                label: "Extra usage",
                usedPercent: usedPercent,
                resetsAt: resetsAt,
                severity: nil,
                kind: "extra_usage"
            ))
        }

        return UsageRecord(
            accountId: accountId,
            source: "claude-code",
            updatedAt: observedAt,
            origin: origin,
            windows: windows
        )
    }

    private static func timeWindow(_ value: TimeWindowDTO?, id: String, label: String) -> UsageWindow? {
        guard let value,
              let usedPercent = value.utilization,
              let resetsAt = value.resetsAt.flatMap(parseISO8601)
        else { return nil }
        return UsageWindow(id: id, label: label, usedPercent: usedPercent, resetsAt: resetsAt)
    }

    private static func sanitize(_ displayName: String) -> String {
        let slug = displayName.lowercased()
            .map { $0.isLetter || $0.isNumber ? String($0) : "_" }
            .joined()
            .split(separator: "_", omittingEmptySubsequences: true)
            .joined(separator: "_")
        return slug.isEmpty ? "unknown" : slug
    }

    private static func parseISO8601(_ raw: String) -> Date? {
        for options: ISO8601DateFormatter.Options in [
            [.withInternetDateTime, .withFractionalSeconds],
            [.withInternetDateTime],
        ] {
            let f = ISO8601DateFormatter()
            f.formatOptions = options
            if let d = f.date(from: raw) { return d }
        }
        var s = raw.replacingOccurrences(of: #"\.\d+"#, with: "", options: .regularExpression)
        if s.hasSuffix("+00:00") { s = String(s.dropLast(6)) + "Z" }
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f.date(from: s)
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
    let scope: Scope?

    struct Scope: Decodable {
        let model: Model?
        struct Model: Decodable {
            let displayName: String?
            enum CodingKeys: String, CodingKey { case displayName = "display_name" }
        }
    }

    enum CodingKeys: String, CodingKey {
        case kind, percent, severity
        case resetsAt = "resets_at"
        case scope
    }
}
