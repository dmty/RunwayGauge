import Foundation
#if canImport(Darwin)
import Darwin
#endif

public enum UsageCommitError: Error, Equatable {
    case missingAccountId
    case invalidAccountId(String)
    case filenameMismatch(expected: String, actual: String)
    case lockFailed
    case writeFailed
}

/// Locked, atomic, write-if-newer commit. Port of `scripts/lib/usage-commit.sh`.
public enum UsageCommit {
    /// Returns `true` when written; `false` on soft policy reject.
    public static func commit(
        record: UsageRecord,
        to url: URL,
        minInterval: TimeInterval = 0,
        fileManager: FileManager = .default,
        now: Date = Date()
    ) throws -> Bool {
        guard let accountId = record.accountId else {
            throw UsageCommitError.missingAccountId
        }
        do {
            try AccountValidation.validateID(accountId)
        } catch {
            throw UsageCommitError.invalidAccountId(accountId)
        }

        let expectedName = "usage-\(accountId).json"
        guard url.lastPathComponent == expectedName else {
            throw UsageCommitError.filenameMismatch(
                expected: expectedName,
                actual: url.lastPathComponent
            )
        }

        try fileManager.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        let lock = try ExclusiveFileLock(
            url: URL(fileURLWithPath: url.path + ".lock"),
            fileManager: fileManager
        )
        defer { lock.unlock() }

        if fileManager.fileExists(atPath: url.path) {
            guard case .record(let existing) = UsageStore.load(from: url),
                  existing.accountId == accountId,
                  !(record.windows.isEmpty && !existing.windows.isEmpty) else {
                return false
            }

            let isNewerData = record.updatedAt > existing.updatedAt
            // Failed polls keep last-good updatedAt; allow writing when only
            // fetchStatus advanced (same windows + same updatedAt).
            let isFetchStatusOnly =
                !isNewerData
                && record.updatedAt == existing.updatedAt
                && record.windows == existing.windows
                && record.fetchStatus != nil
                && (existing.fetchStatus.map { record.fetchStatus!.updatedAt > $0.updatedAt } ?? true)

            guard isNewerData || isFetchStatusOnly else {
                return false
            }

            if isNewerData,
               minInterval > 0,
               let mtime = (try? fileManager.attributesOfItem(atPath: url.path))?[.modificationDate] as? Date,
               now.timeIntervalSince(mtime) < minInterval,
               mtime < record.updatedAt {
                return false
            }
        }

        let data = try UsageRecord.encode(record)
        let tempURL = url.deletingLastPathComponent().appendingPathComponent(
            ".\(url.lastPathComponent).tmp.\(UUID().uuidString)"
        )
        do {
            try data.write(to: tempURL, options: .atomic)
            guard rename(tempURL.path, url.path) == 0 else {
                try? fileManager.removeItem(at: tempURL)
                throw UsageCommitError.writeFailed
            }
        } catch let error as UsageCommitError {
            throw error
        } catch {
            try? fileManager.removeItem(at: tempURL)
            throw UsageCommitError.writeFailed
        }

        return true
    }
}

#if canImport(Darwin)
// ponytail: fcntl flock on sidecar .lock; per-account locks if shell+Swift contention grows
private final class ExclusiveFileLock {
    private let handle: FileHandle
    private var locked = false

    init(url: URL, fileManager: FileManager) throws {
        if !fileManager.fileExists(atPath: url.path),
           !fileManager.createFile(atPath: url.path, contents: nil) {
            throw UsageCommitError.lockFailed
        }
        do {
            handle = try FileHandle(forWritingTo: url)
        } catch {
            throw UsageCommitError.lockFailed
        }
        var lock = Self.flock(F_WRLCK)
        if fcntl(handle.fileDescriptor, F_SETLKW, &lock) != 0 {
            try? handle.close()
            throw UsageCommitError.lockFailed
        }
        locked = true
    }

    func unlock() {
        guard locked else { return }
        var lock = Self.flock(F_UNLCK)
        _ = fcntl(handle.fileDescriptor, F_SETLK, &lock)
        try? handle.close()
        locked = false
    }

    deinit { unlock() }

    private static func flock(_ type: Int32) -> Darwin.flock {
        Darwin.flock(l_start: 0, l_len: 0, l_pid: 0, l_type: Int16(type), l_whence: Int16(SEEK_SET))
    }
}
#else
private final class ExclusiveFileLock {
    init(url: URL, fileManager: FileManager) throws {}
    func unlock() {}
}
#endif
