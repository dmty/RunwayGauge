import Foundation

public enum ResetStyle: Sendable {
    case short
    case long
}

public struct UsageFormatter: Sendable {
    private static let posixLocale = Locale(identifier: "en_US_POSIX")

    private let timeZone: TimeZone
    private let calendar: Calendar

    public init(timeZone: TimeZone) {
        self.timeZone = timeZone
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = timeZone
        cal.locale = Self.posixLocale
        self.calendar = cal
    }

    private func formatter(_ template: String) -> DateFormatter {
        let f = DateFormatter()
        f.locale = Self.posixLocale
        f.timeZone = timeZone
        f.dateFormat = template
        return f
    }

    private func lowercaseMeridiem(_ text: String) -> String {
        text.replacingOccurrences(of: "AM", with: "am")
            .replacingOccurrences(of: "PM", with: "pm")
    }

    public func resetDescription(_ resetsAt: Date, now: Date, style: ResetStyle) -> String {
        let template: String
        if calendar.isDate(resetsAt, inSameDayAs: now) {
            template = "h:mma"
        } else if resetsAt.timeIntervalSince(now) < 7 * 86400 {
            template = "EEE h:mma"
        } else {
            template = "MMM d, h:mma"
        }

        // en_US_POSIX renders AM/PM uppercase; the design calls for lowercase, and only
        // the meridiem may be lowered — weekday and month abbreviations keep their case.
        let text = lowercaseMeridiem(formatter(template).string(from: resetsAt))

        switch style {
        case .short: return text
        case .long: return "\(text) (\(timeZone.identifier))"
        }
    }

    public func ageDescription(_ age: TimeInterval) -> String {
        let seconds = Int(max(0, age))
        switch seconds {
        case ..<60: return "just now"
        case ..<3600: return "\(seconds / 60)m ago"
        case ..<172_800: return "\(seconds / 3600)h ago"
        default: return "\(seconds / 86400)d ago"
        }
    }
}
