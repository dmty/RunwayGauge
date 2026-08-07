import Foundation

/// Maps Claude Code statusline JSON (`rate_limits`) into a schema-2 `UsageRecord`.
public enum StatuslineUsageMapper {
    public enum Error: Swift.Error, Equatable { case malformed }

    public static func map(
        data: Data,
        accountId: String,
        observedAt: Date
    ) throws -> UsageRecord {
        guard let dto = try? JSONDecoder().decode(StatuslineBody.self, from: data) else {
            throw Error.malformed
        }

        var windows: [UsageWindow] = []
        for (src, id, label) in [
            (dto.rateLimits?.fiveHour, "five_hour", "Session"),
            (dto.rateLimits?.sevenDay, "seven_day", "Week"),
        ] {
            if let w = unixWindow(src, id: id, label: label) { windows.append(w) }
        }

        return UsageRecord(
            accountId: accountId,
            source: "claude-code",
            updatedAt: observedAt,
            origin: "statusline",
            windows: windows
        )
    }

    private static func unixWindow(_ dto: RateLimitWindowDTO?, id: String, label: String) -> UsageWindow? {
        guard let dto, let pct = dto.usedPercentage, let ts = dto.resetsAt else { return nil }
        return UsageWindow(id: id, label: label, usedPercent: pct, resetsAt: Date(timeIntervalSince1970: ts))
    }
}

private struct StatuslineBody: Decodable {
    let rateLimits: RateLimitsDTO?
    enum CodingKeys: String, CodingKey { case rateLimits = "rate_limits" }
}

private struct RateLimitsDTO: Decodable {
    let fiveHour: RateLimitWindowDTO?
    let sevenDay: RateLimitWindowDTO?
    enum CodingKeys: String, CodingKey {
        case fiveHour = "five_hour"
        case sevenDay = "seven_day"
    }
}

private struct RateLimitWindowDTO: Decodable {
    let usedPercentage: Double?
    let resetsAt: Double?
    enum CodingKeys: String, CodingKey {
        case usedPercentage = "used_percentage"
        case resetsAt = "resets_at"
    }
}
