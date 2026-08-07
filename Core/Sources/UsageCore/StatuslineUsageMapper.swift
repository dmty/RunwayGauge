import Foundation

/// Maps Claude Code statusline JSON (`rate_limits`) into a schema-2 `UsageRecord`.
public enum StatuslineUsageMapper {
    public enum Error: Swift.Error, Equatable {
        case malformed
    }

    public static func map(
        data: Data,
        accountId: String,
        observedAt: Date
    ) throws -> UsageRecord {
        guard let dto = try? JSONDecoder().decode(StatuslineBody.self, from: data) else {
            throw Error.malformed
        }

        var windows: [UsageWindow] = []

        if let five = dto.rateLimits?.fiveHour,
           let usedPercent = five.usedPercentage,
           let resetsAt = five.resetsAt {
            windows.append(
                UsageWindow(
                    id: "five_hour",
                    label: "Session",
                    usedPercent: usedPercent,
                    resetsAt: Date(timeIntervalSince1970: resetsAt)
                )
            )
        }

        if let seven = dto.rateLimits?.sevenDay,
           let usedPercent = seven.usedPercentage,
           let resetsAt = seven.resetsAt {
            windows.append(
                UsageWindow(
                    id: "seven_day",
                    label: "Week",
                    usedPercent: usedPercent,
                    resetsAt: Date(timeIntervalSince1970: resetsAt)
                )
            )
        }

        return UsageRecord(
            accountId: accountId,
            source: "claude-code",
            updatedAt: observedAt,
            origin: "statusline",
            windows: windows
        )
    }
}

private struct StatuslineBody: Decodable {
    let rateLimits: RateLimitsDTO?

    enum CodingKeys: String, CodingKey {
        case rateLimits = "rate_limits"
    }
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
