import Foundation

/// HTTP GET of Anthropic OAuth usage. Injectable so unit tests never hit the network.
public protocol UsageFetching: Sendable {
    func fetchUsage(accessToken: String) async throws -> (
        status: Int,
        body: Data,
        retryAfter: TimeInterval?
    )
}

/// Orchestrates poll: skip policy → fetch → map/commit. Token must already be resolved.
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
        let existing: UsageRecord?
        if case .record(let record) = UsageStore.load(from: usageURL) {
            existing = record
        } else {
            existing = nil
        }

        let mtime = (try? fileManager.attributesOfItem(atPath: usageURL.path))?[.modificationDate] as? Date
        guard PollPolicy.shouldFetch(
            force: force,
            fileModificationDate: mtime,
            fetchStatus: existing?.fetchStatus,
            now: now
        ) else {
            return .skipped
        }

        let response: (status: Int, body: Data, retryAfter: TimeInterval?)
        do {
            response = try await fetcher.fetchUsage(accessToken: accessToken)
        } catch {
            let failed = PollPolicy.makePollRecord(
                accountId: accountId,
                status: -1,
                body: Data(),
                retryAfter: nil,
                existing: existing,
                observedAt: now
            )
            guard let failed else { return .softFailed }
            do {
                let wrote = try UsageCommit.commit(
                    record: failed,
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

        guard let record = PollPolicy.makePollRecord(
            accountId: accountId,
            status: response.status,
            body: response.body,
            retryAfter: response.retryAfter,
            existing: existing,
            observedAt: now
        ) else {
            return .softFailed
        }

        do {
            let wrote = try UsageCommit.commit(
                record: record,
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
