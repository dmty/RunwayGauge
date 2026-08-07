import Foundation

public enum PollPolicy {
    public static let maxAge: TimeInterval = 600
    public static let defaultCooldown: TimeInterval = 300
    public static let writeMinInterval: TimeInterval = 30

    /// Primary windows owned by the statusline payload. Omitted keys are dropped
    /// (not backfilled from a prior OAuth poll).
    public static let primaryWindowIDs: Set<String> = ["five_hour", "seven_day"]

    public static func shouldFetch(
        force: Bool,
        fileModificationDate: Date?,
        fetchStatus: FetchStatus?,
        now: Date = Date()
    ) -> Bool {
        if force { return true }

        if let status = fetchStatus, status.state == .rateLimited,
           let until = status.retryAfterAt {
            // Still cooling down → skip. Cooldown expired → fetch even if mtime is fresh.
            return now >= until
        }

        if let mtime = fileModificationDate, now.timeIntervalSince(mtime) < maxAge {
            return false
        }
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
        // Keep last-good windows + updatedAt so Freshness stays stale; attempt time
        // lives on fetchStatus.updatedAt only.
        return UsageRecord(
            accountId: accountId,
            source: existing?.source ?? "claude-code",
            updatedAt: existing?.updatedAt ?? observedAt,
            origin: existing?.origin ?? "poll",
            windows: existing?.windows ?? [],
            plan: existing?.plan,
            fetchStatus: fetchStatus
        )
    }

    /// Merge statusline windows into an existing poll record.
    /// Returns `nil` when the statusline mapped zero windows (soft-skip).
    public static func prepareStatuslineRecord(
        mapped: UsageRecord,
        existing: UsageRecord?,
        now: Date = Date()
    ) -> UsageRecord? {
        guard !mapped.windows.isEmpty else { return nil }

        return UsageRecord(
            accountId: mapped.accountId,
            source: mapped.source,
            updatedAt: mapped.updatedAt,
            origin: mapped.origin,
            windows: mergeWindows(
                statusline: mapped.windows,
                existing: existing?.windows ?? [],
                now: now
            ),
            plan: mapped.plan ?? existing?.plan,
            fetchStatus: existing?.fetchStatus.map { _ in
                FetchStatus(state: .ok, updatedAt: mapped.updatedAt)
            }
        )
    }

    /// - Primary ids (`five_hour` / `seven_day`): statusline values only (omitted → dropped).
    /// - OAuth-only ids: retained only when `resetsAt > now`.
    public static func mergeWindows(
        statusline: [UsageWindow],
        existing: [UsageWindow],
        now: Date = Date()
    ) -> [UsageWindow] {
        var result: [UsageWindow] = []
        var seen = Set<String>()
        for window in statusline {
            result.append(window)
            seen.insert(window.id)
        }
        for window in existing {
            guard !seen.contains(window.id) else { continue }
            guard !primaryWindowIDs.contains(window.id) else { continue }
            guard window.resetsAt > now else { continue }
            result.append(window)
        }
        return result
    }
}
