import Darwin
import Foundation

@_silgen_name("flock")
private func systemFlock(_ descriptor: Int32, _ operation: Int32) -> Int32

public enum AccountLoadError: Error, Equatable {
    case missing
    case unreadable
}

public enum AccountStoreError: Error, Equatable {
    case lockUnavailable(Int32)
    case revisionOverflow
    case atomicReplaceFailed(Int32)
}

public struct AccountStore: Sendable {
    public static let legacyUsageArchiveName = "claude-code.legacy.json"
    public static let legacyUsageArchivePendingName = "claude-code.legacy.pending"

    public static func url(home: URL? = nil) -> URL {
        UsageStore.defaultDirectory(home: home).appending(path: "accounts.json")
    }

    public static func legacyUsageArchiveURL(home: URL? = nil) -> URL {
        UsageStore.defaultDirectory(home: home).appending(path: legacyUsageArchiveName)
    }

    public static func legacyUsageArchivePendingURL(home: URL? = nil) -> URL {
        UsageStore.defaultDirectory(home: home).appending(path: legacyUsageArchivePendingName)
    }

    public static func hasLegacyUsageWarning(home: URL? = nil) -> Bool {
        FileManager.default.fileExists(atPath: url(home: home).path)
            && FileManager.default.fileExists(atPath: UsageStore.url(source: "claude-code", home: home).path)
    }

