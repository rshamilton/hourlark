import Foundation
import SwiftData

// MARK: - File format

/// A complete, self-contained snapshot of your data. Plain JSON, so it's readable and future-proof.
struct BackupFile: Codable, Sendable {
    var format = "hourlark-backup"
    var version = 1
    var exportedAt: Date
    var appVersion: String
    var participantName: String
    var causes: [CauseRecord]
    var entries: [EntryRecord]
    var sheets: [SheetRecord]
    var proofs: [ProofRecord]

    struct CauseRecord: Codable, Sendable {
        var uuid: UUID
        var name: String
        var organization: String
        var supervisorName: String
        var symbol: String
        var colorRaw: String
        var goalHours: Double
        var requiresSignOff: Bool?
        var archived: Bool
        var createdAt: Date
    }

    struct EntryRecord: Codable, Sendable {
        var uuid: UUID
        var causeUUID: UUID?
        var sheetUUID: UUID?
        var startDate: Date
        var duration: TimeInterval
        var notes: String
    }

    struct SheetRecord: Codable, Sendable {
        var uuid: UUID
        var causeUUID: UUID?
        var createdAt: Date
        var rangeStart: Date
        var rangeEnd: Date
        var verifierName: String
        var signedBy: String
        var signedOn: Date?
    }

    struct ProofRecord: Codable, Sendable {
        var uuid: UUID
        var sheetUUID: UUID?
        var addedAt: Date
        /// JPEG bytes (encoded as base64 in the JSON).
        var data: Data
    }
}

enum BackupError: LocalizedError {
    case notABackup
    case newerVersion(Int)

    var errorDescription: String? {
        switch self {
        case .notABackup: "That file isn't an Hourlark backup."
        case .newerVersion: "That backup was made by a newer version of Hourlark. Update the app and try again."
        }
    }
}

// MARK: - Build / encode / restore

enum BackupService {
    static let currentVersion = 1

    static func makeBackup(from context: ModelContext, participant: String) throws -> BackupFile {
        let causes = try context.fetch(FetchDescriptor<Cause>(sortBy: [SortDescriptor(\.createdAt)]))
        let entries = try context.fetch(FetchDescriptor<TimeEntry>(sortBy: [SortDescriptor(\.startDate)]))
        let sheets = try context.fetch(FetchDescriptor<SignOffSheet>(sortBy: [SortDescriptor(\.createdAt)]))
        let proofs = try context.fetch(FetchDescriptor<ProofImage>(sortBy: [SortDescriptor(\.addedAt)]))
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"

        return BackupFile(
            version: currentVersion,
            exportedAt: .now,
            appVersion: version,
            participantName: participant,
            causes: causes.map {
                .init(uuid: $0.uuid, name: $0.name, organization: $0.organization,
                      supervisorName: $0.supervisorName, symbol: $0.symbol, colorRaw: $0.colorRaw,
                      goalHours: $0.goalHours, requiresSignOff: $0.requiresSignOff,
                      archived: $0.archived, createdAt: $0.createdAt)
            },
            entries: entries.map {
                .init(uuid: $0.uuid, causeUUID: $0.cause?.uuid, sheetUUID: $0.sheet?.uuid,
                      startDate: $0.startDate, duration: $0.duration, notes: $0.notes)
            },
            sheets: sheets.map {
                .init(uuid: $0.uuid, causeUUID: $0.cause?.uuid, createdAt: $0.createdAt,
                      rangeStart: $0.rangeStart, rangeEnd: $0.rangeEnd, verifierName: $0.verifierName,
                      signedBy: $0.signedBy, signedOn: $0.signedOn)
            },
            proofs: proofs.map {
                .init(uuid: $0.uuid, sheetUUID: $0.sheet?.uuid, addedAt: $0.addedAt, data: $0.data)
            })
    }

