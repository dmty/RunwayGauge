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

@Suite("CodexAppServerClientTests", .serialized)
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

    @Test("timely response wins when shutdown races the deadline")
    func timelyResponseWinsShutdownRace() async throws {
        // TERM-resistant + grace > timeout: stop()-before-tryComplete lets the deadline
        // fire mid-shutdown and steal a timely success.
        let directory = FileManager.default.temporaryDirectory
            .appending(path: "codex-app-server-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let server = directory.appending(path: "server.py")
        try Data("""
        #!/usr/bin/env python3
        import os, signal, sys, time
        signal.signal(signal.SIGTERM, signal.SIG_IGN)
        for line in sys.stdin:
            if '"method":"initialize"' in line:
                print('{"id":0,"result":{}}', flush=True)
            elif '"method":"account/read"' in line:
                print('{"id":1,"result":{"account":{"type":"chatgpt","planType":"plus"}}}', flush=True)
                while True:
                    time.sleep(1)
        """.utf8).write(to: server)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: server.path)
        let script = directory.appending(path: "codex")
        try Data("""
        #!/bin/sh
        test "$1" = "app-server" || exit 64
        exec "$(dirname "$0")/server.py"
        """.utf8).write(to: script)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: script.path)

        let result = try await CodexAppServerClient(
            executableURL: script,
            timeoutSeconds: 2.0,
            shutdownGraceSeconds: 2.5
        ).readAccount()
        #expect(result.account == CodexAccountInfo(type: "chatgpt", planType: "plus"))
    }

    @Test("deadline arbitration discards late success")
    func deadlineArbitration() {
        final class Events: @unchecked Sendable {
            private let lock = NSLock()
            private var values: [String] = []
            func append(_ value: String) {
                lock.lock(); values.append(value); lock.unlock()
            }
            var snapshot: [String] {
                lock.lock(); defer { lock.unlock() }; return values
            }
        }
        let events = Events()
        let gate = OperationDeadline(timeoutSeconds: 0.05) {
            events.append("timeout")
        }
        Thread.sleep(forTimeInterval: 0.08)
        let won = gate.tryComplete()
        events.append(won ? "success" : "discarded")
        #expect(won == false)
        #expect(gate.timedOut)
        #expect(events.snapshot == ["timeout", "discarded"])
    }

    @Test("late fixture response loses to the deadline")
    func lateResponseTimedOut() async throws {
        let script = try makeServerScript(body: #"""
        sleep 0.2
        printf '%s\n' '{"id":0,"result":{}}'
        IFS= read -r _
        IFS= read -r _
        printf '%s\n' '{"id":1,"result":{"account":{"type":"chatgpt","planType":"plus"}}}'
        """#)
        await #expect(throws: CodexAppServerError.timedOut) {
            try await CodexAppServerClient(
                executableURL: script,
                timeoutSeconds: 0.05,
                shutdownGraceSeconds: 0.05
            ).readAccount()
        }
    }

    @Test("timeout waits until TERM-resistant child is gone")
    func stopWaitsForTermResistantChild() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: "codex-app-server-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let server = directory.appending(path: "hang.py")
        try Data("""
        #!/usr/bin/env python3
        import signal, time
        signal.signal(signal.SIGTERM, signal.SIG_IGN)
        while True:
            time.sleep(1)
        """.utf8).write(to: server)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: server.path)
        let script = directory.appending(path: "codex")
        try Data("""
        #!/bin/sh
        test "$1" = "app-server" || exit 64
        exec "$(dirname "$0")/hang.py"
        """.utf8).write(to: script)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: script.path)

        let marker = directory.lastPathComponent
        // timeout >> python startup so SIGTERM is ignored before stop()'s terminate()
        let client = CodexAppServerClient(
            executableURL: script,
            timeoutSeconds: 0.5,
            shutdownGraceSeconds: 0.25
        )
        let started = Date()
        await #expect(throws: CodexAppServerError.timedOut) {
            try await client.readAccount()
        }
        // Deadline floor; SIGKILL/reap timing varies, so liveness is asserted via pgrep below.
        #expect(Date().timeIntervalSince(started) >= 0.5)
        let probe = Process()
        probe.executableURL = URL(fileURLWithPath: "/usr/bin/pgrep")
        probe.arguments = ["-f", marker]
        let sink = Pipe()
        probe.standardOutput = sink
        probe.standardError = sink
        try probe.run()
        probe.waitUntilExit()
        #expect(probe.terminationStatus == 1)
    }

    @Test("rateLimits/read omits params in emitted JSONL")
    func rateLimitsOmitsParams() async throws {
        let script = try makeServerScript(body: #"""
        log="${0}.log"
        while IFS= read -r line; do
          printf '%s\n' "$line" >> "$log"
          case "$line" in
            *'"method":"initialize"'*)
              printf '%s\n' '{"id":0,"result":{}}'
              ;;
            *'"method":"account/rateLimits/read"'*)
              printf '%s\n' '{"id":1,"result":{"rateLimits":{"limitId":"codex","primary":{"usedPercent":1,"windowDurationMins":300,"resetsAt":2000},"secondary":null,"planType":"plus"},"rateLimitsByLimitId":null}}'
              ;;
          esac
        done
        """#)
        _ = try await CodexAppServerClient(executableURL: script).readRateLimits()
        let log = try String(contentsOfFile: script.path + ".log", encoding: .utf8)
        let rateLimitLine = log.split(separator: "\n").first {
            $0.contains(#""method":"account/rateLimits/read""#)
        }
        #expect(rateLimitLine == #"{"id":1,"method":"account/rateLimits/read"}"#)
        #expect(!log.contains(#""params":null"#))
    }

    @Test("schema-incompatible result is malformedResponse")
    func schemaIncompatibleResult() async throws {
        let script = try makeServerScript(body: #"""
        while IFS= read -r line; do
          case "$line" in
            *'"method":"initialize"'*)
              printf '%s\n' '{"id":0,"result":{}}'
              ;;
            *'"method":"account/read"'*)
              printf '%s\n' '{"id":1,"result":{"account":"not-an-object"}}'
              ;;
          esac
        done
        """#)
        await #expect(throws: CodexAppServerError.malformedResponse) {
            try await CodexAppServerClient(executableURL: script).readAccount()
        }
    }
}
