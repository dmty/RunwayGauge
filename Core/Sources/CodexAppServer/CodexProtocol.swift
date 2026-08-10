import Foundation

public struct CodexRPCError: Decodable, Equatable, Sendable {
    public let code: Int
    public let message: String
}

public struct CodexAccountInfo: Decodable, Equatable, Sendable {
    public let type: String
    public let planType: String?

    public init(type: String, planType: String? = nil) {
        self.type = type
        self.planType = planType
    }
}

public struct CodexAccountReadResult: Decodable, Equatable, Sendable {
    public let account: CodexAccountInfo?
    public let requiresOpenaiAuth: Bool?

    public init(account: CodexAccountInfo?, requiresOpenaiAuth: Bool? = nil) {
        self.account = account
        self.requiresOpenaiAuth = requiresOpenaiAuth
    }
}

public struct CodexRateLimitWindow: Decodable, Equatable, Sendable {
    public let usedPercent: Double?
    public let windowDurationMins: Int?
    public let resetsAt: Double?

    public init(
        usedPercent: Double?,
        windowDurationMins: Int?,
        resetsAt: Double?
    ) {
        self.usedPercent = usedPercent
        self.windowDurationMins = windowDurationMins
        self.resetsAt = resetsAt
    }
}

public struct CodexRateLimitBucket: Decodable, Equatable, Sendable {
    public let limitId: String?
    public let primary: CodexRateLimitWindow?
    public let secondary: CodexRateLimitWindow?
    public let planType: String?

    public init(
        limitId: String?,
        primary: CodexRateLimitWindow?,
        secondary: CodexRateLimitWindow?,
        planType: String?
    ) {
        self.limitId = limitId
        self.primary = primary
        self.secondary = secondary
        self.planType = planType
    }
}

public struct CodexRateLimitsReadResult: Decodable, Equatable, Sendable {
    public let rateLimits: CodexRateLimitBucket?
    public let rateLimitsByLimitId: [String: CodexRateLimitBucket]?

    public init(
        rateLimits: CodexRateLimitBucket?,
        rateLimitsByLimitId: [String: CodexRateLimitBucket]?
    ) {
        self.rateLimits = rateLimits
        self.rateLimitsByLimitId = rateLimitsByLimitId
    }
}

struct CodexRPCResponse<Result: Decodable>: Decodable {
    let id: Int
    let result: Result?
    let error: CodexRPCError?
}
