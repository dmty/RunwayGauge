import Foundation

public struct FetchStatus: Sendable, Equatable {
    public enum State: String, Sendable, Equatable, Codable {
        case ok
        case rateLimited
        case failed
    }

    public let state: State
    public let message: String?
    public let retryAfterAt: Date?
    public let httpStatus: Int?
    public let updatedAt: Date

    public init(
        state: State,
        message: String? = nil,
        retryAfterAt: Date? = nil,
        httpStatus: Int? = nil,
        updatedAt: Date
    ) {
        self.state = state
        self.message = message
        self.retryAfterAt = retryAfterAt
        self.httpStatus = httpStatus
        self.updatedAt = updatedAt
    }
}

public struct UsageWindow: Sendable, Equatable {
    public let id: String
    public let label: String
    public let usedPercent: Double
    public let resetsAt: Date
    public let severity: String?
    public let kind: String?

    public init(
        id: String,
        label: String,
        usedPercent: Double,
        resetsAt: Date,
        severity: String? = nil,
        kind: String? = nil
    ) {
        self.id = id
        self.label = label
        self.usedPercent = usedPercent
        self.resetsAt = resetsAt
        self.severity = severity
        self.kind = kind
    }

    /// Percent-only for now; severity-aware display goes through `UsageLevel(usedPercent:severity:)`.
    public var level: UsageLevel { UsageLevel(usedPercent: usedPercent) }
}

public struct UsageRecord: Sendable, Equatable {
    public static let currentSchema = 2

    public let accountId: String?
    public let source: String
    public let updatedAt: Date
    public let origin: String
    public let windows: [UsageWindow]
    public let plan: String?
    public let fetchStatus: FetchStatus?

    public init(
        accountId: String? = nil,
        source: String,
        updatedAt: Date,
        origin: String,
        windows: [UsageWindow],
        plan: String? = nil,
        fetchStatus: FetchStatus? = nil
    ) {
        self.accountId = accountId
        self.source = source
        self.updatedAt = updatedAt
        self.origin = origin
        self.windows = windows
        self.plan = plan
        self.fetchStatus = fetchStatus
    }
}

public enum UsageDecodeError: Error, Equatable {
    case unsupportedSchema(Int)
    case malformed
}

extension UsageRecord {
    private static func isSupportedSchema(_ schema: Int) -> Bool {
        schema == 1 || schema == 2
    }

    private struct DTO: Codable {
        struct FetchStatusDTO: Codable {
            let state: FetchStatus.State
            let message: String?
            let retryAfterAt: Double?
            let httpStatus: Int?
            let updatedAt: Double

            init(from status: FetchStatus) {
                state = status.state
                message = status.message
                retryAfterAt = status.retryAfterAt.map { $0.timeIntervalSince1970 }
                httpStatus = status.httpStatus
                updatedAt = status.updatedAt.timeIntervalSince1970
            }

            func asFetchStatus() -> FetchStatus {
                FetchStatus(
                    state: state,
                    message: message,
                    retryAfterAt: retryAfterAt.map { Date(timeIntervalSince1970: $0) },
                    httpStatus: httpStatus,
                    updatedAt: Date(timeIntervalSince1970: updatedAt)
                )
            }
        }

        struct Window: Codable {
            let id: String
            let label: String
            let usedPercent: Double
            let resetsAt: Double
            let severity: String?
            let kind: String?

            init(from window: UsageWindow) {
                id = window.id
                label = window.label
                usedPercent = window.usedPercent
                resetsAt = window.resetsAt.timeIntervalSince1970
                severity = window.severity
                kind = window.kind
            }

            init(from decoder: Decoder) throws {
                let c = try decoder.container(keyedBy: CodingKeys.self)
                id = try c.decode(String.self, forKey: .id)
                label = try c.decode(String.self, forKey: .label)
                usedPercent = try c.decode(Double.self, forKey: .usedPercent)
                resetsAt = try c.decode(Double.self, forKey: .resetsAt)
                severity = try c.decodeIfPresent(String.self, forKey: .severity)
                kind = try c.decodeIfPresent(String.self, forKey: .kind)
            }

            func asUsageWindow() -> UsageWindow {
                UsageWindow(
                    id: id,
                    label: label,
                    usedPercent: usedPercent,
                    resetsAt: Date(timeIntervalSince1970: resetsAt),
                    severity: severity,
                    kind: kind
                )
            }
        }

        let schema: Int
        let accountId: String?
        let source: String
        let updatedAt: Double
        let origin: String
        let windows: [Window]
        let plan: String?
        let fetchStatus: FetchStatusDTO?

        init(from record: UsageRecord) {
            schema = UsageRecord.currentSchema
            accountId = record.accountId
            source = record.source
            updatedAt = record.updatedAt.timeIntervalSince1970
            origin = record.origin
            windows = record.windows.map(Window.init(from:))
            plan = record.plan
            fetchStatus = record.fetchStatus.map(FetchStatusDTO.init(from:))
        }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            schema = try c.decode(Int.self, forKey: .schema)
            accountId = try c.decodeIfPresent(String.self, forKey: .accountId)
            source = try c.decode(String.self, forKey: .source)
            updatedAt = try c.decode(Double.self, forKey: .updatedAt)
            origin = try c.decode(String.self, forKey: .origin)
            windows = try c.decode([Window].self, forKey: .windows)
            plan = try c.decodeIfPresent(String.self, forKey: .plan)
            fetchStatus = try c.decodeIfPresent(FetchStatusDTO.self, forKey: .fetchStatus)
        }

        func asUsageRecord() -> UsageRecord {
            UsageRecord(
                accountId: accountId,
                source: source,
                updatedAt: Date(timeIntervalSince1970: updatedAt),
                origin: origin,
                windows: windows.map { $0.asUsageWindow() },
                plan: plan,
                fetchStatus: fetchStatus?.asFetchStatus()
            )
        }
    }

    public static func decode(_ data: Data) throws -> UsageRecord {
        // Schema is read first and separately: an unknown schema must be reported as
        // such even when the rest of the payload no longer matches this DTO.
        if let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let schema = object["schema"] as? Int,
           !isSupportedSchema(schema) {
            throw UsageDecodeError.unsupportedSchema(schema)
        }

        guard let dto = try? JSONDecoder().decode(DTO.self, from: data) else {
            throw UsageDecodeError.malformed
        }
        guard isSupportedSchema(dto.schema) else {
            throw UsageDecodeError.unsupportedSchema(dto.schema)
        }

        return dto.asUsageRecord()
    }

    public static func encode(_ record: UsageRecord) throws -> Data {
        try JSONEncoder().encode(DTO(from: record))
    }
}
