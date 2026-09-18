import Foundation
import Testing
@testable import UsageCore

@Suite("ClaudeOAuthTokenTests")
struct ClaudeOAuthTokenTests {
    @Test("parses accessToken from claudeAiOauth JSON")
    func parsesAccessToken() throws {
        let data = Data(#"{ "claudeAiOauth": { "accessToken": "tok_live", "refreshToken": "ref" } }"#.utf8)
        #expect(ClaudeOAuthToken.parseAccessToken(from: data) == "tok_live")
    }

    @Test("returns nil for empty or missing accessToken")
    func missingToken() {
        #expect(ClaudeOAuthToken.parseAccessToken(from: Data("{}".utf8)) == nil)
        let empty = Data(#"{ "claudeAiOauth": { "accessToken": "" } }"#.utf8)
        #expect(ClaudeOAuthToken.parseAccessToken(from: empty) == nil)
    }

    @Test("reads .credentials.json from a config directory")
    func readsCredentialsFile() throws {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appending(path: "claude-token-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        try Data(#"{ "claudeAiOauth": { "accessToken": "from-file" } }"#.utf8)
            .write(to: dir.appending(path: ".credentials.json"))
        #expect(ClaudeOAuthToken.readAccessToken(configDir: dir.path) == "from-file")
    }

    @Test("treats ~/.claude as the default config directory")
    func defaultConfigDir() {
        #expect(ClaudeOAuthToken.isDefaultConfigDir("/Users/ada/.claude"))
        #expect(!ClaudeOAuthToken.isDefaultConfigDir("/Users/ada/.claude-v"))
        #expect(!ClaudeOAuthToken.isDefaultConfigDir(nil))
    }

    @Test("formats Max 20x from subscriptionType and rateLimitTier")
    func planLabelMax20x() {
        let data = Data(#"{ "claudeAiOauth": { "accessToken": "t", "subscriptionType": "max", "rateLimitTier": "default_claude_max_20x" } }"#.utf8)
        #expect(ClaudeOAuthToken.parsePlanLabel(from: data) == "Max 20x")
    }

    @Test("formats Pro from subscriptionType")
    func planLabelPro() {
        let data = Data(#"{ "claudeAiOauth": { "accessToken": "t", "subscriptionType": "pro", "rateLimitTier": "default_claude_ai" } }"#.utf8)
        #expect(ClaudeOAuthToken.parsePlanLabel(from: data) == "Pro")
    }

    @Test("returns nil when subscription fields are missing")
    func planLabelMissing() {
        let data = Data(#"{ "claudeAiOauth": { "accessToken": "t" } }"#.utf8)
        #expect(ClaudeOAuthToken.parsePlanLabel(from: data) == nil)
    }
}
