import Foundation
import UsageCore

enum PollCommand {
    static func run(force: Bool) async {
        do {
            try FileManager.default.createDirectory(
                at: HelperPaths.usageDirectory(),
                withIntermediateDirectories: true
            )
        } catch {
            return
        }

        let targets: [PollTarget]
        do {
            targets = try AccountEnumeration.pollTargets()
        } catch {
            return
        }

        let poller = UsagePoller(fetcher: UsageHTTPClient())
        let now = Date()

        for target in targets {
            guard let token = KeychainTokenReader.accessToken(
                service: target.keychainService,
                account: target.keychainAccount
            ) else {
                continue
            }

            let usageURL: URL
            do {
                usageURL = try HelperPaths.usageURL(accountId: target.accountId)
            } catch {
                continue
            }

            _ = await poller.poll(
                accountId: target.accountId,
                accessToken: token,
                usageURL: usageURL,
                force: force,
                now: now
            )
            // Token drops out of scope each iteration; never logged.
        }
    }
}