    public static func load(from url: URL) throws -> AccountRegistry {
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw AccountLoadError.missing
        }
        guard let data = try? Data(contentsOf: url) else {
            throw AccountLoadError.unreadable
        }
        do {
            return try AccountRegistry.decode(data)
        } catch {
            throw AccountLoadError.unreadable
        }
    }

    /// Loads and repairs an in-memory copy. The registry file is never rewritten.
    public static func loadValidated(
        from url: URL,
        home: URL? = nil
    ) throws -> AccountRegistry {
        var registry = try load(from: url)
        try AccountValidation.validateAndRepair(&registry, home: home)
        return registry
    }

    internal static func save(_ registry: AccountRegistry, to url: URL) throws {
        let data = try AccountRegistry.encode(registry)
        try data.write(to: url, options: .atomic)
    }

    public static func mutate(
        at url: URL,
        _ body: (inout AccountRegistry) throws -> Void
    ) throws -> AccountRegistry {
        try withLock(at: url) {
            var registry: AccountRegistry
            if FileManager.default.fileExists(atPath: url.path) {
                registry = try load(from: url)
            } else {
                registry = emptyRegistry()
            }
            let loadedRevision = registry.revision

            try body(&registry)
            try AccountValidation.validateAndRepair(&registry)
            let (nextRevision, overflow) = loadedRevision.addingReportingOverflow(1)
            guard !overflow else {
                throw AccountStoreError.revisionOverflow
            }
            registry.revision = nextRevision

            try atomicSave(registry, to: url)
            return registry
        }
    }

    public static func bootstrapIfMissing(
        home: URL? = nil,
        discovered: [DiscoveredAccount]
    ) throws -> AccountRegistry {
        let registryURL = url(home: home)
        return try withLock(at: registryURL) {
            let registry: AccountRegistry
            if FileManager.default.fileExists(atPath: registryURL.path) {
                registry = try load(from: registryURL)
                try recoverInterruptedLegacyArchive(home: home)
            } else {
                var created = discoveredRegistry(from: discovered, home: home)
                try AccountValidation.validateAndRepair(&created, home: home)
                created.revision = 1
                let legacy = UsageStore.url(source: "claude-code", home: home)
                let shouldArchive = FileManager.default.fileExists(atPath: legacy.path)
                    && !FileManager.default.fileExists(atPath: legacyUsageArchiveURL(home: home).path)
                if shouldArchive {
                    try writeLegacyArchivePending(home: home)
                }
                try atomicSave(created, to: registryURL)
                if shouldArchive {
                    try completeLegacyArchive(home: home)
                }
                registry = created
            }

            return registry
        }
    }

    private static func writeLegacyArchivePending(home: URL?) throws {
        let pending = legacyUsageArchivePendingURL(home: home)
        guard !FileManager.default.fileExists(atPath: pending.path) else { return }
        try Data().write(to: pending)
    }

    private static func completeLegacyArchive(home: URL?) throws {
        let legacy = UsageStore.url(source: "claude-code", home: home)
        let archive = legacyUsageArchiveURL(home: home)
        let pending = legacyUsageArchivePendingURL(home: home)
        guard FileManager.default.fileExists(atPath: legacy.path),
              !FileManager.default.fileExists(atPath: archive.path) else { return }
        try FileManager.default.moveItem(at: legacy, to: archive)
        try? FileManager.default.removeItem(at: pending)
    }

    private static func recoverInterruptedLegacyArchive(home: URL?) throws {
        let pending = legacyUsageArchivePendingURL(home: home)
        guard FileManager.default.fileExists(atPath: pending.path) else { return }
        let archive = legacyUsageArchiveURL(home: home)
        if FileManager.default.fileExists(atPath: archive.path) {
            try? FileManager.default.removeItem(at: pending)
            return
        }
        try completeLegacyArchive(home: home)
    }

    private static func withLock<T>(
        at url: URL,
        _ body: () throws -> T
    ) throws -> T {
        let directory = url.deletingLastPathComponent()
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )

        let lockURL = directory.appending(path: url.lastPathComponent + ".lock")
        let descriptor = Darwin.open(
            lockURL.path,
            O_CREAT | O_RDWR,
            S_IRUSR | S_IWUSR
        )
        guard descriptor >= 0 else {
            throw AccountStoreError.lockUnavailable(errno)
        }
        defer { Darwin.close(descriptor) }

        while systemFlock(descriptor, LOCK_EX) != 0 {
            guard errno == EINTR else {
                throw AccountStoreError.lockUnavailable(errno)
            }
        }
        defer { _ = systemFlock(descriptor, LOCK_UN) }

        return try body()
    }

    private static func atomicSave(_ registry: AccountRegistry, to url: URL) throws {
        let directory = url.deletingLastPathComponent()
        let data = try AccountRegistry.encode(registry)
        let temporaryURL = directory.appending(
            path: ".\(url.lastPathComponent).\(UUID().uuidString).tmp"
        )
        defer { try? FileManager.default.removeItem(at: temporaryURL) }
        try data.write(to: temporaryURL)

        guard Darwin.rename(temporaryURL.path, url.path) == 0 else {
            throw AccountStoreError.atomicReplaceFailed(errno)
        }
    }

    private static func emptyRegistry() -> AccountRegistry {
        AccountRegistry(
            revision: 0,
            prefs: AccountPreferences(),
            accounts: []
        )
    }

    private static func discoveredRegistry(
        from discovered: [DiscoveredAccount],
        home: URL?
    ) -> AccountRegistry {
        var accounts: [Account] = []
        for item in discovered {
            var trial = AccountRegistry(
                revision: 0,
                prefs: AccountPreferences(),
                accounts: accounts + [Account(
                    id: "acc_\(UUID().uuidString)",
                    label: item.label,
                    sourceKind: item.sourceKind,
                    pinned: false,
                    credentials: item.credentials
                )]
            )
            guard (try? AccountValidation.validateAndRepair(&trial, home: home)) != nil else { continue }
            let candidate = trial.accounts.last! // ponytail: validated trial always has the new account last
            guard !accounts.contains(where: {
                $0.label == candidate.label && $0.sourceKind == candidate.sourceKind && $0.credentials == candidate.credentials
            }) else { continue }
            accounts.append(candidate)
        }

        let pinIndex = accounts.firstIndex {
            $0.sourceKind == .claudeOAuth && ($0.credentials.configDir != nil || AccountValidation.isPollCapable($0))
        }
        if let pinIndex { accounts[pinIndex].pinned = true }
        return AccountRegistry(
            revision: 0,
            prefs: AccountPreferences(selectedAccountId: pinIndex.map { accounts[$0].id }),
            accounts: accounts
        )
    }
}
