import Foundation
import UsageCore

enum WriteCommand {
    static func run(accountIdFlag: String?) {
        guard (try? FileManager.default.createDirectory(
            at: HelperPaths.usageDirectory(), withIntermediateDirectories: true
        )) != nil else { return }
        guard let accountId = try? AccountEnumeration.resolveAccountId(explicit: accountIdFlag),
              let usageURL = try? HelperPaths.usageURL(accountId: accountId) else { return }

        let now = Date()
        let fm = FileManager.default
        if fm.fileExists(atPath: usageURL.path),
           let mtime = (try? fm.attributesOfItem(atPath: usageURL.path))?[.modificationDate] as? Date,
           now.timeIntervalSince(mtime) < PollPolicy.writeMinInterval { return }

        let input = FileHandle.standardInput.readDataToEndOfFile()
        guard !input.isEmpty,
              let mapped = try? StatuslineUsageMapper.map(
                  data: input, accountId: accountId, observedAt: now
              ) else { return }

        let existing: UsageRecord? = if case .record(let record) = UsageStore.load(from: usageURL) { record } else { nil }
        let record = PollPolicy.prepareStatuslineRecord(mapped: mapped, existing: existing)
        _ = try? UsageCommit.commit(
            record: record,
            to: usageURL,
            minInterval: PollPolicy.writeMinInterval,
            now: now
        )
    }
}
