import Foundation
import Testing
@testable import UsageCore

@Suite("UsageCommitTests")
struct UsageCommitTests {
    private let accountId = "acc_commit_one"
    private let baseTime = Date(timeIntervalSince1970: 1_800_000_000)

    private func tempDir() throws -> URL {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appending(path: "usage-commit-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private func targetURL(in dir: URL) -> URL {
        dir.appending(path: "usage-\(accountId).json")
    }

    private func window(id: String = "five_hour") -> UsageWindow {
        UsageWindow(
            id: id,
            label: "Session",
            usedPercent: 19,
            resetsAt: baseTime.addingTimeInterval(3_600)
        )
    }

    private func record(
        updatedAt: Date,
        windows: [UsageWindow],
        accountId: String? = "acc_commit_one"
    ) -> UsageRecord {
        UsageRecord(
            accountId: accountId,
            source: "claude-code",
            updatedAt: updatedAt,
            origin: "poll",
            windows: windows
        )
    }

    private func seed(_ record: UsageRecord, at url: URL) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try UsageRecord.encode(record).write(to: url)
    }

    @Test("commit rejects older or equal updatedAt")
    func rejectsOlder() throws {
        let dir = try tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = targetURL(in: dir)
        try seed(record(updatedAt: baseTime, windows: [window()]), at: url)

        let older = record(
            updatedAt: baseTime.addingTimeInterval(-10),
            windows: [window(id: "seven_day")]
        )
        #expect(try UsageCommit.commit(record: older, to: url) == false)

        let equal = record(updatedAt: baseTime, windows: [window(id: "seven_day")])
        #expect(try UsageCommit.commit(record: equal, to: url) == false)

        guard case .record(let kept) = UsageStore.load(from: url) else {
            Issue.record("expected existing record to remain")
            return
        }
        #expect(kept.updatedAt == baseTime)
        #expect(kept.windows.map(\.id) == ["five_hour"])
    }

    @Test("commit rejects empty windows overwriting non-empty")
    func rejectsEmptyOverwrite() throws {
        let dir = try tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = targetURL(in: dir)
        try seed(record(updatedAt: baseTime, windows: [window()]), at: url)

        let emptyNewer = record(
            updatedAt: baseTime.addingTimeInterval(60),
            windows: []
        )
        #expect(try UsageCommit.commit(record: emptyNewer, to: url) == false)

        guard case .record(let kept) = UsageStore.load(from: url) else {
            Issue.record("expected non-empty record to remain")
            return
        }
        #expect(!kept.windows.isEmpty)
        #expect(kept.updatedAt == baseTime)
    }

    @Test("commit accepts newer updatedAt")
    func acceptsNewer() throws {
        let dir = try tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = targetURL(in: dir)
        try seed(record(updatedAt: baseTime, windows: [window()]), at: url)

        let newer = record(
            updatedAt: baseTime.addingTimeInterval(30),
            windows: [window(id: "seven_day")]
        )
        #expect(try UsageCommit.commit(record: newer, to: url) == true)

        guard case .record(let written) = UsageStore.load(from: url) else {
            Issue.record("expected committed record")
            return
        }
        #expect(written.updatedAt == newer.updatedAt)
        #expect(written.windows.map(\.id) == ["seven_day"])
        #expect(written.accountId == accountId)
    }

    @Test("commit creates file when missing")
    func createsWhenMissing() throws {
        let dir = try tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = targetURL(in: dir)
        let fresh = record(updatedAt: baseTime, windows: [window()])

        #expect(try UsageCommit.commit(record: fresh, to: url) == true)
        guard case .record(let written) = UsageStore.load(from: url) else {
            Issue.record("expected new record")
            return
        }
        #expect(written == fresh)
    }

    @Test("commit rejects filename / accountId mismatches")
    func rejectsMismatchedTarget() throws {
        let dir = try tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let wrongName = dir.appending(path: "usage-acc_other.json")
        let candidate = record(updatedAt: baseTime, windows: [window()])

        #expect(throws: UsageCommitError.self) {
            try UsageCommit.commit(record: candidate, to: wrongName)
        }

        let missingAccount = record(
            updatedAt: baseTime,
            windows: [window()],
            accountId: nil
        )
        #expect(throws: UsageCommitError.self) {
            try UsageCommit.commit(record: missingAccount, to: targetURL(in: dir))
        }
    }

    @Test("commit honors minInterval against file mtime")
    func honorsMinInterval() throws {
        let dir = try tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = targetURL(in: dir)
        try seed(record(updatedAt: baseTime, windows: [window()]), at: url)

        let now = baseTime.addingTimeInterval(5)
        try FileManager.default.setAttributes(
            [.modificationDate: now.addingTimeInterval(-2)],
            ofItemAtPath: url.path
        )

        let newer = record(
            updatedAt: baseTime.addingTimeInterval(60),
            windows: [window(id: "seven_day")]
        )
        #expect(
            try UsageCommit.commit(
                record: newer,
                to: url,
                minInterval: 30,
                now: now
            ) == false
        )
        #expect(
            try UsageCommit.commit(
                record: newer,
                to: url,
                minInterval: 30,
                now: now.addingTimeInterval(40)
            ) == true
        )
    }

    @Test("commit accepts fetchStatus-only update with same updatedAt")
    func acceptsFetchStatusOnly() throws {
        let dir = try tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = targetURL(in: dir)
        let windows = [window()]
        try seed(
            UsageRecord(
                accountId: accountId,
                source: "claude-code",
                updatedAt: baseTime,
                origin: "poll",
                windows: windows,
                fetchStatus: FetchStatus(state: .ok, httpStatus: 200, updatedAt: baseTime)
            ),
            at: url
        )

        let failed = UsageRecord(
            accountId: accountId,
            source: "claude-code",
            updatedAt: baseTime,
            origin: "poll",
            windows: windows,
            fetchStatus: FetchStatus(
                state: .rateLimited,
                message: "rate limited",
                retryAfterAt: baseTime.addingTimeInterval(300),
                httpStatus: 429,
                updatedAt: baseTime.addingTimeInterval(60)
            )
        )
        #expect(try UsageCommit.commit(record: failed, to: url) == true)

        guard case .record(let written) = UsageStore.load(from: url) else {
            Issue.record("expected fetchStatus update"); return
        }
        #expect(written.updatedAt == baseTime)
        #expect(written.fetchStatus?.state == .rateLimited)
        #expect(written.fetchStatus?.updatedAt == baseTime.addingTimeInterval(60))
        #expect(written.windows == windows)
    }
}
