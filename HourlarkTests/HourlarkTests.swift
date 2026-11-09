import Testing
import Foundation
import SwiftData
@testable import Hourlark

@MainActor
struct StatusTests {
    private func makeContext() throws -> ModelContext {
        let config = ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        let container = try ModelContainer(
            for: Cause.self, TimeEntry.self, SignOffSheet.self, ProofImage.self,
            configurations: config)
        return ModelContext(container)
    }

    @Test func exportsDropSignOffColumnsWhenNothingNeedsIt() throws {
        let context = try makeContext()
        let free = Cause(name: "Work", requiresSignOff: false)
        let needs = Cause(name: "Service", requiresSignOff: true)
        context.insert(free); context.insert(needs)
        let a = TimeEntry(startDate: .now, duration: 3600)
        let b = TimeEntry(startDate: .now, duration: 3600)
        context.insert(a); context.insert(b)
        a.cause = free
        b.cause = needs

        let plain = CSVExporter.csv(for: [a])
        #expect(!plain.contains("Status"))
        #expect(!plain.contains("Sheet ID"))
        let mixed = CSVExporter.csv(for: [a, b])
        #expect(mixed.contains("Status"))
        #expect(mixed.contains("Sheet ID"))
    }

    @Test func statusFollowsCauseAndSheet() throws {
        let context = try makeContext()
        let needs = Cause(name: "Service", requiresSignOff: true)
        let free = Cause(name: "Work", requiresSignOff: false)
        context.insert(needs); context.insert(free)

        let a = TimeEntry(startDate: .now, duration: 3600)
        let b = TimeEntry(startDate: .now, duration: 3600)
        context.insert(a); context.insert(b)
        a.cause = needs
        b.cause = free
        #expect(a.status == .notSubmitted)
        #expect(b.status == .notRequired)

        let sheet = SignOffSheet(rangeStart: .now, rangeEnd: .now)
        context.insert(sheet)
        sheet.cause = needs
        a.sheet = sheet
        #expect(a.status == .awaitingSignature)
        #expect(a.isLocked == false)

        sheet.signedOn = .now
        #expect(a.status == .signed)
        #expect(a.isLocked)
    }
}

@MainActor
struct BackupTests {
    private func makeContext() throws -> ModelContext {
        let config = ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        let container = try ModelContainer(
            for: Cause.self, TimeEntry.self, SignOffSheet.self, ProofImage.self,
            configurations: config)
        return ModelContext(container)
    }

    private func seed(_ context: ModelContext) throws {
        let cause = Cause(name: "Food Bank", organization: "Helping Hands", tint: .green,
                          goalHours: 40, requiresSignOff: true)
        context.insert(cause)
        let entry = TimeEntry(startDate: Date(timeIntervalSince1970: 1_700_000_000), duration: 5400, notes: "Sorted cans, \"fun\"")
        context.insert(entry)
        entry.cause = cause
        let sheet = SignOffSheet(rangeStart: .now, rangeEnd: .now, verifierName: "Pat")
        context.insert(sheet)
        sheet.cause = cause
        sheet.signedBy = "Pat"
        sheet.signedOn = Date(timeIntervalSince1970: 1_700_100_000)
        entry.sheet = sheet
        let proof = ProofImage(data: Data([1, 2, 3, 4]))
        context.insert(proof)
        proof.sheet = sheet
        try context.save()
    }

    @Test func roundTripThroughJSON() throws {
        let source = try makeContext()
        try seed(source)
        let file = try BackupService.makeBackup(from: source, participant: "Ryan")
        let decoded = try BackupService.decode(try BackupService.encode(file))
        #expect(decoded.causes.count == 1)
        #expect(decoded.entries.first?.notes == "Sorted cans, \"fun\"")
        #expect(decoded.proofs.first?.data == Data([1, 2, 3, 4]))

        let target = try makeContext()
        let summary = try BackupService.restore(decoded, into: target, mode: .replace)
        #expect(summary.entries == 1 && summary.proofs == 1)
        let restored = try target.fetch(FetchDescriptor<TimeEntry>())
        #expect(restored.first?.status == .signed)
        #expect(restored.first?.cause?.name == "Food Bank")
        #expect(restored.first?.sheet?.proofs.count == 1)
    }

    @Test func mergeNeverDuplicates() throws {
        let context = try makeContext()
        try seed(context)
        let file = try BackupService.makeBackup(from: context, participant: "")
        let summary = try BackupService.restore(file, into: context, mode: .merge)
        #expect(summary.causes == 0 && summary.entries == 0 && summary.sheets == 0 && summary.proofs == 0)
        #expect(try context.fetchCount(FetchDescriptor<TimeEntry>()) == 1)
    }

