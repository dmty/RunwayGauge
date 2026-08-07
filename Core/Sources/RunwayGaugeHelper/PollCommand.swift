import Foundation
import UsageCore

enum PollCommand {
    static func run(force: Bool) async {
        guard (try? FileManager.default.createDirectory(
            at: HelperPaths.usageDirectory(), withIntermediateDirectories: true
        )) != nil,
              let targets = try? AccountEnumeration.pollTargets() else { return }

        let poller = UsagePoller(fetcher: UsageHTTPClient())
        let now = Date()
        for target in targets {
            guard let token = KeychainTokenReader.accessToken(
                service: target.keychainService, account: target.keychainAccount
            ), let usageURL = try? HelperPaths.usageURL(accountId: target.accountId) else { continue }
            _ = await poller.poll(
                accountId: target.accountId,
                accessToken: token,
                usageURL: usageURL,
                force: force,
                now: now
            )
        }
    }
}
