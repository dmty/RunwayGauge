import Foundation
import Testing
@testable import UsageCore

private let now = Date(timeIntervalSince1970: 1_800_000_000)

private func tempDir() throws -> URL {
    let dir = URL(fileURLWithPath: NSTemporaryDirectory())
        .appending(path: "usage-store-tests-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    return dir
}

private func storeFile(in dir: URL, contents: String) throws -> URL {
    let url = dir.appending(path: "claude-code.json")
    try Data(contents.utf8).write(to: url)
    return url
}

private let validPayload = """
{"schema":1,"source":"claude-code","updatedAt":1799999940,"origin":"statusline",
 "windows":[{"id":"five_hour","label":"Session","usedPercent":19.0,"resetsAt":1800003600}]}
"""

private let expectedUsageFile = URL(fileURLWithPath:
    "/Users/test/Library/Containers/com.mirabilia.MacUsageWidget.UsageWidget/Data/Library/Application Support/MacUsageWidget/claude-code.json"
)

@Test("default path is derived from the home directory")
func defaultPath() {
    let home = URL(fileURLWithPath: "/Users/test")
    #expect(UsageStore.url(source: "claude-code", home: home) == expectedUsageFile)
}

@Test("widget extension container home uses short Application Support path")
func containerHomePath() {
    let home = URL(fileURLWithPath:
        "/Users/test/Library/Containers/com.mirabilia.MacUsageWidget.UsageWidget/Data"
    )
    #expect(UsageStore.url(source: "claude-code", home: home) == expectedUsageFile)
}

@Test("host app container home resolves to widget extension data path")
func hostAppContainerHomePath() {
    let home = URL(fileURLWithPath:
        "/Users/test/Library/Containers/com.mirabilia.MacUsageWidget/Data"
    )
    #expect(UsageStore.url(source: "claude-code", home: home) == expectedUsageFile)
}

@Test("missing file loads as missing")
func missingFile() throws {
    let dir = try tempDir()
    #expect(UsageStore.load(from: dir.appending(path: "nope.json")) == .missing)
}

@Test("valid file loads as a record")
func validFile() throws {
    let url = try storeFile(in: try tempDir(), contents: validPayload)
    guard case .record(let r) = UsageStore.load(from: url) else {
        Issue.record("expected a record"); return
    }
    #expect(r.windows.count == 1)
}

@Test("malformed file loads as unreadable")
func malformedFile() throws {
    let url = try storeFile(in: try tempDir(), contents: "{broken")
    #expect(UsageStore.load(from: url) == .unreadable)
}

@Test("existing but unreadable path loads as unreadable, not missing")
func existingButUnreadablePath() throws {
    let dir = try tempDir()
    let url = dir.appending(path: "claude-code.json")
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: url) }
    #expect(UsageStore.load(from: url) == .unreadable)
}

@Test("unknown schema loads as unreadable")
func unknownSchema() throws {
    let url = try storeFile(
        in: try tempDir(),
        contents: #"{"schema":99,"source":"x","updatedAt":1,"origin":"y","windows":[]}"#
    )
    #expect(UsageStore.load(from: url) == .unreadable)
}

@Test("missing maps to the empty state")
func stateMissing() {
    #expect(UsageStore.state(for: .missing, now: now, path: "/p") == .empty)
}

@Test("unreadable maps to the unreadable state carrying the path")
func stateUnreadable() {
    #expect(UsageStore.state(for: .unreadable, now: now, path: "/p") == .unreadable(path: "/p"))
}

@Test("a record with zero windows maps to the empty state, not a data state")
func stateEmptyWindows() {
    let record = UsageRecord(source: "claude-code", updatedAt: now, origin: "poll", windows: [])
    #expect(UsageStore.state(for: .record(record), now: now, path: "/p") == .empty)
}

@Test("a record with windows maps to a data state carrying freshness")
func stateData() {
    let record = UsageRecord(
        source: "claude-code",
        updatedAt: now.addingTimeInterval(-60),
        origin: "statusline",
        windows: [UsageWindow(id: "five_hour", label: "Session", usedPercent: 19, resetsAt: now.addingTimeInterval(3600))]
    )
    #expect(UsageStore.state(for: .record(record), now: now, path: "/p") == .data(record: record, freshness: .fresh))
}
