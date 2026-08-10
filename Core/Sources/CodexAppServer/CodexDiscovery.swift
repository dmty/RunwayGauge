import Foundation

public enum CodexDiscoveryStatus: Equatable, Sendable {
    case ready(executablePath: String)
    case notInstalled
    case signInRequired
    case unavailable(message: String)

    public var settingsText: String {
        switch self {
        case .ready: "Codex ready"
        case .notInstalled: "Codex not installed"
        case .signInRequired: "Sign in to Codex"
        case .unavailable(let message): "Codex unavailable — \(message)"
        }
    }
}

public enum CodexExecutableLocator {
    public static func locate(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        fallbackDirectories: [String] = ["/opt/homebrew/bin", "/usr/local/bin"]
    ) -> URL? {
        let pathDirectories = (environment["PATH"] ?? "")
            .split(separator: ":", omittingEmptySubsequences: true)
            .map(String.init)
        var seen = Set<String>()
        for directory in pathDirectories + fallbackDirectories {
            let candidate = URL(fileURLWithPath: directory, isDirectory: true)
                .appending(path: "codex")
                .resolvingSymlinksInPath()
                .standardizedFileURL
            guard seen.insert(candidate.path).inserted else { continue }
            guard FileManager.default.isExecutableFile(atPath: candidate.path) else { continue }
            return candidate
        }
        return nil
    }
}

public struct CodexDiscovery: Sendable {
    private let locate: @Sendable () -> URL?
    private let makeClient: @Sendable (URL) -> any CodexAppServerServing

    public init(
        locate: @escaping @Sendable () -> URL? = {
            CodexExecutableLocator.locate()
        },
        makeClient: @escaping @Sendable (URL) -> any CodexAppServerServing = {
            CodexAppServerClient(executableURL: $0)
        }
    ) {
        self.locate = locate
        self.makeClient = makeClient
    }

    public func discover() async -> CodexDiscoveryStatus {
        guard let executable = locate() else { return .notInstalled }
        let client = makeClient(executable)
        do {
            let account = try await client.readAccount()
            guard account.account?.type == "chatgpt" else {
                return .signInRequired
            }
            let limits = try await client.readRateLimits()
            guard CodexUsageMapper.mainBucket(in: limits) != nil else {
                return .unavailable(message: "Rate limits are unavailable.")
            }
            return .ready(executablePath: executable.path)
        } catch let error as CodexAppServerError {
            return .unavailable(message: error.userMessage)
        } catch {
            return .unavailable(message: "Codex could not be checked.")
        }
    }
}
