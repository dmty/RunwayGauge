import Foundation

public enum AccountValidationError: Error, Equatable {
    case unsupportedSchema(Int)
    case invalidID(String)
    case duplicateID(String)
    case invalidLabel(String)
    case invalidRotationInterval(Int)
    case invalidConfigDirectory(String)
    case duplicateConfigDirectory(String)
    case emptyKeychainService(String)
    case duplicateKeychainReference(String, String?)
}

public enum AccountValidation {
    /// Account labels are limited to 100 user-perceived characters.
    public static let maximumLabelLength = 100

    public static func validateID(_ id: String) throws {
        guard isValidID(id) else {
            throw AccountValidationError.invalidID(id)
        }
    }

    public static func validateAndRepair(
        _ registry: inout AccountRegistry,
        home: URL? = nil
    ) throws {
        guard registry.schema == AccountRegistry.currentSchema else {
            throw AccountValidationError.unsupportedSchema(registry.schema)
        }
        guard (300...86_400).contains(registry.prefs.rotateIntervalSec) else {
            throw AccountValidationError.invalidRotationInterval(
                registry.prefs.rotateIntervalSec
            )
        }

        var ids = Set<String>()
        var configDirectories = Set<String>()
        var keychainReferences = Set<KeychainFingerprint>()

        for index in registry.accounts.indices {
            let id = registry.accounts[index].id
            try validateID(id)
            guard ids.insert(id).inserted else {
                throw AccountValidationError.duplicateID(id)
            }

            let originalLabel = registry.accounts[index].label
            let label = originalLabel.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !label.isEmpty, label.count <= maximumLabelLength else {
                throw AccountValidationError.invalidLabel(originalLabel)
            }
            registry.accounts[index].label = label

            if var keychain = registry.accounts[index].credentials.keychain {
                let service = keychain.service.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !service.isEmpty else {
                    throw AccountValidationError.emptyKeychainService(id)
                }
                let account = keychain.account?
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                if account?.isEmpty == true {
                    keychain.account = nil
                }
                if registry.accounts[index].sourceKind == .claudeOAuth {
                    let fingerprint = KeychainFingerprint(
                        service: service,
                        account: account?.isEmpty == true ? nil : account
                    )
                    guard keychainReferences.insert(fingerprint).inserted else {
                        throw AccountValidationError.duplicateKeychainReference(
                            service,
                            keychain.account
                        )
                    }
                }
                registry.accounts[index].credentials.keychain = keychain
            }

            if registry.accounts[index].sourceKind == .claudeOAuth,
               let path = registry.accounts[index].credentials.configDir {
                guard !path.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                    throw AccountValidationError.invalidConfigDirectory(path)
                }
                let normalized = normalizePath(path, home: home)
                guard configDirectories.insert(normalized).inserted else {
                    throw AccountValidationError.duplicateConfigDirectory(normalized)
                }
                registry.accounts[index].credentials.configDir = normalized
            }
        }

        if let selected = registry.prefs.selectedAccountId,
           !registry.accounts.contains(where: { $0.id == selected && $0.pinned }) {
            registry.prefs.selectedAccountId = registry.accounts.first(where: \.pinned)?.id
            registry.prefs.rotationAnchorAt = nil
        }
    }

    public static func isPollCapable(_ account: Account) -> Bool {
        guard account.sourceKind == .claudeOAuth,
              let keychain = account.credentials.keychain else {
            return false
        }
        return !keychain.service.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !(keychain.account?
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .isEmpty ?? true)
    }

    public static func normalizePath(_ path: String, home: URL? = nil) -> String {
        let homePath = (home ?? UsageStore.realUserHome()).path
        let expanded: String
        if path == "~" {
            expanded = homePath
        } else if path.hasPrefix("~/") {
            expanded = homePath + "/" + path.dropFirst(2)
        } else {
            expanded = path
        }

        let standardized = standardizePathComponents(expanded)
        if FileManager.default.fileExists(atPath: standardized) {
            return URL(fileURLWithPath: standardized)
                .resolvingSymlinksInPath()
                .standardizedFileURL
                .path
        }
        return standardized
    }

    private static func isValidID(_ id: String) -> Bool {
        guard id.hasPrefix("acc_") else { return false }
        let suffix = id.dropFirst(4)
        guard (1...64).contains(suffix.count) else { return false }
        return suffix.utf8.allSatisfy {
            ($0 >= 48 && $0 <= 57)
                || ($0 >= 65 && $0 <= 90)
                || ($0 >= 97 && $0 <= 122)
                || $0 == 95
                || $0 == 45
        }
    }

    private struct KeychainFingerprint: Hashable {
        var service: String
        var account: String?
    }

    private static func standardizePathComponents(_ path: String) -> String {
        let absolute = path.hasPrefix("/")
        var components: [Substring] = []
        for component in path.split(separator: "/", omittingEmptySubsequences: true) {
            switch component {
            case ".":
                continue
            case "..":
                if components.last.map({ $0 != ".." }) == true {
                    components.removeLast()
                } else if !absolute {
                    components.append(component)
                }
            default:
                components.append(component)
            }
        }

        let joined = components.joined(separator: "/")
        if absolute {
            return joined.isEmpty ? "/" : "/" + joined
        }
        return joined.isEmpty ? "." : joined
    }
}
