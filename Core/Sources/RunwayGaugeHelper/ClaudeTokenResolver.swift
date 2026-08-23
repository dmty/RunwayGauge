import Foundation
import UsageCore

enum ClaudeTokenResolver {
    static func accessToken(
        configDir: String?,
        keychainService: String?,
        keychainAccount: String?
    ) -> String? {
        if let service = keychainService,
           let token = KeychainTokenReader.accessToken(service: service, account: keychainAccount) {
            return token
        }
        if ClaudeOAuthToken.isDefaultConfigDir(configDir),
           let token = KeychainTokenReader.accessToken(
            service: ClaudeOAuthSource.genericKeychainService,
            account: nil
           ) {
            return token
        }
        if let configDir {
            return ClaudeOAuthToken.readAccessToken(configDir: configDir)
        }
        return nil
    }
}
