import Foundation
import Testing
@testable import UsageCore

private final class FakeFetcher: UsageFetching, @unchecked Sendable {
    var status: Int
    var body: Data
    var retryAfter: TimeInterval?
    var error: (any Error)?
    private(set) var callCount = 0

    init(status: Int = 200, body: Data = Data(), retryAfter: TimeInterval? = nil, error: (any Error)? = nil) {
        self.status = status
        self.body = body
        self.retryAfter = retryAfter
        self.error = error
    }

    func fetchUsage(accessToken: String) async throws -> (status: Int, body: Data, retryAfter: TimeInterval?) {
        _ = accessToken
        callCount += 1
        if let error { throw error }
        return (status, body, retryAfter)
    }
}

private func fixtureURL(_ name: String) throws -> URL {
    var dir = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
    while dir.path != "/" {
        let candidate = dir.appendingPathComponent("tests/fixtures/\(name)")
        if FileManager.default.fileExists(atPath: candidate.path) { return candidate }
        dir.deleteLastPathComponent()
    }
    Issue.record("Fixture not found: \(name)")
    throw CocoaError(.fileNoSuchFile)
}

@Suite("PollPolicyTests")
struct PollPolicyTests {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    @Test("skips fresh poll-origin file without fetchStatus unless force")
    func skipsFreshPollOrigin() {
        let mtime = now.addingTimeInterval(-100)
        #expect(!PollPolicy.shouldFetch(
            force: false, fileModificationDate: mtime, fetchStatus: nil, origin: "poll", now: now
        ))
        #expect(PollPolicy.shouldFetch(
            force: true, fileModificationDate: mtime, fetchStatus: nil, origin: "poll", now: now
        ))
    }

    @Test("fresh statusline mtime with missing poll fetchStatus still fetches")
    func statuslineMtimeDoesNotSkipPoll() {
        let freshMtime = now.addingTimeInterval(-30)
        #expect(PollPolicy.shouldFetch(
            force: false, fileModificationDate: freshMtime, fetchStatus: nil, origin: "statusline", now: now
        ))
    }

    @Test("fresh statusline mtime with stale poll fetchStatus still fetches")
    func stalePollAgeFetchesDespiteFreshStatuslineMtime() {
        let freshMtime = now.addingTimeInterval(-30)
        let stalePoll = FetchStatus(state: .ok, httpStatus: 200, updatedAt: now.addingTimeInterval(-900))
        #expect(PollPolicy.shouldFetch(
            force: false,
            fileModificationDate: freshMtime,
            fetchStatus: stalePoll,
            origin: "statusline",
            now: now
        ))
    }

    @Test("recent poll fetchStatus skips even when file mtime is stale")
    func recentPollAttemptSkips() {
        let staleMtime = now.addingTimeInterval(-900)
        let recentPoll = FetchStatus(state: .ok, httpStatus: 200, updatedAt: now.addingTimeInterval(-100))
        #expect(!PollPolicy.shouldFetch(
            force: false,
            fileModificationDate: staleMtime,
            fetchStatus: recentPoll,
            origin: "statusline",
            now: now
        ))
    }

    @Test("skips during rate-limit cooldown even if file is stale")
    func cooldown() {
        let mtime = now.addingTimeInterval(-900)
        let active = FetchStatus(state: .rateLimited, retryAfterAt: now.addingTimeInterval(60), updatedAt: now)
        #expect(!PollPolicy.shouldFetch(
            force: false, fileModificationDate: mtime, fetchStatus: active, origin: "poll", now: now
        ))
        #expect(PollPolicy.shouldFetch(
            force: true, fileModificationDate: mtime, fetchStatus: active, origin: "poll", now: now
        ))
        let expired = FetchStatus(state: .rateLimited, retryAfterAt: now.addingTimeInterval(-1), updatedAt: now)
        #expect(PollPolicy.shouldFetch(
            force: false, fileModificationDate: mtime, fetchStatus: expired, origin: "poll", now: now
        ))
    }

    @Test("expired rate-limit cooldown fetches even when file mtime is fresh")
    func cooldownExpiredIgnoresFreshMtime() {
        let freshMtime = now.addingTimeInterval(-30)
        let expired = FetchStatus(
            state: .rateLimited,
            retryAfterAt: now.addingTimeInterval(-1),
            updatedAt: now.addingTimeInterval(-100)
        )
        #expect(PollPolicy.shouldFetch(
            force: false, fileModificationDate: freshMtime, fetchStatus: expired, origin: "poll", now: now
        ))
        let active = FetchStatus(
            state: .rateLimited,
            retryAfterAt: now.addingTimeInterval(60),
            updatedAt: now.addingTimeInterval(-10)
        )
        #expect(!PollPolicy.shouldFetch(
            force: false, fileModificationDate: freshMtime, fetchStatus: active, origin: "poll", now: now
        ))
    }

    @Test("200 maps fixture and sets fetchStatus ok")
    func okMapping() throws {
        let body = try Data(contentsOf: fixtureURL("oauth-usage-response.json"))
        let record = PollPolicy.makePollRecord(
            accountId: "acc_test", status: 200, body: body, retryAfter: nil, existing: nil, observedAt: now
        )
        #expect(record?.fetchStatus?.state == .ok)
        #expect(record?.fetchStatus?.httpStatus == 200)
        #expect(record?.windows.isEmpty == false)
    }

    @Test("429 preserves windows and last-good updatedAt")
    func rateLimited() {
        let lastGood = now.addingTimeInterval(-500)
        let attempt = now
        let existing = UsageRecord(
            accountId: "acc_test", source: "claude-code", updatedAt: lastGood, origin: "poll",
            windows: [UsageWindow(id: "five_hour", label: "Session", usedPercent: 10, resetsAt: now.addingTimeInterval(3600))]
        )
        let record = PollPolicy.makePollRecord(
            accountId: "acc_test", status: 429, body: Data(), retryAfter: 120, existing: existing, observedAt: attempt
        )
        #expect(record?.windows.first?.usedPercent == 10)
        #expect(record?.updatedAt == lastGood)
        #expect(record?.fetchStatus?.state == .rateLimited)
        #expect(record?.fetchStatus?.updatedAt == attempt)
        #expect(record?.fetchStatus?.retryAfterAt == attempt.addingTimeInterval(120))
    }

    @Test("failed poll keeps last-good updatedAt")
    func failedKeepsLastGoodTimestamp() {
        let lastGood = now.addingTimeInterval(-800)
        let attempt = now
        let existing = UsageRecord(
            accountId: "acc_test", source: "claude-code", updatedAt: lastGood, origin: "poll",
            windows: [UsageWindow(id: "seven_day", label: "Week", usedPercent: 55, resetsAt: now.addingTimeInterval(7200))]
        )
        let record = PollPolicy.makePollRecord(
            accountId: "acc_test", status: 500, body: Data(), retryAfter: nil, existing: existing, observedAt: attempt
        )
        #expect(record?.updatedAt == lastGood)
        #expect(record?.windows.first?.usedPercent == 55)
        #expect(record?.fetchStatus?.state == .failed)
        #expect(record?.fetchStatus?.updatedAt == attempt)
        #expect(record?.fetchStatus?.httpStatus == 500)
    }

    @Test("non-429 errors without existing use attempt time")
    func failed() {
        let record = PollPolicy.makePollRecord(
            accountId: "acc_test", status: 500, body: Data(), retryAfter: nil, existing: nil, observedAt: now
        )
        #expect(record?.fetchStatus?.state == .failed)
        #expect(record?.fetchStatus?.httpStatus == 500)
        #expect(record?.updatedAt == now)
        #expect(record?.windows.isEmpty == true)
    }

    @Test("statusline prepare clears prior rateLimited without advancing poll age")
    func statuslineClears() {
        let pollAttempt = now.addingTimeInterval(-400)
        let window = UsageWindow(id: "five_hour", label: "Session", usedPercent: 1, resetsAt: now.addingTimeInterval(60))
        let mapped = UsageRecord(accountId: "acc_test", source: "claude-code", updatedAt: now, origin: "statusline", windows: [window])
        let existing = UsageRecord(
            accountId: "acc_test", source: "claude-code", updatedAt: now, origin: "poll",
            windows: [window],
            fetchStatus: FetchStatus(state: .rateLimited, updatedAt: pollAttempt)
        )
        let prepared = PollPolicy.prepareStatuslineRecord(mapped: mapped, existing: existing)
        #expect(prepared?.fetchStatus?.state == .ok)
        #expect(prepared?.fetchStatus?.updatedAt == pollAttempt)
    }

    @Test("empty statusline mapping soft-skips prepare")
    func emptyStatuslineSkips() throws {
        let data = try Data(contentsOf: fixtureURL("statusline-none.json"))
        let mapped = try StatuslineUsageMapper.map(data: data, accountId: "acc_test", observedAt: now)
        #expect(mapped.windows.isEmpty)
        let existing = UsageRecord(
            accountId: "acc_test", source: "claude-code", updatedAt: now.addingTimeInterval(-50), origin: "poll",
            windows: [UsageWindow(id: "five_hour", label: "Session", usedPercent: 10, resetsAt: now.addingTimeInterval(60))]
        )
        #expect(PollPolicy.prepareStatuslineRecord(mapped: mapped, existing: existing, now: now) == nil)
    }

    @Test("statusline write merges live OAuth-only windows by id")
    func statuslinePreservesOAuthOnlyWindows() {
        let resets = now.addingTimeInterval(3600)
        let mapped = UsageRecord(
            accountId: "acc_test", source: "claude-code", updatedAt: now, origin: "statusline",
            windows: [
                UsageWindow(id: "five_hour", label: "Session", usedPercent: 22, resetsAt: resets),
                UsageWindow(id: "seven_day", label: "Week", usedPercent: 40, resetsAt: resets),
            ]
        )
        let existing = UsageRecord(
            accountId: "acc_test", source: "claude-code", updatedAt: now.addingTimeInterval(-100), origin: "poll",
            windows: [
                UsageWindow(id: "five_hour", label: "Session", usedPercent: 10, resetsAt: resets),
                UsageWindow(id: "seven_day_sonnet", label: "Sonnet", usedPercent: 70, resetsAt: resets),
                UsageWindow(id: "extra_usage", label: "Extra usage", usedPercent: 5, resetsAt: resets, kind: "extra_usage"),
            ]
        )
        let prepared = PollPolicy.prepareStatuslineRecord(mapped: mapped, existing: existing, now: now)
        #expect(prepared?.windows.map(\.id) == ["five_hour", "seven_day", "seven_day_sonnet", "extra_usage"])
        #expect(prepared?.windows.first { $0.id == "five_hour" }?.usedPercent == 22)
        #expect(prepared?.windows.first { $0.id == "seven_day_sonnet" }?.usedPercent == 70)
        #expect(prepared?.windows.first { $0.id == "extra_usage" }?.usedPercent == 5)
    }

    @Test("statusline omits primary window and drops stale OAuth primary")
    func statuslineDropsOmittedPrimary() {
        let resets = now.addingTimeInterval(3600)
        let mapped = UsageRecord(
            accountId: "acc_test", source: "claude-code", updatedAt: now, origin: "statusline",
            windows: [UsageWindow(id: "five_hour", label: "Session", usedPercent: 22, resetsAt: resets)]
        )
        let existing = UsageRecord(
            accountId: "acc_test", source: "claude-code", updatedAt: now.addingTimeInterval(-100), origin: "poll",
            windows: [
                UsageWindow(id: "five_hour", label: "Session", usedPercent: 10, resetsAt: resets),
                UsageWindow(id: "seven_day", label: "Week", usedPercent: 40, resetsAt: resets),
                UsageWindow(id: "seven_day_sonnet", label: "Sonnet", usedPercent: 70, resetsAt: resets),
            ]
        )
        let prepared = PollPolicy.prepareStatuslineRecord(mapped: mapped, existing: existing, now: now)
        #expect(prepared?.windows.map(\.id) == ["five_hour", "seven_day_sonnet"])
        #expect(prepared?.windows.contains { $0.id == "seven_day" } == false)
    }

    @Test("statusline merge drops expired OAuth-only windows")
    func statuslineDropsExpiredOAuthOnly() {
        let live = now.addingTimeInterval(3600)
        let expired = now.addingTimeInterval(-10)
        let mapped = UsageRecord(
            accountId: "acc_test", source: "claude-code", updatedAt: now, origin: "statusline",
            windows: [UsageWindow(id: "five_hour", label: "Session", usedPercent: 22, resetsAt: live)]
        )
        let existing = UsageRecord(
            accountId: "acc_test", source: "claude-code", updatedAt: now.addingTimeInterval(-100), origin: "poll",
            windows: [
                UsageWindow(id: "seven_day_sonnet", label: "Sonnet", usedPercent: 70, resetsAt: expired),
                UsageWindow(id: "extra_usage", label: "Extra usage", usedPercent: 5, resetsAt: live, kind: "extra_usage"),
            ]
        )
        let prepared = PollPolicy.prepareStatuslineRecord(mapped: mapped, existing: existing, now: now)
        #expect(prepared?.windows.map(\.id) == ["five_hour", "extra_usage"])
        #expect(prepared?.windows.contains { $0.id == "seven_day_sonnet" } == false)
    }
}

