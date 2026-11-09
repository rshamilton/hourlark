import SwiftData
import SwiftUI

enum CauseColor: String, CaseIterable, Identifiable {
    case blue, teal, green, yellow, orange, red, pink, purple, indigo, gray

    var id: String { rawValue }

    /// Readable text/icon color on top of this color's gradient.
    var foreground: Color { self == .yellow ? .black : .white }

    var swiftUIColor: Color {
        switch self {
        case .blue: .blue
        case .teal: .teal
        case .green: .green
        case .yellow: .yellow
        case .orange: .orange
        case .red: .red
        case .pink: .pink
        case .purple: .purple
        case .indigo: .indigo
        case .gray: .gray
        }
    }
}

/// A "cause" is anything you track time against: a charity, a job, a class, a project.
@Model
final class Cause {
    var uuid: UUID = UUID()
    var name: String = ""
    var organization: String = ""
    var supervisorName: String = ""
    var symbol: String = "heart.fill"
    var colorRaw: String = CauseColor.blue.rawValue
    /// 0 means "no goal".
    var goalHours: Double = 0
    /// Whether a supervisor has to sign off on these hours.
    var requiresSignOff: Bool = true
    var archived: Bool = false
    var createdAt: Date = Date()

    @Relationship(deleteRule: .cascade, inverse: \TimeEntry.cause)
    var entries: [TimeEntry] = []

    @Relationship(deleteRule: .cascade, inverse: \SignOffSheet.cause)
    var sheets: [SignOffSheet] = []

    init(name: String,
         organization: String = "",
         supervisorName: String = "",
         symbol: String = "heart.fill",
         tint: CauseColor = .blue,
         goalHours: Double = 0,
         requiresSignOff: Bool = true) {
        self.requiresSignOff = requiresSignOff
        self.name = name
        self.organization = organization
        self.supervisorName = supervisorName
        self.symbol = symbol
        self.colorRaw = tint.rawValue
        self.goalHours = goalHours
    }

    var tint: CauseColor {
        get { CauseColor(rawValue: colorRaw) ?? .blue }
        set { colorRaw = newValue.rawValue }
    }

    var totalSeconds: TimeInterval { entries.reduce(0) { $0 + $1.duration } }

    var unsubmittedCount: Int { entries.filter { $0.status == .notSubmitted }.count }

    func seconds(with status: VerificationStatus) -> TimeInterval {
        entries.filter { $0.status == status }.reduce(0) { $0 + $1.duration }
    }
}