    @Test func rejectsOtherJSON() {
        #expect(throws: BackupError.self) { try BackupService.decode(Data("{\"hello\":1}".utf8)) }
    }
}

@MainActor
@Suite(.serialized)
struct SharedTimerTests {
    /// Each test gets its own empty store and the app is told not to react to it.
    init() {
        SharedConfig.defaults = UserDefaults(suiteName: "hourlark.tests.\(UUID().uuidString)") ?? .standard
        SharedStore.sendsNotifications = false
    }

    private func reset() {}

    @Test func startStopQueuesAMinimumOneMinuteSession() {
        reset()
        defer { reset() }
        let cause = SharedCause(id: UUID().uuidString, name: "Food Bank", symbol: "heart.fill", colorName: "red")
        let start = Date.now.addingTimeInterval(-10)
        SharedStore.start(cause, at: start)
        #expect(SharedStore.running()?.cause.name == "Food Bank")

        let session = SharedStore.stop(at: start.addingTimeInterval(10))
        #expect(session?.duration == 60)
        #expect(SharedStore.running() == nil)
        #expect(SharedStore.pending().count == 1)
        #expect(SharedStore.displayTotals().today >= 60)

        SharedStore.clearPending(ids: [session!.id])
        #expect(SharedStore.pending().isEmpty)
    }

    @Test func startingWhileRunningQueuesTheFirstSession() {
        reset()
        defer { reset() }
        let a = SharedCause(id: "a", name: "A", symbol: "star", colorName: "blue")
        let b = SharedCause(id: "b", name: "B", symbol: "star", colorName: "green")
        SharedStore.start(a, at: Date.now.addingTimeInterval(-3600))
        SharedStore.start(b)
        #expect(SharedStore.running()?.cause.id == "b")
        #expect(SharedStore.pending().map(\.causeID) == ["a"])
        #expect(SharedStore.pending().first?.duration == 3600)
    }
}

struct XLSXTests {
    @Test func buildsAValidZipContainer() {
        let data = XLSXWriter.build(sheets: [
            XLSXSheet(name: "Entries", columns: [("A", 10), ("B", 10)],
                      rows: [[.text("x & <y>"), .number(1.5)], [.date(.now), .empty]])
        ])
        #expect(data.starts(with: [0x50, 0x4B, 0x03, 0x04]))
        let text = String(decoding: data, as: UTF8.self)
        #expect(text.contains("xl/worksheets/sheet1.xml"))
        #expect(text.contains("x &amp; &lt;y&gt;"))
    }

    @Test func columnReferences() {
        #expect(XLSXWriter.ref(col: 0, row: 1) == "A1")
        #expect(XLSXWriter.ref(col: 25, row: 3) == "Z3")
        #expect(XLSXWriter.ref(col: 26, row: 2) == "AA2")
    }

    @Test func crcMatchesKnownValue() {
        // CRC-32 of "123456789" is 0xCBF43926.
        #expect(ZipWriter.crc32(Data("123456789".utf8)) == 0xCBF4_3926)
    }
}

struct FormattingTests {
    @Test func durationFormats() {
        #expect(Fmt.hm(0) == "0m")
        #expect(Fmt.hm(45 * 60) == "45m")
        #expect(Fmt.hm(3600) == "1h")
        #expect(Fmt.hm(9000) == "2h 30m")
        #expect(Fmt.colonHM(9000) == "2:30")
        #expect(Fmt.decimal(9000) == "2.50")
        #expect(Fmt.clock(3723) == "01:02:03")
    }
}

struct CSVTests {
    @Test func escapesCommasAndQuotes() {
        #expect(CSVExporter.escape("plain") == "plain")
        #expect(CSVExporter.escape("a,b") == "\"a,b\"")
        #expect(CSVExporter.escape("say \"hi\"") == "\"say \"\"hi\"\"\"")
    }

    @Test func neutralisesFormulaInjection() {
        #expect(CSVExporter.escape("=SUM(A1)") == "'=SUM(A1)")
        #expect(CSVExporter.escape("@cmd") == "'@cmd")
    }

    @Test func emptyExportHasHeaderOnly() {
        let csv = CSVExporter.csv(for: [])
        #expect(csv.hasPrefix("Date,Start time,Cause"))
        #expect(csv.split(separator: "\r\n").count == 1)
    }
}
