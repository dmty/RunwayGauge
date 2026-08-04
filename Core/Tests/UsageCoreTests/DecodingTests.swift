import Foundation
import Testing
@testable import UsageCore

private func json(_ s: String) -> Data { Data(s.utf8) }
private func epoch(_ seconds: Double) -> Date { Date(timeIntervalSince1970: seconds) }

private func recordJSON(origin: String, windowsJSON: String) -> Data {
    json("""
    {"schema":1,"source":"claude-code","updatedAt":1785812495,"origin":"\(origin)",
     "windows":\(windowsJSON)}
    """)
}

private let bothWindows = json("""
{"schema":1,"source":"claude-code","updatedAt":1785812495,"origin":"statusline",
 "windows":[
   {"id":"five_hour","label":"Session","usedPercent":19.0,"resetsAt":1785823140},
   {"id":"seven_day","label":"Week","usedPercent":73.0,"resetsAt":1786143540}]}
""")

@Test("decodes both windows in order")
func decodesBoth() throws {
    let r = try UsageRecord.decode(bothWindows)
    #expect(r.source == "claude-code")
    #expect(r.origin == "statusline")
    #expect(r.updatedAt == epoch(1785812495))
    #expect(r.windows.count == 2)
    #expect(r.windows[0].id == "five_hour")
    #expect(r.windows[0].label == "Session")
    #expect(r.windows[0].usedPercent == 19.0)
    #expect(r.windows[0].resetsAt == epoch(1785823140))
    #expect(r.windows[1].id == "seven_day")
    #expect(r.windows[1].usedPercent == 73.0)
}

@Test("decodes a single window")
func decodesOne() throws {
    let r = try UsageRecord.decode(recordJSON(
        origin: "poll",
        windowsJSON: #"[{"id":"seven_day","label":"Week","usedPercent":73.0,"resetsAt":1786143540}]"#
    ))
    #expect(r.windows.count == 1)
    #expect(r.windows[0].id == "seven_day")
}

@Test("decodes zero windows")
func decodesNone() throws {
    let r = try UsageRecord.decode(recordJSON(origin: "poll", windowsJSON: "[]"))
    #expect(r.windows.isEmpty)
}

@Test("rejects an unsupported schema")
func rejectsSchema() {
    let data = json("""
    {"schema":2,"source":"claude-code","updatedAt":1785812495,"origin":"poll","windows":[]}
    """)
    #expect(throws: UsageDecodeError.unsupportedSchema(2)) { try UsageRecord.decode(data) }
}

@Test("rejects malformed json")
func rejectsMalformed() {
    #expect(throws: UsageDecodeError.malformed) { try UsageRecord.decode(json("{not json")) }
}

@Test("rejects a record missing required fields")
func rejectsMissingFields() {
    #expect(throws: UsageDecodeError.malformed) {
        try UsageRecord.decode(json(#"{"schema":1,"source":"claude-code"}"#))
    }
}

@Test("rejects a window missing required fields rather than partially decoding")
func rejectsPartialWindow() {
    #expect(throws: UsageDecodeError.malformed) {
        try UsageRecord.decode(recordJSON(
            origin: "poll",
            windowsJSON: #"[{"id":"five_hour","label":"Session"}]"#
        ))
    }
}
