import Foundation

public enum Freshness: Sendable, Equatable {
    case fresh
    case stale(age: TimeInterval)

    public static let staleThreshold: TimeInterval = 600

    public static func evaluate(
        _ record: UsageRecord,
        now: Date,
        windows: [UsageWindow]? = nil
    ) -> Freshness {
        let age = max(0, now.timeIntervalSince(record.updatedAt))
        // ponytail: rolled-over visible windows force stale even when updatedAt is fresh
        let rolledOver = (windows ?? record.windows).contains { $0.resetsAt <= now }
        return rolledOver || age >= staleThreshold ? .stale(age: age) : .fresh
    }
}
