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

    @Test("skips fresh file unless force")
    func skipsFresh() {
        let mtime = now.addingTimeInterval(-100)
        #expect(!PollPolicy.shouldFetch(force: false, fileModificationDate: mtime, fetchStatus: nil, now: now))
        #expect(PollPolicy.shouldFetch(force: true, fileModificationDate: mtime, fetchStatus: nil, now: now))
    }

    @Test("skips during rate-limit cooldown even if file is stale")
    func cooldown() {
        let mtime = now.addingTimeInterval(-900)
        let active = FetchStatus(state: .rateLimited, retryAfterAt: now.addingTimeInterval(60), updatedAt: now)
        #expect(!PollPolicy.shouldFetch(force: false, fileModificationDate: mtime, fetchStatus: active, now: now))
        #expect(PollPolicy.shouldFetch(force: true, fileModificationDate: mtime, fetchStatus: active, now: now))
        let expired = FetchStatus(state: .rateLimited, retryAfterAt: now.addingTimeInterval(-1), updatedAt: now)
        #expect(PollPolicy.shouldFetch(force: false, fileModificationDate: mtime, fetchStatus: expired, now: now))
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

    @Test("429 preserves windows and sets rateLimited cooldown")
    func rateLimited() {
        let existing = UsageRecord(
            accountId: "acc_test", source: "claude-code", updatedAt: now, origin: "poll",
            windows: [UsageWindow(id: "five_hour", label: "Session", usedPercent: 10, resetsAt: now.addingTimeInterval(3600))]
        )
        let record = PollPolicy.makePollRecord(
            accountId: "acc_test", status: 429, body: Data(), retryAfter: 120, existing: existing, observedAt: now
        )
        #expect(record?.windows.first?.usedPercent == 10)
        #expect(record?.fetchStatus?.state == .rateLimited)
        #expect(record?.fetchStatus?.retryAfterAt == now.addingTimeInterval(120))
    }

    @Test("non-429 errors set failed")
    func failed() {
        let record = PollPolicy.makePollRecord(
            accountId: "acc_test", status: 500, body: Data(), retryAfter: nil, existing: nil, observedAt: now
        )
        #expect(record?.fetchStatus?.state == .failed)
        #expect(record?.fetchStatus?.httpStatus == 500)
        #expect(record?.windows.isEmpty == true)
    }

    @Test("statusline prepare clears prior rateLimited")
    func statuslineClears() {
        let window = UsageWindow(id: "five_hour", label: "Session", usedPercent: 1, resetsAt: now.addingTimeInterval(60))
        let mapped = UsageRecord(accountId: "acc_test", source: "claude-code", updatedAt: now, origin: "statusline", windows: [window])
        let existing = UsageRecord(
            accountId: "acc_test", source: "claude-code", updatedAt: now, origin: "poll",
            windows: [window], fetchStatus: FetchStatus(state: .rateLimited, updatedAt: now)
        )
        #expect(PollPolicy.prepareStatuslineRecord(mapped: mapped, existing: existing).fetchStatus?.state == .ok)
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

    @Test("429 commits rateLimited with preserved windows")
    func rateLimitedCommit() async throws {
        let (dir, url) = try tempUsageURL(age: -900, usedPercent: 42)
        defer { try? FileManager.default.removeItem(at: dir) }
        let step = await UsagePoller(fetcher: FakeFetcher(status: 429, retryAfter: 90)).poll(
            accountId: accountId, accessToken: "test-token", usageURL: url, force: true, now: now
        )
        #expect(step == .committed(wrote: true))
        guard case .record(let record) = UsageStore.load(from: url) else {
            Issue.record("expected rateLimited record"); return
        }
        #expect(record.fetchStatus?.state == .rateLimited)
        #expect(record.windows.first?.usedPercent == 42)
        #expect(record.fetchStatus?.retryAfterAt == now.addingTimeInterval(90))
    }
}
