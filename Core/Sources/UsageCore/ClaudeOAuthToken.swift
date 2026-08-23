import Foundation

public enum ClaudeOAuthToken {
    public static func parseAccessToken(from data: Data) -> String? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let oauth = json["claudeAiOauth"] as? [String: Any],
              let token = oauth["accessToken"] as? String
        else { return nil }
        let trimmed = token.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    public static func readAccessToken(
        configDir: String,
        fileManager: FileManager = .default
    ) -> String? {
        let url = URL(fileURLWithPath: configDir).appendingPathComponent(".credentials.json")
        guard let data = fileManager.contents(atPath: url.path) else { return nil }
        return parseAccessToken(from: data)
    }

    public static func isDefaultConfigDir(_ path: String?) -> Bool {
        guard let path else { return false }
        let standardized = URL(fileURLWithPath: path).standardizedFileURL.path
        return (standardized as NSString).lastPathComponent == ".claude"
    }
}
