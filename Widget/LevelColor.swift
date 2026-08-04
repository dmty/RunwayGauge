import SwiftUI
import UsageCore

extension UsageLevel {
    var color: Color {
        switch self {
        case .normal: return Color(red: 0.702, green: 0.702, blue: 0.961)   // #B3B3F5
        case .warning: return Color(red: 0.961, green: 0.780, blue: 0.478)  // #F5C77A
        case .critical: return Color(red: 0.961, green: 0.502, blue: 0.478) // #F5807A
        }
    }
}
