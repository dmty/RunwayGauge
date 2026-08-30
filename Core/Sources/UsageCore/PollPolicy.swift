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
        origin: String? = nil,
        windows: [UsageWindow] = [],
        now: Date = Date()
    ) -> Bool {
        if force { return true }

        if let status = fetchStatus, status.state == .rateLimited,
           let until = status.retryAfterAt {
            // Still cooling down → skip. Cooldown expired → fetch even if mtime is fresh.
            return now >= until
        }

        // A rolled-over window is already wrong; don't wait out maxAge.
        if windows.contains(where: { $0.resetsAt <= now }) {
            return true
        }

        // Prefer last OAuth/poll attempt time. Statusline mtime must not suppress polls.
        if let status = fetchStatus {
            return now.timeIntervalSince(status.updatedAt) >= maxAge
        }

        // Legacy records without fetchStatus: only trust file age when last write was a poll.
        if origin == "poll",
           let mtime = fileModificationDate,
           now.timeIntervalSince(mtime) < maxAge {
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
                windows: mergePollWindows(
                    mapped: mapped.windows,
                    existing: existing?.windows ?? [],
                    now: observedAt
                ),
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
            windows: mergePollWindows(
                mapped: mergeWindows(
                    statusline: mapped.windows,
                    existing: existing?.windows ?? [],
                    now: now
                ),
                existing: existing?.windows ?? [],
                now: now
            ),
            plan: mapped.plan ?? existing?.plan,
            // Clear error state for the widget, but never advance poll-attempt age —
            // statusline writes must not reset the OAuth poll clock.
            fetchStatus: existing?.fetchStatus.map { prior in
                guard prior.state != .ok else { return prior }
                return FetchStatus(
                    state: .ok,
                    message: nil,
                    retryAfterAt: nil,
                    httpStatus: prior.httpStatus,
                    updatedAt: prior.updatedAt
                )
            }
        )
    }

    /// OAuth often sends `five_hour: null` when no session is open. Keep a still-live
    /// Session; otherwise show 0% until the next 5h window rather than dropping the bar.
    public static func mergePollWindows(
        mapped: [UsageWindow],
        existing: [UsageWindow],
        now: Date = Date()
    ) -> [UsageWindow] {
        if mapped.contains(where: { $0.id == "five_hour" }) {
            return mapped
        }

        let session: UsageWindow
        if let live = existing.first(where: { $0.id == "five_hour" && $0.resetsAt > now }) {
            session = live
        } else {
            session = UsageWindow(
                id: "five_hour",
                label: "Session",
                usedPercent: 0,
                resetsAt: now.addingTimeInterval(5 * 3600)
            )
        }

        return [session] + mapped.filter { $0.id != "five_hour" }
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
