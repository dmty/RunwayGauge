import Foundation

/// Skip / cooldown rules for `poll`, plus HTTP outcome → record mapping (no network).
public enum PollPolicy {
    public static let maxAge: TimeInterval = 600
    public static let defaultCooldown: TimeInterval = 300
    public static let writeMinInterval: TimeInterval = 30

    /// Whether a live GET should run for this account.
    ///
    /// Skip when `!force` and either still inside a rate-limit cooldown, or the
    /// usage file is fresher than `maxAge`.
    public static func shouldFetch(
        force: Bool,
        fileModificationDate: Date?,
        fetchStatus: FetchStatus?,
        now: Date = Date()
    ) -> Bool {
        if force { return true }

        if let status = fetchStatus,
           status.state == .rateLimited,
           let retryAfterAt = status.retryAfterAt,
           now < retryAfterAt {
            return false
        }

        if let mtime = fileModificationDate,
           now.timeIntervalSince(mtime) < maxAge {
            return false
        }

        return true
    }

    /// Build the record to commit for a poll HTTP response. Returns `nil` when
    /// a 200 body cannot be mapped to usable windows (soft skip).
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
                data: body,
                accountId: accountId,
                observedAt: observedAt,
                origin: "poll"
            ), !mapped.windows.isEmpty else {
                return nil
            }
            return UsageRecord(
                accountId: mapped.accountId,
                source: mapped.source,
                updatedAt: mapped.updatedAt,
                origin: mapped.origin,
                windows: mapped.windows,
                plan: mapped.plan ?? existing?.plan,
                fetchStatus: FetchStatus(
                    state: .ok,
                    message: nil,
                    retryAfterAt: nil,
                    httpStatus: 200,
                    updatedAt: observedAt
                )
            )
        }

        let windows = existing?.windows ?? []
        let plan = existing?.plan

        if status == 429 {
            let cooldown = retryAfter ?? defaultCooldown
            return UsageRecord(
                accountId: accountId,
                source: existing?.source ?? "claude-code",
                updatedAt: observedAt,
                origin: "poll",
                windows: windows,
                plan: plan,
                fetchStatus: FetchStatus(
                    state: .rateLimited,
                    message: "rate limited",
                    retryAfterAt: observedAt.addingTimeInterval(cooldown),
                    httpStatus: 429,
                    updatedAt: observedAt
                )
            )
        }

        return UsageRecord(
            accountId: accountId,
            source: existing?.source ?? "claude-code",
            updatedAt: observedAt,
            origin: "poll",
            windows: windows,
            plan: plan,
            fetchStatus: FetchStatus(
                state: .failed,
                message: "fetch failed",
                retryAfterAt: nil,
                httpStatus: status,
                updatedAt: observedAt
            )
        )
    }

    /// Statusline write clears a prior failed/rateLimited (or any) fetch status.
    public static func prepareStatuslineRecord(
        mapped: UsageRecord,
        existing: UsageRecord?
    ) -> UsageRecord {
        let fetchStatus: FetchStatus? = existing?.fetchStatus == nil
            ? nil
            : FetchStatus(state: .ok, updatedAt: mapped.updatedAt)

        return UsageRecord(
            accountId: mapped.accountId,
            source: mapped.source,
            updatedAt: mapped.updatedAt,
            origin: mapped.origin,
            windows: mapped.windows,
            plan: mapped.plan ?? existing?.plan,
            fetchStatus: fetchStatus
        )
    }
}
