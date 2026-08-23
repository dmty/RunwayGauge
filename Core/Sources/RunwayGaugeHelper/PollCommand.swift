import Foundation
import UsageCore
import CodexAppServer

enum PollCommand {
    static func run(force: Bool) async {
        guard (try? FileManager.default.createDirectory(
            at: HelperPaths.usageDirectory(), withIntermediateDirectories: true
        )) != nil,
              let targets = try? AccountEnumeration.pollTargets() else { return }

        let now = Date()
        for target in targets {
            guard let usageURL = try? HelperPaths.usageURL(accountId: target.accountId) else {
                continue
            }
            switch target {
            case .claude(
                let accountId,
                _,
                let configDir,
                let keychainService,
                let keychainAccount
            ):
                guard let token = ClaudeTokenResolver.accessToken(
                    configDir: configDir,
                    keychainService: keychainService,
                    keychainAccount: keychainAccount
                ) else { continue }
                _ = await UsagePoller(fetcher: UsageHTTPClient()).poll(
                    accountId: accountId,
                    accessToken: token,
                    usageURL: usageURL,
                    force: force,
                    now: now
                )

            case .codex(let accountId, _, let executablePath):
                let client = CodexAppServerClient(
                    executableURL: URL(fileURLWithPath: executablePath)
                )
                _ = await CodexUsagePoller(client: client).poll(
                    accountId: accountId,
                    usageURL: usageURL,
                    force: force,
                    now: now
                )
            }
        }
    }
}
