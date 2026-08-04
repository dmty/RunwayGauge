import Foundation

public struct UsageWindow: Sendable, Equatable {
    public let id: String
    public let label: String
    public let usedPercent: Double
    public let resetsAt: Date

    public init(id: String, label: String, usedPercent: Double, resetsAt: Date) {
        self.id = id
        self.label = label
        self.usedPercent = usedPercent
        self.resetsAt = resetsAt
    }

    public var level: UsageLevel { UsageLevel(usedPercent: usedPercent) }
}

public struct UsageRecord: Sendable, Equatable {
    public static let currentSchema = 1

    public let source: String
    public let updatedAt: Date
    public let origin: String
    public let windows: [UsageWindow]

    public init(source: String, updatedAt: Date, origin: String, windows: [UsageWindow]) {
        self.source = source
        self.updatedAt = updatedAt
        self.origin = origin
        self.windows = windows
    }
}

public enum UsageDecodeError: Error, Equatable {
    case unsupportedSchema(Int)
    case malformed
}

extension UsageRecord {
    private struct DTO: Decodable {
        struct Window: Decodable {
            let id: String
            let label: String
            let usedPercent: Double
            let resetsAt: Double

            func asUsageWindow() -> UsageWindow {
                UsageWindow(
                    id: id,
                    label: label,
                    usedPercent: usedPercent,
                    resetsAt: Date(timeIntervalSince1970: resetsAt)
                )
            }
        }
        let schema: Int
        let source: String
        let updatedAt: Double
        let origin: String
        let windows: [Window]

        func asUsageRecord() -> UsageRecord {
            UsageRecord(
                source: source,
                updatedAt: Date(timeIntervalSince1970: updatedAt),
                origin: origin,
                windows: windows.map { $0.asUsageWindow() }
            )
        }
    }

    public static func decode(_ data: Data) throws -> UsageRecord {
        // Schema is read first and separately: an unknown schema must be reported as
        // such even when the rest of the payload no longer matches this DTO.
        if let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let schema = object["schema"] as? Int,
           schema != currentSchema {
            throw UsageDecodeError.unsupportedSchema(schema)
        }

        guard let dto = try? JSONDecoder().decode(DTO.self, from: data) else {
            throw UsageDecodeError.malformed
        }
        guard dto.schema == currentSchema else {
            throw UsageDecodeError.unsupportedSchema(dto.schema)
        }

        return dto.asUsageRecord()
    }
}
