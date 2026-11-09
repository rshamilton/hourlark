import Foundation
import Observation
import SwiftData
import UIKit

/// Keeps your logs mirrored to real files: always in the app's Files folder, and optionally in a
/// folder you pick (such as one in iCloud Drive).
@MainActor
@Observable
final class BackupManager {
    private(set) var lastBackup: Date?
    private(set) var lastError: String?
    private(set) var isWorking = false
    private(set) var customFolderName: String?

    var autoBackupEnabled: Bool {
        didSet { defaults.set(autoBackupEnabled, forKey: Keys.auto) }
    }

    /// Mirror backups into Hourlark's own iCloud Drive folder.
    var iCloudEnabled: Bool {
        didSet {
            defaults.set(iCloudEnabled, forKey: Keys.icloud)
            if iCloudEnabled { Task { await backupNow() } }
        }
    }

    /// False when the user isn't signed in to iCloud (or has iCloud Drive off).
    var iCloudAvailable: Bool { FileManager.default.ubiquityIdentityToken != nil }

    nonisolated static let iCloudContainerID = "iCloud.com.ryanhamilton.hourlark"

    @ObservationIgnored private let container: ModelContainer
    @ObservationIgnored private let defaults = UserDefaults.standard
    @ObservationIgnored private var debounceTask: Task<Void, Never>?
    @ObservationIgnored private var observerTask: Task<Void, Never>?
    @ObservationIgnored private var dirty = false

    private enum Keys {
        static let auto = "backup.auto"
        static let last = "backup.last"
        static let bookmark = "backup.bookmark"
        static let icloud = "backup.icloud"
    }

    /// `Documents/` inside Hourlark's iCloud container, which appears as the "Hourlark" folder in iCloud Drive.
    nonisolated static func iCloudFolder() -> URL? {
        FileManager.default.url(forUbiquityContainerIdentifier: iCloudContainerID)?
            .appendingPathComponent("Documents", isDirectory: true)
    }

    /// For fresh installs: is there a backup waiting in iCloud Drive?
    nonisolated static func iCloudLatestBackupURL() async -> URL? {
        await Task.detached { () -> URL? in
            guard let folder = iCloudFolder() else { return nil }
            let file = folder.appendingPathComponent(BackupWriter.latestName)
            let placeholder = folder.appendingPathComponent(".\(BackupWriter.latestName).icloud")
            let fm = FileManager.default
            if fm.fileExists(atPath: file.path) { return file }
            if fm.fileExists(atPath: placeholder.path) {
                try? fm.startDownloadingUbiquitousItem(at: file)
                return file
            }
            return nil
        }.value
    }

    /// `Documents/Backups`, shown in Files under On My iPhone → Hourlark.
    static var localFolder: URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let dir = docs.appendingPathComponent("Backups", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    init(container: ModelContainer) {
        self.container = container
        autoBackupEnabled = defaults.object(forKey: Keys.auto) as? Bool ?? true
        // On by default: backups also go to the user's own iCloud Drive (they can turn it off).
        iCloudEnabled = defaults.object(forKey: Keys.icloud) as? Bool ?? true
        let t = defaults.double(forKey: Keys.last)
        lastBackup = t > 0 ? Date(timeIntervalSince1970: t) : nil
        customFolderName = BackupWriter.resolveBookmark(defaults.data(forKey: Keys.bookmark))?.lastPathComponent

        observerTask = Task { [weak self] in
            for await _ in NotificationCenter.default.notifications(named: ModelContext.didSave) {
                self?.scheduleBackup()
            }
        }
    }

    // MARK: Triggers

    /// Called after data changes; backs up a few seconds later so bursts of edits become one file.
    func scheduleBackup() {
        guard autoBackupEnabled else { return }
        dirty = true
        debounceTask?.cancel()
        debounceTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(4))
            guard !Task.isCancelled else { return }
            await self?.backupNow()
        }
    }

    /// Called when the app leaves the screen, so nothing waits on the debounce timer.
    func flushIfNeeded() async {
        guard autoBackupEnabled, dirty else { return }
        debounceTask?.cancel()
        await backupNow()
    }

    /// Called on launch: refresh if the last backup is more than a day old.
    func backupIfStale() {
        guard autoBackupEnabled else { return }
        if let last = lastBackup, Date.now.timeIntervalSince(last) < 20 * 3600 { return }
        Task { await backupNow() }
    }

    // MARK: Backup

    func backupNow() async {
        guard !isWorking else { return }
        let context = container.mainContext
        do {
            // Never overwrite a good backup with an empty database (for example on a fresh install).
            guard try context.fetchCount(FetchDescriptor<Cause>()) > 0 else { return }

            isWorking = true
            defer { isWorking = false }
            dirty = false

            let participant = defaults.string(forKey: "participantName") ?? ""
            let file = try BackupService.makeBackup(from: context, participant: participant)
            let entries = try context.fetch(FetchDescriptor<TimeEntry>())
            let csv = Data(("\u{FEFF}" + CSVExporter.csv(for: entries)).utf8)
            let bookmark = defaults.data(forKey: Keys.bookmark)
            let local = Self.localFolder
            let useICloud = iCloudEnabled
            let signedInToICloud = iCloudAvailable

            let outcome = await Task.detached(priority: .utility) { () -> (local: String?, custom: String?) in
                let json: Data
                do { json = try BackupService.encode(file) } catch { return (error.localizedDescription, nil) }

                var localError: String?
                do { try BackupWriter.write(json: json, csv: csv, to: local) } catch { localError = error.localizedDescription }

                var customError: String?
                if useICloud {
                    if let folder = BackupManager.iCloudFolder() {
                        do { try BackupWriter.writeScoped(json: json, csv: csv, to: folder) }
                        catch { customError = "Couldn't save to iCloud Drive: \(error.localizedDescription)" }
                    } else if signedInToICloud {
                        customError = "iCloud Drive isn't available right now. Check iCloud Drive in iOS Settings."
                    }
                    // Not signed in to iCloud: skip quietly. Backups still go to Files on this iPhone.
                }
                if let folder = BackupWriter.resolveBookmark(bookmark) {
                    do { try BackupWriter.writeScoped(json: json, csv: csv, to: folder) }
                    catch { customError = "Couldn't save to \"\(folder.lastPathComponent)\": \(error.localizedDescription)" }
                }
                return (localError, customError)
            }.value

            if let message = outcome.local ?? outcome.custom {
                lastError = message
            } else {
                lastError = nil
            }
            if outcome.local == nil {
                lastBackup = .now
                defaults.set(Date.now.timeIntervalSince1970, forKey: Keys.last)
            }
        } catch {
            lastError = error.localizedDescription
        }
    }

    // MARK: Extra folder (iCloud Drive etc.)

    func setCustomFolder(_ url: URL) {
        let accessing = url.startAccessingSecurityScopedResource()
        defer { if accessing { url.stopAccessingSecurityScopedResource() } }
        do {
            let data = try url.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil)
            defaults.set(data, forKey: Keys.bookmark)
            customFolderName = url.lastPathComponent
            lastError = nil
            Task { await backupNow() }
        } catch {
            lastError = "Couldn't use that folder: \(error.localizedDescription)"
        }
    }

    func clearCustomFolder() {
        defaults.removeObject(forKey: Keys.bookmark)
        customFolderName = nil
    }

    /// Opens the Files app at Hourlark's folder.
    func openInFiles() {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let link = docs.absoluteString.replacingOccurrences(of: "file://", with: "shareddocuments://")
        if let url = URL(string: link) { UIApplication.shared.open(url) }
    }
}
