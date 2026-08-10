import Foundation

public struct KeychainItemDescriptor: Equatable, Sendable {
    public var service: String
    public var account: String?

    public init(service: String, account: String? = nil) {
        self.service = service
        self.account = account
    }
}

public struct SourceFieldDescriptor: Equatable, Sendable {
    public var key: String
    public var label: String
    public var required: Bool

    public init(key: String, label: String, required: Bool) {
        self.key = key
        self.label = label
        self.required = required
    }
}

public struct DiscoveredAccount: Equatable, Sendable {
    public var label: String
    public var sourceKind: SourceKind
    public var credentials: AccountCredentials

    public init(
        label: String,
        sourceKind: SourceKind,
        credentials: AccountCredentials
    ) {
        self.label = label
        self.sourceKind = sourceKind
        self.credentials = credentials
    }
}

public enum SourceHealth: Equatable, Sendable {
    case ready
    case statuslineOnly(reason: String)
    case pollerOnly(reason: String)
    case unavailable(reason: String)
    case comingSoon
}

public enum UsagePaneModel: Equatable, Sendable {
    case usage(sourceKind: SourceKind, label: String, record: UsageRecord?)
    case unsupported(sourceKind: SourceKind, label: String)
    case comingSoon(sourceKind: SourceKind, label: String)
}

public protocol SourceFileSystem: Sendable {
    func itemExists(at url: URL) -> Bool
    func directoryExists(at url: URL) -> Bool
}

public struct LocalSourceFileSystem: SourceFileSystem {
    public init() {}

    public func itemExists(at url: URL) -> Bool {
        FileManager.default.fileExists(atPath: url.path)
    }

    public func directoryExists(at url: URL) -> Bool {
        var isDirectory = ObjCBool(false)
        return FileManager.default.fileExists(
            atPath: url.path,
            isDirectory: &isDirectory
        ) && isDirectory.boolValue
    }
}

public protocol UsageSource: Sendable {
    var kind: SourceKind { get }
    var displayName: String { get }
    var settingsFields: [SourceFieldDescriptor] { get }
    var presentation: UsageSourcePresentation { get }

    func discover(
        home: URL,
        keychainItems: [KeychainItemDescriptor]
    ) -> [DiscoveredAccount]
    func validate(_ account: Account, fileSystem: any SourceFileSystem) -> SourceHealth
    func paneModel(account: Account, record: UsageRecord?) -> UsagePaneModel
}

public struct UsageSourcePresentation: Equatable, Sendable {
    public let compactHeader: String
    public let emptyMessage: String
    public let supportsSessionNotStarted: Bool

    public init(
        compactHeader: String,
        emptyMessage: String,
        supportsSessionNotStarted: Bool
    ) {
        self.compactHeader = compactHeader
        self.emptyMessage = emptyMessage
        self.supportsSessionNotStarted = supportsSessionNotStarted
    }
}

public extension UsageSource {
    var presentation: UsageSourcePresentation {
        UsageSourcePresentation(
            compactHeader: displayName.uppercased(),
            emptyMessage: "No usage data yet.",
            supportsSessionNotStarted: false
        )
    }
}

public enum SourceCatalog {
    private static let adapters: [any UsageSource] = [
        ClaudeOAuthSource(),
        CodexSource(),
        ComingSoonAPISource.openAI,
        ComingSoonAPISource.anthropic,
    ]

    public static func adapter(for kind: SourceKind) -> (any UsageSource)? {
        adapters.first { $0.kind == kind }
    }

    public static func presentation(for kind: SourceKind) -> UsageSourcePresentation {
        adapter(for: kind)?.presentation ?? UsageSourcePresentation(
            compactHeader: kind.rawValue.uppercased(),
            emptyMessage: "No usage data yet.",
            supportsSessionNotStarted: false
        )
    }

    public static func paneModel(
        for account: Account,
        record: UsageRecord?
    ) -> UsagePaneModel {
        guard let adapter = adapter(for: account.sourceKind) else {
            return .unsupported(sourceKind: account.sourceKind, label: account.label)
        }
        return adapter.paneModel(account: account, record: record)
    }
}
