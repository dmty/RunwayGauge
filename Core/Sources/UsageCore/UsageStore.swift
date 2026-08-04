import Foundation
#if canImport(Darwin)
import Darwin
#endif

public enum UsageLoadResult: Sendable, Equatable {
    case record(UsageRecord)
    case missing
    case unreadable
}

public enum WidgetState: Sendable, Equatable {
    case empty
    case unreadable(path: String)
    case data(record: UsageRecord, freshness: Freshness)
}

public struct UsageStore: Sendable {
    private static let widgetContainerID = "com.mirabilia.MacUsageWidget.UsageWidget"
    private static let appSupportRelativePath = "Library/Application Support/MacUsageWidget"
    private static let containersMarker = "/Library/Containers/"
    private static let widgetContainerDataMarker =
        "\(containersMarker)\(widgetContainerID)/Data"
    private static let containerRelativePath =
        "Library/Containers/\(widgetContainerID)/Data/\(appSupportRelativePath)"

    private static func realUserHome() -> URL {
        #if os(macOS) || os(iOS) || os(tvOS) || os(watchOS)
        if let passwd = getpwuid(getuid()) {
            return URL(fileURLWithPath: String(cString: passwd.pointee.pw_dir))
        }
        #endif
        return FileManager.default.homeDirectoryForCurrentUser
    }

    private static func isWidgetExtensionContainerHome(_ home: URL) -> Bool {
        home.path.contains(widgetContainerDataMarker)
    }

    private static func realHomePrefix(from home: URL) -> URL {
        guard let range = home.path.range(of: containersMarker) else { return home }
        return URL(fileURLWithPath: String(home.path[..<range.lowerBound]))
    }

    public static func defaultDirectory(
        home: URL? = nil
    ) -> URL {
        let resolved = home ?? realUserHome()
        if isWidgetExtensionContainerHome(resolved) {
            return resolved.appending(path: appSupportRelativePath)
        }
        return realHomePrefix(from: resolved).appending(path: containerRelativePath)
    }

    public static func url(
        source: String,
        home: URL? = nil
    ) -> URL {
        defaultDirectory(home: home).appending(path: "\(source).json")
    }

    public static func load(from url: URL) -> UsageLoadResult {
        guard let data = try? Data(contentsOf: url) else { return .missing }
        guard let record = try? UsageRecord.decode(data) else { return .unreadable }
        return .record(record)
    }

    public static func state(for result: UsageLoadResult, now: Date, path: String) -> WidgetState {
        switch result {
        case .missing:
            return .empty
        case .unreadable:
            return .unreadable(path: path)
        case .record(let record):
            guard !record.windows.isEmpty else { return .empty }
            return .data(record: record, freshness: Freshness.evaluate(record, now: now))
        }
    }
}
