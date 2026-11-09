import SwiftUI
import SwiftData

struct BackupSettingsView: View {
    @Environment(BackupManager.self) private var backup
    @State private var showFolderPicker = false
    @State private var showRestore = false

    var body: some View {
        @Bindable var backup = backup

        Form {
            Section {
                Toggle("Automatic backups", isOn: $backup.autoBackupEnabled)
                LabeledContent("Last backup", value: backup.lastBackup.map {
                    $0.formatted(date: .abbreviated, time: .shortened)
                } ?? "Never")
                Button {
                    Task { await backup.backupNow() }
                } label: {
                    HStack {
                        Label("Back up now", systemImage: "arrow.clockwise")
                        if backup.isWorking { Spacer(); ProgressView() }
                    }
                }
                .disabled(backup.isWorking)
                if let error = backup.lastError {
                    Label(error, systemImage: "exclamationmark.triangle.fill")
                        .font(.footnote)
                        .foregroundStyle(.red)
                }
            } footer: {
                Text("Saved a few seconds after every change.")
            }

            Section {
                Label("This iPhone, always", systemImage: "iphone")
                Button { backup.openInFiles() } label: {
                    Label("Open in Files", systemImage: "folder")
                }
            } header: {
                Text("Stored on this iPhone")
            } footer: {
                Text("Files → On My iPhone → Hourlark → Backups")
            }

            Section {
                Toggle("Save to iCloud Drive", isOn: $backup.iCloudEnabled)
                if backup.iCloudEnabled && !backup.iCloudAvailable {
                    Label("Sign in to iCloud in iOS Settings.", systemImage: "exclamationmark.icloud")
                        .font(.footnote)
                        .foregroundStyle(.orange)
                }
            } header: {
                Text("Your private iCloud Drive")
            } footer: {
                Text("On by default. Copies go to your own iCloud account. Only you can see them. Turn it off any time.")
            }

            Section {
                if let name = backup.customFolderName {
                    LabeledContent("Saving to", value: name)
                    Button("Change folder…") { showFolderPicker = true }
                    Button("Stop saving there", role: .destructive) { backup.clearCustomFolder() }
                } else {
                    Button { showFolderPicker = true } label: {
                        Label("Choose a folder…", systemImage: "folder.badge.plus")
                    }
                }
            } header: {
                Text("Another folder")
            } footer: {
                Text("Optional. Any folder you pick in Files.")
            }

            Section {
                Button { showRestore = true } label: {
                    Label("Restore from a backup…", systemImage: "arrow.down.doc")
                }
            } header: {
                Text("Restore")
            } footer: {
                Text("Pick a backup (.json) from Files.")
            }
        }
        .navigationTitle("Backup & Files")
        .navigationBarTitleDisplayMode(.inline)
        .restoreFlow(isPresented: $showRestore)
        .background {
            Color.clear.fileImporter(isPresented: $showFolderPicker, allowedContentTypes: [.folder]) { result in
                if case .success(let url) = result { backup.setCustomFolder(url) }
            }
        }
    }
}