    static func encode(_ file: BackupFile) throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(file)
    }

    static func decode(_ data: Data) throws -> BackupFile {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let file = try? decoder.decode(BackupFile.self, from: data), file.format == "hourlark-backup" else {
            throw BackupError.notABackup
        }
        if file.version > currentVersion { throw BackupError.newerVersion(file.version) }
        return file
    }

    enum RestoreMode { case merge, replace }

    struct Summary {
        var causes = 0, entries = 0, sheets = 0, proofs = 0
        var text: String {
            "Added \(causes) causes, \(entries) entries, \(sheets) sheets and \(proofs) proof photos."
        }
    }

    /// Merge adds anything missing (matched by ID) and never deletes. Replace wipes first.
    @discardableResult
    static func restore(_ file: BackupFile, into context: ModelContext, mode: RestoreMode) throws -> Summary {
        if mode == .replace {
            for m in try context.fetch(FetchDescriptor<ProofImage>()) { context.delete(m) }
            for m in try context.fetch(FetchDescriptor<TimeEntry>()) { context.delete(m) }
            for m in try context.fetch(FetchDescriptor<SignOffSheet>()) { context.delete(m) }
            for m in try context.fetch(FetchDescriptor<Cause>()) { context.delete(m) }
            try context.save()
        }

        var causes = Dictionary(uniqueKeysWithValues: try context.fetch(FetchDescriptor<Cause>()).map { ($0.uuid, $0) })
        var sheets = Dictionary(uniqueKeysWithValues: try context.fetch(FetchDescriptor<SignOffSheet>()).map { ($0.uuid, $0) })
        let knownEntries = Set(try context.fetch(FetchDescriptor<TimeEntry>()).map(\.uuid))
        let knownProofs = Set(try context.fetch(FetchDescriptor<ProofImage>()).map(\.uuid))
        var summary = Summary()

        for r in file.causes where causes[r.uuid] == nil {
            let c = Cause(name: r.name, organization: r.organization, supervisorName: r.supervisorName,
                          symbol: r.symbol, tint: CauseColor(rawValue: r.colorRaw) ?? .blue,
                          goalHours: r.goalHours, requiresSignOff: r.requiresSignOff ?? true)
            c.uuid = r.uuid
            c.archived = r.archived
            c.createdAt = r.createdAt
            context.insert(c)
            causes[r.uuid] = c
            summary.causes += 1
        }

        for r in file.sheets where sheets[r.uuid] == nil {
            let s = SignOffSheet(rangeStart: r.rangeStart, rangeEnd: r.rangeEnd, verifierName: r.verifierName)
            s.uuid = r.uuid
            s.createdAt = r.createdAt
            s.signedBy = r.signedBy
            s.signedOn = r.signedOn
            context.insert(s)
            s.cause = r.causeUUID.flatMap { causes[$0] }
            sheets[r.uuid] = s
            summary.sheets += 1
        }

        for r in file.entries where !knownEntries.contains(r.uuid) {
            let e = TimeEntry(startDate: r.startDate, duration: r.duration, notes: r.notes)
            e.uuid = r.uuid
            context.insert(e)
            e.cause = r.causeUUID.flatMap { causes[$0] }
            e.sheet = r.sheetUUID.flatMap { sheets[$0] }
            summary.entries += 1
        }

        for r in file.proofs where !knownProofs.contains(r.uuid) {
            let p = ProofImage(data: r.data)
            p.uuid = r.uuid
            p.addedAt = r.addedAt
            context.insert(p)
            p.sheet = r.sheetUUID.flatMap { sheets[$0] }
            summary.proofs += 1
        }

        try context.save()
        return summary
    }
}

// MARK: - Writing files

/// Writes backups as ordinary files so they show up in the Files app.
enum BackupWriter {
    static let latestName = "Hourlark-Latest.json"
    static let csvName = "Hourlark-Hours.csv"
    private static let datedPrefix = "Hourlark-Backup-"

    static func resolveBookmark(_ data: Data?) -> URL? {
        guard let data else { return nil }
        var stale = false
        return try? URL(resolvingBookmarkData: data, options: [], relativeTo: nil, bookmarkDataIsStale: &stale)
    }

    static func write(json: Data, csv: Data, to folder: URL, today: Date = .now) throws {
        let fm = FileManager.default
        try fm.createDirectory(at: folder, withIntermediateDirectories: true)
        try json.write(to: folder.appendingPathComponent(latestName), options: .atomic)
        try csv.write(to: folder.appendingPathComponent(csvName), options: .atomic)
        try json.write(to: folder.appendingPathComponent("\(datedPrefix)\(Fmt.isoDate(today)).json"), options: .atomic)
        prune(folder)
    }

    /// Reads a file that may live in iCloud (downloading it first if needed) or outside the app.
    static func readCoordinated(_ url: URL) throws -> Data {
        let accessing = url.startAccessingSecurityScopedResource()
        defer { if accessing { url.stopAccessingSecurityScopedResource() } }

        var coordinationError: NSError?
        var result: Result<Data, Error>?
        NSFileCoordinator().coordinate(readingItemAt: url, options: [], error: &coordinationError) { readable in
            result = Result { try Data(contentsOf: readable) }
        }
        if let coordinationError { throw coordinationError }
        return try result?.get() ?? Data()
    }

    /// For a folder the user picked in Files (for example in iCloud Drive).
    static func writeScoped(json: Data, csv: Data, to folder: URL) throws {
        let accessing = folder.startAccessingSecurityScopedResource()
        defer { if accessing { folder.stopAccessingSecurityScopedResource() } }

        var coordinationError: NSError?
        var writeError: Error?
        NSFileCoordinator().coordinate(writingItemAt: folder, options: [], error: &coordinationError) { url in
            do { try write(json: json, csv: csv, to: url) } catch { writeError = error }
        }
        if let error = coordinationError ?? writeError { throw error }
    }

    /// Keep the 14 most recent dated snapshots.
    static func prune(_ folder: URL, keep: Int = 14) {
        let fm = FileManager.default
        guard let names = try? fm.contentsOfDirectory(atPath: folder.path) else { return }
        let dated = names.filter { $0.hasPrefix(datedPrefix) && $0.hasSuffix(".json") }.sorted(by: >)
        for name in dated.dropFirst(keep) {
            try? fm.removeItem(at: folder.appendingPathComponent(name))
        }
    }
}
