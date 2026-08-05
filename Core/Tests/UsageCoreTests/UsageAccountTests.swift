import Foundation
import Testing
@testable import UsageCore

@Suite("UsageAccountTests")
struct UsageAccountTests {
    private func tempHome() throws -> URL {
        let home = URL(fileURLWithPath: NSTemporaryDirectory())
            .appending(path: "usage-account-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        return home
    }

    private func payload(accountId: String? = "acc_one") -> Data {
        let accountField = accountId.map { #""accountId":"\#($0)","# } ?? ""
        return Data("""
        {"schema":1,\(accountField)"source":"claude-code","updatedAt":1785812495,
         "origin":"poll","windows":[]}
        """.utf8)
    }

    private func writeUsage(_ data: Data, accountId: String, home: URL) throws {
        let url = try UsageStore.usageURL(accountId: accountId, home: home)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: url)
    }

    @Test("account IDs are validated before constructing usage filenames")
    func rejectsUnsafeAccountPaths() throws {
        let home = try tempHome()
        for id in ["", "one", "acc_../escape", "acc_a/b", "acc_💣"] {
            #expect(throws: AccountValidationError.invalidID(id)) {
                try UsageStore.usageURL(accountId: id, home: home)
            }
        }
        #expect(try UsageStore.usageURL(accountId: "acc_safe-1", home: home).lastPathComponent == "usage-acc_safe-1.json")
    }

    @Test("per-account loads accept only a matching embedded account ID")
    func matchingLoad() throws {
        let home = try tempHome()
        try writeUsage(payload(), accountId: "acc_one", home: home)

        guard case .record(let record) = UsageStore.load(accountId: "acc_one", home: home) else {
            Issue.record("expected matching usage record")
            return
        }
        #expect(record.accountId == "acc_one")
    }

    @Test("per-account loads distinguish missing files and reject malformed or mismatched payloads")
    func rejectedLoads() throws {
        let home = try tempHome()
        #expect(UsageStore.load(accountId: "acc_one", home: home) == .missing)

        try writeUsage(Data("{broken".utf8), accountId: "acc_one", home: home)
        #expect(UsageStore.load(accountId: "acc_one", home: home) == .unreadable)

        try writeUsage(payload(accountId: "acc_two"), accountId: "acc_one", home: home)
        #expect(UsageStore.load(accountId: "acc_one", home: home) == .unreadable)

        try writeUsage(payload(accountId: nil), accountId: "acc_one", home: home)
        #expect(UsageStore.load(accountId: "acc_one", home: home) == .unreadable)
    }

    @Test("schema 1 legacy payload remains decodable only through the legacy decoder")
    func legacyCompatibilityIsIsolated() throws {
        let home = try tempHome()
        let legacy = UsageStore.url(source: "claude-code", home: home)
        try FileManager.default.createDirectory(at: legacy.deletingLastPathComponent(), withIntermediateDirectories: true)
        try payload(accountId: nil).write(to: legacy)

        guard case .record(let record) = UsageStore.load(from: legacy) else {
            Issue.record("expected legacy decode")
            return
        }
        #expect(record.accountId == nil)

        try writeUsage(payload(accountId: nil), accountId: "acc_one", home: home)
        #expect(UsageStore.load(accountId: "acc_one", home: home) == .unreadable)
        #expect(UsageRecord.currentSchema == 1)
    }
}
