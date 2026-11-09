import ActivityKit
import SwiftUI

/// Describes the lock-screen / Dynamic Island timer. Shared by the app and the widget extension.
struct TimerActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        var running = true
    }

    var causeName: String
    var symbol: String
    var colorName: String
    /// The system counts up from this date on its own, so the app doesn't need to push updates.
    var startDate: Date
}

enum ActivityTint {
    static func color(_ name: String) -> Color {
        switch name {
        case "teal": .teal
        case "green": .green
        case "yellow": .yellow
        case "orange": .orange
        case "red": .red
        case "pink": .pink
        case "purple": .purple
        case "indigo": .indigo
        case "gray": .gray
        default: .blue
        }
    }

    static func foreground(_ name: String) -> Color { name == "yellow" ? .black : .white }
}
