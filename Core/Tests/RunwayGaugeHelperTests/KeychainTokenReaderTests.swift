import Foundation
import Testing
@testable import RunwayGaugeHelper

@Suite("KeychainTokenReaderTests")
struct KeychainTokenReaderTests {
    private func fakeSecurity(_ body: String) throws -> (tool: URL, log: URL) {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("fake-security-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let tool = dir.appendingPathComponent("security")
        let log = dir.appendingPathComponent("args.log")
        let script = "#!/bin/bash\nprintf '%s\\n' \"$@\" > '\(log.path)'\n\(body)\n"
        try script.write(to: tool, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: tool.path)
        return (tool, log)
    }

    @Test("reads the pinned item through security find-generic-password -w")
    func readsPinnedItem() throws {
        let fake = try fakeSecurity(#"echo '{"claudeAiOauth":{"accessToken":"tok"}}'"#)
        let data = KeychainTokenReader.credentialData(
            service: " Claude Code-credentials-abc ",
            account: "dmitry",
            tool: fake.tool
        )
        #expect(data == Data(#"{"claudeAiOauth":{"accessToken":"tok"}}"#.utf8))
        let args = try String(contentsOf: fake.log, encoding: .utf8)
        #expect(args == "find-generic-password\n-s\nClaude Code-credentials-abc\n-a\ndmitry\n-w\n")
    }

    @Test("omits -a for an item without an account")
    func omitsEmptyAccount() throws {
        let fake = try fakeSecurity("echo secret")
        #expect(KeychainTokenReader.readPassword(service: "svc", account: "", tool: fake.tool)
            == Data("secret".utf8))
        let args = try String(contentsOf: fake.log, encoding: .utf8)
        #expect(args == "find-generic-password\n-s\nsvc\n-w\n")
    }

    @Test("returns nil when security fails or is missing")
    func failure() throws {
        let fake = try fakeSecurity("exit 44")
        #expect(KeychainTokenReader.readPassword(service: "svc", account: "a", tool: fake.tool) == nil)
        let missing = URL(fileURLWithPath: "/nonexistent/security")
        #expect(KeychainTokenReader.readPassword(service: "svc", account: "a", tool: missing) == nil)
    }

    @Test("decodes hex output for non-printable secrets")
    func decodesHex() {
        let json = Data(#"{"k":"é"}"#.utf8)
        let hex = json.map { String(format: "%02x", $0) }.joined() + "\n"
        #expect(KeychainTokenReader.decodePasswordOutput(Data(hex.utf8)) == json)
        #expect(KeychainTokenReader.decodePasswordOutput(Data("\n".utf8)) == nil)
    }
}
