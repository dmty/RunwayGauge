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

/// Locked, atomic, write-if-newer commit for one account usage record.
///
/// Port of `scripts/lib/usage-commit.sh`.
public enum UsageCommit {
    /// Commits `record` to `url` if it is newer / allowed.
    /// - Returns: `true` when the file was replaced or created; `false` when a
    ///   soft policy reject applied (stale `updatedAt`, empty overwrite, or
    ///   `minInterval`).
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

        let lockURL = URL(fileURLWithPath: url.path + ".lock")
        let lock = try ExclusiveFileLock(url: lockURL, fileManager: fileManager)
        defer { lock.unlock() }

        if fileManager.fileExists(atPath: url.path) {
            guard case .record(let existing) = UsageStore.load(from: url) else {
                return false
            }
            guard existing.accountId == accountId else {
                return false
            }
            guard record.updatedAt.timeIntervalSince1970 > existing.updatedAt.timeIntervalSince1970
            else {
                return false
            }
            if record.windows.isEmpty, !existing.windows.isEmpty {
                return false
            }
            if minInterval > 0,
               let modifiedAt = modificationDate(of: url, fileManager: fileManager) {
                let age = now.timeIntervalSince(modifiedAt)
                let candidateTime = record.updatedAt.timeIntervalSince1970
                let modifiedTime = modifiedAt.timeIntervalSince1970
                if age < minInterval, modifiedTime < candidateTime {
                    return false
                }
            }
        }

        let data = try UsageRecord.encode(record)
        let tempURL = url.deletingLastPathComponent().appendingPathComponent(
            ".\(url.lastPathComponent).tmp.\(UUID().uuidString)"
        )
        do {
            try data.write(to: tempURL, options: .atomic)
            // Same-directory rename is atomic on APFS/HFS+.
            if rename(tempURL.path, url.path) != 0 {
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

    private static func modificationDate(
        of url: URL,
        fileManager: FileManager
    ) -> Date? {
        let attrs = try? fileManager.attributesOfItem(atPath: url.path)
        return attrs?[.modificationDate] as? Date
    }
}

#if canImport(Darwin)
/// Exclusive `fcntl` lock on `usage-….json.lock` for parity with `lockf` in shell.
private final class ExclusiveFileLock {
    private let handle: FileHandle
    private var locked = false

    init(url: URL, fileManager: FileManager) throws {
        if !fileManager.fileExists(atPath: url.path) {
            guard fileManager.createFile(atPath: url.path, contents: nil) else {
                throw UsageCommitError.lockFailed
            }
        }
        do {
            handle = try FileHandle(forWritingTo: url)
        } catch {
            throw UsageCommitError.lockFailed
        }

        var lock = Darwin.flock()
        lock.l_start = 0
        lock.l_len = 0
        lock.l_pid = 0
        lock.l_type = Int16(F_WRLCK)
        lock.l_whence = Int16(SEEK_SET)
        if fcntl(handle.fileDescriptor, F_SETLKW, &lock) != 0 {
            try? handle.close()
            throw UsageCommitError.lockFailed
        }
        locked = true
    }

    func unlock() {
        guard locked else { return }
        var lock = Darwin.flock()
        lock.l_start = 0
        lock.l_len = 0
        lock.l_pid = 0
        lock.l_type = Int16(F_UNLCK)
        lock.l_whence = Int16(SEEK_SET)
        _ = fcntl(handle.fileDescriptor, F_SETLK, &lock)
        try? handle.close()
        locked = false
    }

    deinit {
        unlock()
    }
}
#else
private final class ExclusiveFileLock {
    init(url: URL, fileManager: FileManager) throws {}
    func unlock() {}
}
#endif
