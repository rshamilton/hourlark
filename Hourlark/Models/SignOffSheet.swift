import SwiftData
import Foundation

/// A printable verification sheet covering a set of entries for one cause.
/// Once the signed paper is photographed and attached, it can be marked signed.
@Model
final class SignOffSheet {
    var uuid: UUID = UUID()
    var createdAt: Date = Date()
    var rangeStart: Date = Date()
    var rangeEnd: Date = Date()
    var verifierName: String = ""
    var signedBy: String = ""
    var signedOn: Date?
    var cause: Cause?

    @Relationship(deleteRule: .nullify, inverse: \TimeEntry.sheet)
    var entries: [TimeEntry] = []

    @Relationship(deleteRule: .cascade, inverse: \ProofImage.sheet)
    var proofs: [ProofImage] = []

    init(rangeStart: Date, rangeEnd: Date, verifierName: String = "") {
        self.rangeStart = rangeStart
        self.rangeEnd = rangeEnd
        self.verifierName = verifierName
    }

    var isSigned: Bool { signedOn != nil }
    var shortID: String { String(uuid.uuidString.prefix(8)) }
    var totalSeconds: TimeInterval { entries.reduce(0) { $0 + $1.duration } }
    var sortedEntries: [TimeEntry] { entries.sorted { $0.startDate < $1.startDate } }
    var sortedProofs: [ProofImage] { proofs.sorted { $0.addedAt < $1.addedAt } }
}

/// A photo or scan of the signed paper sheet.
@Model
final class ProofImage {
    var uuid: UUID = UUID()
    var addedAt: Date = Date()
    @Attribute(.externalStorage) var data: Data = Data()
    var sheet: SignOffSheet?

    init(data: Data) {
        self.data = data
    }
}
