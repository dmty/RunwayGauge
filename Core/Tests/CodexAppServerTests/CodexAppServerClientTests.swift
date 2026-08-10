import Foundation
import Testing
@testable import CodexAppServer

private func makeServerScript(body: String) throws -> URL {
    let directory = FileManager.default.temporaryDirectory
        .appending(path: "codex-app-server-tests-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let script = directory.appending(path: "codex")
    let source = """
    #!/bin/sh
    test "$1" = "app-server" || exit 64
    \(body)
    """
    try Data(source.utf8).write(to: script)
    try FileManager.default.setAttributes(
        [.posixPermissions: 0o700],
        ofItemAtPath: script.path
    )
    return script
}

@Suite("CodexAppServerClientTests")
struct CodexAppServerClientTests {
    @Test("handshakes before account read and ignores notifications")
    func accountReadHandshake() async throws {
        let script = try makeServerScript(body: #"""
        log="${0}.log"
        while IFS= read -r line; do
          printf '%s\n' "$line" >> "$log"
          case "$line" in
            *'"method":"initialize"'*)
              printf '%s\n' '{"method":"account/updated","params":{}}'
              printf '%s\n' '{"id":0,"result":{"userAgent":"fixture"}}'
              ;;
            *'"method":"account/read"'*)
              printf '%s\n' '{"id":1,"result":{"account":{"type":"chatgpt","planType":"plus"},"requiresOpenaiAuth":true}}'
              ;;
          esac
        done
        """#)
        let client = CodexAppServerClient(executableURL: script)

        let result = try await client.readAccount()
        let log = try String(contentsOfFile: script.path + ".log", encoding: .utf8)

        #expect(result.account == CodexAccountInfo(type: "chatgpt", planType: "plus"))
        #expect(log.range(of: #""method":"initialize""#)!.lowerBound
            < log.range(of: #""method":"initialized""#)!.lowerBound)
        #expect(log.range(of: #""method":"initialized""#)!.lowerBound
            < log.range(of: #""method":"account/read""#)!.lowerBound)
        #expect(!log.contains("refreshToken\":true"))
    }

    @Test("correlates the rate-limit request id")
    func rateLimitCorrelation() async throws {
        let script = try makeServerScript(body: #"""
        while IFS= read -r line; do
          case "$line" in
            *'"method":"initialize"'*)
              printf '%s\n' '{"id":99,"result":{"ignored":true}}'
              printf '%s\n' '{"id":0,"result":{}}'
              ;;
            *'"method":"account/rateLimits/read"'*)
              printf '%s\n' '{"id":98,"result":{"rateLimits":null}}'
              printf '%s\n' '{"id":1,"method":"fixture/request","params":{}}'
              printf '%s\n' '{"id":1,"result":{"rateLimits":{"limitId":"codex","primary":{"usedPercent":12,"windowDurationMins":300,"resetsAt":2000},"secondary":null,"planType":"plus"},"rateLimitsByLimitId":null}}'
              ;;
          esac
        done
        """#)

        let result = try await CodexAppServerClient(
            executableURL: script
        ).readRateLimits()

        #expect(result.rateLimits?.limitId == "codex")
        #expect(result.rateLimits?.primary?.usedPercent == 12)
    }

    @Test("timeout terminates a non-responsive child")
    func timeout() async throws {
        let script = try makeServerScript(body: "exec sleep 30")
        let client = CodexAppServerClient(
            executableURL: script,
            timeoutSeconds: 0.1,
            shutdownGraceSeconds: 0.05
        )

        await #expect(throws: CodexAppServerError.timedOut) {
            try await client.readAccount()
        }
    }

    @Test("diagnostics are bounded to eight KiB")
    func diagnosticCap() {
        var diagnostics = CodexDiagnosticAccumulator(limit: 8 * 1_024)
        diagnostics.append(Data(repeating: 65, count: 20_000))
        #expect(diagnostics.data.count == 8 * 1_024)
    }

    @Test("malformed JSONL is a typed protocol failure")
    func malformedJSONL() async throws {
        let script = try makeServerScript(body: "printf '%s\\n' 'not-json'")
        await #expect(throws: CodexAppServerError.malformedResponse) {
            try await CodexAppServerClient(executableURL: script).readAccount()
        }
    }

    @Test("early child exit is distinct from timeout")
    func earlyExit() async throws {
        let script = try makeServerScript(body: "exit 0")
        await #expect(throws: CodexAppServerError.exitedEarly) {
            try await CodexAppServerClient(executableURL: script).readAccount()
        }
    }

    @Test("RPC errors retain only the numeric code")
    func rpcError() async throws {
        let script = try makeServerScript(body: #"""
        IFS= read -r line
        printf '%s\n' '{"id":0,"error":{"code":-32601,"message":"unsupported fixture detail"}}'
        """#)
        await #expect(throws: CodexAppServerError.rpcError(code: -32601)) {
            try await CodexAppServerClient(executableURL: script).readAccount()
        }
    }
}
