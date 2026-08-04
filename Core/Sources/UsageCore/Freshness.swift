import Foundation

public enum Freshness: Sendable, Equatable {
    case fresh
    case stale(age: TimeInterval)

    public static let staleThreshold: TimeInterval = 600

    public static func evaluate(_ record: UsageRecord, now: Date) -> Freshness {
        let age = max(0, now.timeIntervalSince(record.updatedAt))

        // A window whose reset time has passed has rolled over, so its percentage is
        // wrong no matter how recently the file was written.
        let rolledOver = record.windows.contains { $0.resetsAt <= now }

        if rolledOver || age >= staleThreshold {
            return .stale(age: age)
        }
        return .fresh
    }
}
