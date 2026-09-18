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

    public static func parsePlanLabel(from data: Data) -> String? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let oauth = json["claudeAiOauth"] as? [String: Any]
        else { return nil }
        return displayPlan(
            subscriptionType: oauth["subscriptionType"] as? String,
            rateLimitTier: oauth["rateLimitTier"] as? String
        )
    }

    public static func displayPlan(subscriptionType: String?, rateLimitTier: String?) -> String? {
        let tier = rateLimitTier?.lowercased() ?? ""
        if let multiplier = maxMultiplier(in: tier) {
            return "Max \(multiplier)x"
        }
        switch subscriptionType?.lowercased() {
        case "max": return "Max"
        case "pro": return "Pro"
        case "team": return "Team"
        case "enterprise": return "Enterprise"
        case let other?:
            let trimmed = other.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        default:
            return nil
        }
    }

    private static func maxMultiplier(in tier: String) -> Int? {
        guard let match = tier.firstMatch(of: /max_(\d+)x/) else { return nil }
        return Int(match.1)
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