@Suite("UsagePollerTests")
struct UsagePollerTests {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)
    private let accountId = "acc_poll_fake"

    private func tempUsageURL(age: TimeInterval, usedPercent: Double) throws -> (dir: URL, url: URL) {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory()).appending(path: "usage-poller-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appending(path: "usage-\(accountId).json")
        let seed = UsageRecord(
            accountId: accountId, source: "claude-code", updatedAt: now.addingTimeInterval(age),
            origin: "poll",
            windows: [UsageWindow(id: "five_hour", label: "Session", usedPercent: usedPercent, resetsAt: now.addingTimeInterval(60))]
        )
        try UsageRecord.encode(seed).write(to: url)
        try FileManager.default.setAttributes([.modificationDate: now.addingTimeInterval(age)], ofItemAtPath: url.path)
        return (dir, url)
    }

    @Test("fake fetcher 200 commits without network")
    func commitsOk() async throws {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory()).appending(path: "usage-poller-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appending(path: "usage-\(accountId).json")
        let fake = FakeFetcher(status: 200, body: try Data(contentsOf: fixtureURL("oauth-usage-response.json")))
        let step = await UsagePoller(fetcher: fake).poll(
            accountId: accountId, accessToken: "test-token", usageURL: url, force: true, now: now
        )
        #expect(step == .committed(wrote: true))
        #expect(fake.callCount == 1)
        guard case .record(let record) = UsageStore.load(from: url) else {
            Issue.record("expected committed record"); return
        }
        #expect(record.fetchStatus?.state == .ok && !record.windows.isEmpty)
    }

    @Test("skips when file is fresh without force")
    func skipsFreshWithoutCallingFetcher() async throws {
        let (dir, url) = try tempUsageURL(age: -30, usedPercent: 1)
        defer { try? FileManager.default.removeItem(at: dir) }
        let fake = FakeFetcher()
        let step = await UsagePoller(fetcher: fake).poll(
            accountId: accountId, accessToken: "test-token", usageURL: url, force: false, now: now
        )
        #expect(step == .skipped && fake.callCount == 0)
    }

    @Test("429 commits rateLimited with preserved windows and last-good updatedAt")
    func rateLimitedCommit() async throws {
        let (dir, url) = try tempUsageURL(age: -900, usedPercent: 42)
        defer { try? FileManager.default.removeItem(at: dir) }
        let lastGood = now.addingTimeInterval(-900)
        let step = await UsagePoller(fetcher: FakeFetcher(status: 429, retryAfter: 90)).poll(
            accountId: accountId, accessToken: "test-token", usageURL: url, force: true, now: now
        )
        #expect(step == .committed(wrote: true))
        guard case .record(let record) = UsageStore.load(from: url) else {
            Issue.record("expected rateLimited record"); return
        }
        #expect(record.fetchStatus?.state == .rateLimited)
        #expect(record.windows.first?.usedPercent == 42)
        #expect(record.updatedAt == lastGood)
        #expect(record.fetchStatus?.updatedAt == now)
        #expect(record.fetchStatus?.retryAfterAt == now.addingTimeInterval(90))
    }
}
