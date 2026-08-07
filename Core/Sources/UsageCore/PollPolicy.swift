import Foundation

public enum PollPolicy {
    public static let maxAge: TimeInterval = 600
    public static let defaultCooldown: TimeInterval = 300
    public static let writeMinInterval: TimeInterval = 30

    public static func shouldFetch(
        force: Bool,
        fileModificationDate: Date?,
        fetchStatus: FetchStatus?,
        now: Date = Date()
    ) -> Bool {
        guard !force else { return true }
        if let status = fetchStatus, status.state == .rateLimited,
           let until = status.retryAfterAt, now < until { return false }
        if let mtime = fileModificationDate, now.timeIntervalSince(mtime) < maxAge { return false }
        return true
    }

    public static func makePollRecord(
        accountId: String,
        status: Int,
        body: Data,
        retryAfter: TimeInterval?,
        existing: UsageRecord?,
        observedAt: Date = Date()
    ) -> UsageRecord? {
        if status == 200 {
            guard let mapped = try? OAuthUsageMapper.map(
                data: body, accountId: accountId, observedAt: observedAt, origin: "poll"
            ), !mapped.windows.isEmpty else { return nil }
            return UsageRecord(
                accountId: mapped.accountId,
                source: mapped.source,
                updatedAt: mapped.updatedAt,
                origin: mapped.origin,
                windows: mapped.windows,
                plan: mapped.plan ?? existing?.plan,
                fetchStatus: FetchStatus(state: .ok, httpStatus: 200, updatedAt: observedAt)
            )
        }

        let fetchStatus: FetchStatus
        if status == 429 {
            fetchStatus = FetchStatus(
                state: .rateLimited,
                message: "rate limited",
                retryAfterAt: observedAt.addingTimeInterval(retryAfter ?? defaultCooldown),
                httpStatus: 429,
                updatedAt: observedAt
            )
        } else {
            fetchStatus = FetchStatus(
                state: .failed,
                message: "fetch failed",
                httpStatus: status,
                updatedAt: observedAt
            )
        }
        return UsageRecord(
            accountId: accountId,
            source: existing?.source ?? "claude-code",
            updatedAt: observedAt,
            origin: "poll",
            windows: existing?.windows ?? [],
            plan: existing?.plan,
            fetchStatus: fetchStatus
        )
    }

    public static func prepareStatuslineRecord(
        mapped: UsageRecord,
        existing: UsageRecord?
    ) -> UsageRecord {
        UsageRecord(
            accountId: mapped.accountId,
            source: mapped.source,
            updatedAt: mapped.updatedAt,
            origin: mapped.origin,
            windows: mapped.windows,
            plan: mapped.plan ?? existing?.plan,
            fetchStatus: existing?.fetchStatus.map { _ in
                FetchStatus(state: .ok, updatedAt: mapped.updatedAt)
            }
        )
    }
}
