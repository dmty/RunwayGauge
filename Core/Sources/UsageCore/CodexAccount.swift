import Foundation

public enum CodexAccount {
    public static let id = "acc_codex_default"
    public static let label = "Codex"
    public static let executablePathKey = "executablePath"

    @discardableResult
    public static func merge(
        executablePath: String,
        into registry: inout AccountRegistry
    ) -> Bool {
        let normalized = URL(fileURLWithPath: executablePath)
            .standardizedFileURL.path

        if let index = registry.accounts.firstIndex(where: { $0.id == id }) {
            let current = registry.accounts[index]
            guard current.sourceKind != .codex
                    || current.label != label
                    || current.credentials.configDir != nil
                    || current.credentials.keychain != nil
                    || current.credentials.nonSecretFields[executablePathKey] != normalized
            else { return false }

            registry.accounts[index] = Account(
                id: current.id,
                label: label,
                sourceKind: .codex,
                pinned: current.pinned,
                credentials: AccountCredentials(nonSecretFields: [
                    executablePathKey: normalized,
                ])
            )
            return true
        }

        registry.accounts.append(Account(
            id: id,
            label: label,
            sourceKind: .codex,
            pinned: false,
            credentials: AccountCredentials(nonSecretFields: [
                executablePathKey: normalized,
            ])
        ))
        return true
    }
}
