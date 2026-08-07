import Foundation
import UsageCore

enum WriteCommand {
    /// Soft-exit: never throws to caller; statusline must not fail loud.
    static func run(accountIdFlag: String?) {
        do {
            try FileManager.default.createDirectory(
                at: HelperPaths.usageDirectory(),
                withIntermediateDirectories: true
            )
        } catch {
            return
        }

        let accountId: String
        do {
            accountId = try AccountEnumeration.resolveAccountId(explicit: accountIdFlag)
        } catch {
            return
        }

        let usageURL: URL
        do {
            usageURL = try HelperPaths.usageURL(accountId: accountId)
        } catch {
            return
        }

        // Soft min-interval gate before reading stdin (matches shell writer).
        let now = Date()
        if FileManager.default.fileExists(atPath: usageURL.path),
           let mtime = (try? FileManager.default.attributesOfItem(atPath: usageURL.path))?[.modificationDate] as? Date,
           now.timeIntervalSince(mtime) < PollPolicy.writeMinInterval {
            return
        }

        let input = FileHandle.standardInput.readDataToEndOfFile()
        guard !input.isEmpty else { return }

        let mapped: UsageRecord
        do {
            mapped = try StatuslineUsageMapper.map(
                data: input,
                accountId: accountId,
                observedAt: now
            )
        } catch {
            return
        }

        let existing: UsageRecord?
        if case .record(let record) = UsageStore.load(from: usageURL) {
            existing = record
        } else {
            existing = nil
        }

        let record = PollPolicy.prepareStatuslineRecord(mapped: mapped, existing: existing)
        _ = try? UsageCommit.commit(
            record: record,
            to: usageURL,
            minInterval: PollPolicy.writeMinInterval,
            now: now
        )
    }
}
