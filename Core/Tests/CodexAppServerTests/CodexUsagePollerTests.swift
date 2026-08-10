import Foundation
import Testing
import UsageCore
@testable import CodexAppServer

private enum FixtureFailure: Error, Sendable { case unavailable }

private actor PollFixtureServer: CodexAppServerServing {
    var result: Result<CodexRateLimitsReadResult, FixtureFailure>
    private(set) var rateLimitReads = 0

    init(result: Result<CodexRateLimitsReadResult, FixtureFailure>) {
        self.result = result
    }

    func readAccount() async throws -> CodexAccountReadResult {
        CodexAccountReadResult(account: CodexAccountInfo(type: "chatgpt"))
    }

    func readRateLimits() async throws -> CodexRateLimitsReadResult {
        rateLimitReads += 1
        return try result.get()
    }

    func readCount() -> Int { rateLimitReads }
}

private func pollLimits() -> CodexRateLimitsReadResult {
    CodexRateLimitsReadResult(
        rateLimits: CodexRateLimitBucket(
            limitId: "codex",
            primary: CodexRateLimitWindow(
                usedPercent: 20,
                windowDurationMins: 300,
                resetsAt: 5_000
            ),
            secondary: CodexRateLimitWindow(
                usedPercent: 40,
                windowDurationMins: 10_080,
                resetsAt: 8_000
            ),
            planType: "plus"
        ),
        rateLimitsByLimitId: nil
    )
}

private func usageURL() throws -> URL {
    let directory = FileManager.default.temporaryDirectory
        .appending(path: "codex-poller-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    return directory.appending(path: "usage-\(CodexAccount.id).json")
}

@Suite("CodexUsagePollerTests")
struct CodexUsagePollerTests {
    @Test("successful poll commits both Codex windows")
    func commitsSuccess() async throws {
        let url = try usageURL()
        let server = PollFixtureServer(result: .success(pollLimits()))
        let step = await CodexUsagePoller(client: server).poll(
            accountId: CodexAccount.id,
            usageURL: url,
            force: false,
            now: Date(timeIntervalSince1970: 1_000)
        )

        #expect(step == .committed(wrote: true))
        let record = try #require({
            if case .record(let value) = UsageStore.load(from: url) { return value }
            return nil
        }())
        #expect(record.source == "codex")
        #expect(record.windows.map(\.id) == ["five_hour", "seven_day"])
        #expect(record.plan == "plus")
    }

    @Test("failure keeps last-good values and advances only fetch status")
    func preservesLastGood() async throws {
        let url = try usageURL()
        let oldDate = Date(timeIntervalSince1970: 900)
        let old = UsageRecord(
            accountId: CodexAccount.id,
            source: "codex",
            updatedAt: oldDate,
            origin: "poll",
            windows: [UsageWindow(
                id: "five_hour",
                label: "Current session",
                usedPercent: 9,
                resetsAt: Date(timeIntervalSince1970: 5_000)
            )],
            plan: "plus"
        )
        #expect(try UsageCommit.commit(record: old, to: url))
        let server = PollFixtureServer(result: .failure(.unavailable))

        #expect(await CodexUsagePoller(client: server).poll(
            accountId: CodexAccount.id,
            usageURL: url,
            force: true,
            now: Date(timeIntervalSince1970: 1_000)
        ) == .committed(wrote: true))

        let record = try #require({
            if case .record(let value) = UsageStore.load(from: url) { return value }
            return nil
        }())
        #expect(record.updatedAt == oldDate)
        #expect(record.windows == old.windows)
        #expect(record.fetchStatus?.state == .failed)
        #expect(record.fetchStatus?.message == "Codex usage refresh failed")
        #expect(record.fetchStatus?.updatedAt == Date(timeIntervalSince1970: 1_000))
    }

    @Test("first failure commits a no-data failure record")
    func firstFailure() async throws {
        let url = try usageURL()
        let server = PollFixtureServer(result: .failure(.unavailable))

        #expect(await CodexUsagePoller(client: server).poll(
            accountId: CodexAccount.id,
            usageURL: url,
            force: false,
            now: Date(timeIntervalSince1970: 1_000)
        ) == .committed(wrote: true))

        let record = try #require({
            if case .record(let value) = UsageStore.load(from: url) { return value }
            return nil
        }())
        #expect(record.windows.isEmpty)
        #expect(record.fetchStatus?.state == .failed)
        #expect(record.updatedAt == Date(timeIntervalSince1970: 1_000))
    }

    @Test("fresh data skips normally and force bypasses freshness")
    func forceBypassesFreshness() async throws {
        let url = try usageURL()
        let server = PollFixtureServer(result: .success(pollLimits()))
        let poller = CodexUsagePoller(client: server)
        #expect(await poller.poll(
            accountId: CodexAccount.id,
            usageURL: url,
            force: false,
            now: Date(timeIntervalSince1970: 1_000)
        ) == .committed(wrote: true))
        #expect(await poller.poll(
            accountId: CodexAccount.id,
            usageURL: url,
            force: false,
            now: Date(timeIntervalSince1970: 1_100)
        ) == .skipped)
        #expect(await poller.poll(
            accountId: CodexAccount.id,
            usageURL: url,
            force: true,
            now: Date(timeIntervalSince1970: 1_101)
        ) == .committed(wrote: true))
        #expect(await server.readCount() == 2)
    }
}
