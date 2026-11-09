import SwiftUI
import SwiftData

struct SettingsView: View {
    @AppStorage("participantName") private var participant = ""
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(BackupManager.self) private var backup
    @Query private var causes: [Cause]
    @State private var confirmErase = false
    @State private var showGuide = false

    private var version: String {
        let v = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
        let b = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "?"
        return "\(v) (\(b))"
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Your name", text: $participant)
                        .textContentType(.name)
                } header: {
                    Text("Printed on sheets and reports")
                }

                Section {
                    NavigationLink {
                        CausesView()
                    } label: {
                        Label("Manage causes", systemImage: "heart.text.square")
                    }
                    Button { showGuide = true } label: {
                        Label("How printing, signing & reports work", systemImage: "questionmark.circle")
                    }
                    .foregroundStyle(.primary)
                }

                Section {
                    NavigationLink {
                        BackupSettingsView()
                    } label: {
                        Label {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Backup & Files")
                                Text(backup.lastBackup.map { "Last backup \($0.formatted(.relative(presentation: .named)))" } ?? "Not backed up yet")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                        } icon: { Image(systemName: "externaldrive.badge.icloud") }
                    }
                    NavigationLink {
                        ReminderSettingsView()
                    } label: {
                        Label("Reminders", systemImage: "bell.badge")
                    }
                }

                Section {
                    Label("Stored only on this iPhone", systemImage: "iphone")
                    Label("Optional backup to your own private iCloud Drive", systemImage: "icloud")
                    Label("No account, servers, analytics or ads", systemImage: "lock.shield")
                } header: {
                    Text("Your data")
                } footer: {
                    Text("Nothing is shared with anyone, ever. Hourlark has no servers to send it to.")
                }

                Section("About") {
                    LabeledContent("Version", value: version)
                    LabeledContent("License", value: "GPL-3.0 (free, open source)")
                }

                Section {
                    Button("Erase all data…", role: .destructive) { confirmErase = true }
                } footer: {
                    Text("Saved backups in Files are kept.")
                }
            }
            .sheet(isPresented: $showGuide) { GuideView() }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
            .confirmationDialog("Erase everything?", isPresented: $confirmErase, titleVisibility: .visible) {
                Button("Erase all data", role: .destructive) {
                    for cause in causes { context.delete(cause) }
                }
            } message: {
                Text("This can't be undone, except from a backup.")
            }
        }
    }
}
