import Foundation
import Testing
@testable import CodexAppServer

private struct FakeCodexServer: CodexAppServerServing {
    let account: CodexAccountReadResult
    let limits: CodexRateLimitsReadResult

    func readAccount() async throws -> CodexAccountReadResult { account }
    func readRateLimits() async throws -> CodexRateLimitsReadResult { limits }
}

private func validLimits() -> CodexRateLimitsReadResult {
    CodexRateLimitsReadResult(
        rateLimits: CodexRateLimitBucket(
            limitId: "codex",
            primary: CodexRateLimitWindow(
                usedPercent: 1,
                windowDurationMins: 300,
                resetsAt: 2_000
            ),
            secondary: nil,
            planType: "plus"
        ),
        rateLimitsByLimitId: nil
    )
}

@Suite("CodexDiscoveryTests")
struct CodexDiscoveryTests {
    @Test("PATH order wins and the result is absolute")
    func pathOrder() throws {
        let root = FileManager.default.temporaryDirectory
            .appending(path: "codex-locator-\(UUID().uuidString)")
        let first = root.appending(path: "first")
        let second = root.appending(path: "second")
        try FileManager.default.createDirectory(at: first, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: second, withIntermediateDirectories: true)
        for directory in [first, second] {
            let executable = directory.appending(path: "codex")
            try Data("#!/bin/sh\n".utf8).write(to: executable)
            try FileManager.default.setAttributes(
                [.posixPermissions: 0o700],
                ofItemAtPath: executable.path
            )
        }

        let located = CodexExecutableLocator.locate(
            environment: ["PATH": "\(first.path):\(second.path)"],
            fallbackDirectories: []
        )
        #expect(located == first.appending(path: "codex").resolvingSymlinksInPath())
    }

    @Test("compatible ChatGPT account becomes ready")
    func ready() async {
        let executable = URL(fileURLWithPath: "/opt/homebrew/bin/codex")
        let server = FakeCodexServer(
            account: CodexAccountReadResult(
                account: CodexAccountInfo(type: "chatgpt", planType: "plus")
            ),
            limits: validLimits()
        )
        let status = await CodexDiscovery(
            locate: { executable },
            makeClient: { _ in server }
        ).discover()

        #expect(status == .ready(executablePath: executable.path))
    }

    @Test("missing and unsupported accounts are distinct")
    func nonReadyStates() async {
        #expect(await CodexDiscovery(
            locate: { nil },
            makeClient: { _ in FakeCodexServer(
                account: CodexAccountReadResult(account: nil),
                limits: validLimits()
            ) }
        ).discover() == .notInstalled)

        let apiKeyServer = FakeCodexServer(
            account: CodexAccountReadResult(account: CodexAccountInfo(type: "apiKey")),
            limits: validLimits()
        )
        let signedOutServer = FakeCodexServer(
            account: CodexAccountReadResult(account: nil),
            limits: validLimits()
        )
        #expect(await CodexDiscovery(
            locate: { URL(fileURLWithPath: "/usr/local/bin/codex") },
            makeClient: { _ in signedOutServer }
        ).discover() == .signInRequired)
        #expect(await CodexDiscovery(
            locate: { URL(fileURLWithPath: "/usr/local/bin/codex") },
            makeClient: { _ in apiKeyServer }
        ).discover() == .signInRequired)
    }

    @Test("authenticated account without the main bucket is unavailable")
    func missingMainBucket() async {
        let server = FakeCodexServer(
            account: CodexAccountReadResult(
                account: CodexAccountInfo(type: "chatgpt")
            ),
            limits: CodexRateLimitsReadResult(
                rateLimits: nil,
                rateLimitsByLimitId: ["spark": CodexRateLimitBucket(
                    limitId: "spark",
                    primary: nil,
                    secondary: nil,
                    planType: nil
                )]
            )
        )
        #expect(await CodexDiscovery(
            locate: { URL(fileURLWithPath: "/usr/local/bin/codex") },
            makeClient: { _ in server }
        ).discover() == .unavailable(message: "Rate limits are unavailable."))
    }
}
