import Foundation
import UsageCore

struct ClaudeCredentials {
    var accessToken: String
    var planLabel: String?
}

enum ClaudeTokenResolver {
    static func credentials(
        configDir: String?,
        keychainService: String?,
        keychainAccount: String?
    ) -> ClaudeCredentials? {
        if let service = keychainService,
           let data = KeychainTokenReader.credentialData(service: service, account: keychainAccount),
           let creds = parse(data) {
            return creds
        }
        if ClaudeOAuthToken.isDefaultConfigDir(configDir),
           let data = KeychainTokenReader.credentialData(
            service: ClaudeOAuthSource.genericKeychainService,
            account: nil
           ),
           let creds = parse(data) {
            return creds
        }
        if let configDir {
            let url = URL(fileURLWithPath: configDir).appendingPathComponent(".credentials.json")
            if let data = FileManager.default.contents(atPath: url.path) {
                return parse(data)
            }
        }
        return nil
    }

    private static func parse(_ data: Data) -> ClaudeCredentials? {
        guard let token = ClaudeOAuthToken.parseAccessToken(from: data) else { return nil }
        return ClaudeCredentials(
            accessToken: token,
            planLabel: ClaudeOAuthToken.parsePlanLabel(from: data)
        )
    }
}
