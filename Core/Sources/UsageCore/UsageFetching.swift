import Foundation

public protocol UsageFetching: Sendable {
    func fetchUsage(accessToken: String) async throws -> (
        status: Int,
        body: Data,
        retryAfter: TimeInterval?
    )
}

public struct UsagePoller {
    public var fetcher: any UsageFetching
    nonisolated(unsafe) public var fileManager: FileManager
    public var minInterval: TimeInterval

    public init(
        fetcher: any UsageFetching,
        fileManager: FileManager = .default,
        minInterval: TimeInterval = 0
    ) {
        self.fetcher = fetcher
        self.fileManager = fileManager
        self.minInterval = minInterval
    }

    public enum Step: Equatable, Sendable {
        case skipped
        case committed(wrote: Bool)
        case softFailed
    }

    public func poll(
        accountId: String,
        accessToken: String,
        usageURL: URL,
        force: Bool,
        now: Date = Date()
    ) async -> Step {
        let existing = loadExisting(from: usageURL)
        let mtime = (try? fileManager.attributesOfItem(atPath: usageURL.path))?[.modificationDate] as? Date
        guard PollPolicy.shouldFetch(
            force: force,
            fileModificationDate: mtime,
            fetchStatus: existing?.fetchStatus,
            now: now
        ) else { return .skipped }

        let status: Int
        let body: Data
        let retryAfter: TimeInterval?
        do {
            (status, body, retryAfter) = try await fetcher.fetchUsage(accessToken: accessToken)
        } catch {
            (status, body, retryAfter) = (-1, Data(), nil)
        }

        guard let record = PollPolicy.makePollRecord(
            accountId: accountId,
            status: status,
            body: body,
            retryAfter: retryAfter,
            existing: existing,
            observedAt: now
        ) else { return .softFailed }

        return commit(record, to: usageURL, now: now)
    }

    private func loadExisting(from url: URL) -> UsageRecord? {
        if case .record(let record) = UsageStore.load(from: url) { return record }
        return nil
    }

    private func commit(_ record: UsageRecord, to url: URL, now: Date) -> Step {
        do {
            let wrote = try UsageCommit.commit(
                record: record,
                to: url,
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
