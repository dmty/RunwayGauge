import Foundation

public struct SourceKind: RawRepresentable, Codable, Hashable, Sendable {
    public let rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        rawValue = try container.decode(String.self)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }

    public static let claudeOAuth = SourceKind(rawValue: "claude-oauth")
    public static let openAIAPI = SourceKind(rawValue: "openai-api")
    public static let anthropicAPI = SourceKind(rawValue: "anthropic-api")
}

public struct KeychainReference: Codable, Equatable, Sendable {
    public var service: String
    public var account: String?

    public init(service: String, account: String? = nil) {
        self.service = service
        self.account = account
    }
}

public struct AccountCredentials: Codable, Equatable, Sendable {
    public var configDir: String?
    public var keychain: KeychainReference?
    public var nonSecretFields: [String: String]

    public init(
        configDir: String? = nil,
        keychain: KeychainReference? = nil,
        nonSecretFields: [String: String] = [:]
    ) {
        self.configDir = configDir
        self.keychain = keychain
        self.nonSecretFields = nonSecretFields
    }

    enum CodingKeys: String, CodingKey {
        case configDir, keychain, nonSecretFields
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        configDir = try container.decodeIfPresent(String.self, forKey: .configDir)
        keychain = try container.decodeIfPresent(KeychainReference.self, forKey: .keychain)
        nonSecretFields = try container.decodeIfPresent([String: String].self, forKey: .nonSecretFields) ?? [:]
    }
}

public struct Account: Codable, Identifiable, Equatable, Sendable {
    public var id: String
    public var label: String
    public var sourceKind: SourceKind
    public var pinned: Bool
    public var credentials: AccountCredentials

    public init(
        id: String,
        label: String,
        sourceKind: SourceKind,
        pinned: Bool,
        credentials: AccountCredentials
    ) {
        self.id = id
        self.label = label
        self.sourceKind = sourceKind
        self.pinned = pinned
        self.credentials = credentials
    }
}

public struct AccountPreferences: Codable, Equatable, Sendable {
    public var selectedAccountId: String?
    public var rotateEnabled: Bool
    public var rotateIntervalSec: Int
    public var rotationAnchorAt: Double?

    public init(
        selectedAccountId: String? = nil,
        rotateEnabled: Bool = false,
        rotateIntervalSec: Int = 900,
        rotationAnchorAt: Double? = nil
    ) {
        self.selectedAccountId = selectedAccountId
        self.rotateEnabled = rotateEnabled
        self.rotateIntervalSec = rotateIntervalSec
        self.rotationAnchorAt = rotationAnchorAt
    }

    enum CodingKeys: String, CodingKey {
        case selectedAccountId, rotateEnabled, rotateIntervalSec, rotationAnchorAt
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        selectedAccountId = try c.decodeIfPresent(String.self, forKey: .selectedAccountId)
        rotateEnabled = try c.decodeIfPresent(Bool.self, forKey: .rotateEnabled) ?? false
        rotateIntervalSec = try c.decodeIfPresent(Int.self, forKey: .rotateIntervalSec) ?? 900
        rotationAnchorAt = try c.decodeIfPresent(Double.self, forKey: .rotationAnchorAt)
    }
}

public struct AccountRegistry: Codable, Equatable, Sendable {
    public static let currentSchema = 1

    public var schema: Int
    public var revision: UInt64
    public var prefs: AccountPreferences
    public var accounts: [Account]

    public init(
        schema: Int = currentSchema,
        revision: UInt64,
        prefs: AccountPreferences,
        accounts: [Account]
    ) {
        self.schema = schema
        self.revision = revision
        self.prefs = prefs
        self.accounts = accounts
    }
}

public enum AccountDecodeError: Error, Equatable {
    case unsupportedSchema(Int)
    case malformed
}

extension AccountRegistry {
    private struct SchemaProbe: Decodable { let schema: Int }

    public static func decode(_ data: Data) throws -> AccountRegistry {
        if let probe = try? JSONDecoder().decode(SchemaProbe.self, from: data),
           probe.schema != currentSchema {
            throw AccountDecodeError.unsupportedSchema(probe.schema)
        }
        guard let registry = try? JSONDecoder().decode(AccountRegistry.self, from: data) else {
            throw AccountDecodeError.malformed
        }
        return registry
    }

    public static func encode(_ registry: AccountRegistry) throws -> Data {
        try JSONEncoder().encode(registry)
    }
}
