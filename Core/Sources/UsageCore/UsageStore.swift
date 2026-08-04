import Foundation

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
    private static let containerRelativePath =
        "Library/Containers/com.mirabilia.MacUsageWidget.UsageWidget/Data/Library/Application Support/MacUsageWidget"

    public static func defaultDirectory(
        home: URL = FileManager.default.homeDirectoryForCurrentUser
    ) -> URL {
        if home.path.contains("/Library/Containers/") {
            return home.appending(path: "Library/Application Support/MacUsageWidget")
        }
        return home.appending(path: containerRelativePath)
    }

    public static func url(
        source: String,
        home: URL = FileManager.default.homeDirectoryForCurrentUser
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
