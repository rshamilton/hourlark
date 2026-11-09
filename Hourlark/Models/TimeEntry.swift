import SwiftData
import SwiftUI

enum VerificationStatus: String, CaseIterable {
    case notRequired
    case notSubmitted
    case awaitingSignature
    case signed

    var label: String {
        switch self {
        case .notRequired: "No sign-off needed"
        case .notSubmitted: "Not submitted"
        case .awaitingSignature: "Awaiting signature"
        case .signed: "Signed"
        }
    }

    var symbol: String {
        switch self {
        case .notRequired: "checkmark.circle"
        case .notSubmitted: "circle.dashed"
        case .awaitingSignature: "hourglass"
        case .signed: "checkmark.seal.fill"
        }
    }

    var color: Color {
        switch self {
        case .notRequired: .teal
        case .notSubmitted: .gray
        case .awaitingSignature: .orange
        case .signed: .green
        }
    }
}

@Model
final class TimeEntry {
    var uuid: UUID = UUID()
    var startDate: Date = Date()
    /// Length in seconds.
    var duration: TimeInterval = 0
    var notes: String = ""
    var cause: Cause?
    var sheet: SignOffSheet?

    init(startDate: Date, duration: TimeInterval, notes: String = "") {
        self.startDate = startDate
        self.duration = duration
        self.notes = notes
    }

    var status: VerificationStatus {
        if let sheet { return sheet.isSigned ? .signed : .awaitingSignature }
        return cause?.requiresSignOff == false ? .notRequired : .notSubmitted
    }

    var isLocked: Bool { sheet?.isSigned == true }
}

extension Collection where Element == TimeEntry {
    /// True when any of these hours involve signing. When false, exports leave out every sign-off column.
    var involvesSignOff: Bool {
        contains { $0.cause?.requiresSignOff == true || $0.sheet != nil }
    }
}
