import Foundation
import UsageCore

public struct CodexUsagePoller: Sendable {
    public let client: any CodexAppServerServing
    nonisolated(unsafe) public var fileManager: FileManager
    public let minInterval: TimeInterval

    public init(
        client: any CodexAppServerServing,
        fileManager: FileManager = .default,
        minInterval: TimeInterval = 0
    ) {
        self.client = client
        self.fileManager = fileManager
        self.minInterval = minInterval
    }

    public func poll(
        accountId: String,
        usageURL: URL,
        force: Bool,
        now: Date = Date()
    ) async -> UsagePoller.Step {
        let existing: UsageRecord? = if case .record(let value) = UsageStore.load(from: usageURL) {
            value
        } else {
            nil
        }
        let mtime = (try? fileManager.attributesOfItem(atPath: usageURL.path))?[
            .modificationDate
        ] as? Date
        guard PollPolicy.shouldFetch(
            force: force,
            fileModificationDate: mtime,
            fetchStatus: existing?.fetchStatus,
            origin: existing?.origin,
            windows: existing?.windows ?? [],
            now: now
        ) else { return .skipped }

        let candidate: UsageRecord
        do {
            let mapped = try CodexUsageMapper.map(
                try await client.readRateLimits(),
                accountId: accountId,
                observedAt: now
            )
            candidate = UsageRecord(
                accountId: mapped.accountId,
                source: mapped.source,
                updatedAt: mapped.updatedAt,
                origin: mapped.origin,
                windows: mapped.windows,
                plan: mapped.plan ?? existing?.plan,
                fetchStatus: mapped.fetchStatus
            )
        } catch {
            candidate = UsageRecord(
                accountId: accountId,
                source: "codex",
                updatedAt: existing?.updatedAt ?? now,
                origin: existing?.origin ?? "poll",
                windows: existing?.windows ?? [],
                plan: existing?.plan,
                fetchStatus: FetchStatus(
                    state: .failed,
                    message: "Codex usage refresh failed",
                    updatedAt: now
                )
            )
        }

        do {
            let wrote = try UsageCommit.commit(
                record: candidate,
                to: usageURL,
                minInterval: minInterval,
                fileManager: fileManager,
                now: now
            )
            return .committed(wrote: wrote)
        } catch {
            return .softFailed
        }
    }
}
