import Foundation
import UsageCore

/// Live Anthropic OAuth usage GET. Headers match `scripts/poll-claude-usage.sh` plus anthropic-beta.
struct UsageHTTPClient: UsageFetching, Sendable {
    var session: URLSession
    var url: URL
    var timeout: TimeInterval

    init(
        session: URLSession = .shared,
        url: URL = URL(string: "https://api.anthropic.com/api/oauth/usage")!,
        timeout: TimeInterval = 15
    ) {
        self.session = session
        self.url = url
        self.timeout = timeout
    }

    func fetchUsage(accessToken: String) async throws -> (
        status: Int,
        body: Data,
        retryAfter: TimeInterval?
    ) {
        var request = URLRequest(url: url, timeoutInterval: timeout)
        request.httpMethod = "GET"
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("runway-gauge/1.0", forHTTPHeaderField: "User-Agent")
        request.setValue("oauth-2025-04-20", forHTTPHeaderField: "anthropic-beta")

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            return (status: -1, body: data, retryAfter: nil)
        }
        return (
            status: http.statusCode,
            body: data,
            retryAfter: Self.parseRetryAfter(http.value(forHTTPHeaderField: "Retry-After"))
        )
    }

    static func parseRetryAfter(_ raw: String?) -> TimeInterval? {
        guard let raw = raw?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else {
            return nil
        }
        if let seconds = TimeInterval(raw), seconds >= 0 {
            return seconds
        }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss zzz"
        if let date = formatter.date(from: raw) {
            return max(0, date.timeIntervalSinceNow)
        }
        return nil
    }
}
