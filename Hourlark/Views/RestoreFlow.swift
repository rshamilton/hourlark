import SwiftUI
import SwiftData
import UniformTypeIdentifiers

/// File picker → read → "merge or replace?" → result. Attach with `.restoreFlow(isPresented:)`.
struct RestoreFlow: ViewModifier {
    @Binding var isPresented: Bool
    /// Set this to restore from a known file (for example the iCloud backup) without the picker.
    @Binding var url: URL?
    @Environment(\.modelContext) private var context
    @AppStorage("participantName") private var participant = ""
    @AppStorage("onboardingDone") private var onboardingDone = false

    @State private var pending: BackupFile?
    @State private var message: String?

    func body(content: Content) -> some View {
        content
            .fileImporter(isPresented: $isPresented, allowedContentTypes: [.json]) { result in
                handle(result)
            }
            .onChange(of: url) { _, newValue in
                guard let newValue else { return }
                url = nil
                load(newValue)
            }
            .confirmationDialog(
                "Restore this backup?",
                isPresented: Binding(get: { pending != nil }, set: { if !$0 { pending = nil } }),
                titleVisibility: .visible,
                presenting: pending
            ) { file in
                Button("Merge with my current data") { apply(file, .merge) }
                Button("Replace everything", role: .destructive) { apply(file, .replace) }
                Button("Cancel", role: .cancel) {}
            } message: { file in
                Text("Made \(file.exportedAt.formatted(date: .abbreviated, time: .shortened)) · \(file.causes.count) causes, \(file.entries.count) entries, \(file.proofs.count) proof photos. Merge keeps what you have and adds what's missing.")
            }
            .alert("Restore", isPresented: Binding(get: { message != nil }, set: { if !$0 { message = nil } })) {
                Button("OK") {}
            } message: {
                Text(message ?? "")
            }
    }

    private func handle(_ result: Result<URL, Error>) {
        switch result {
        case .failure(let error):
            message = error.localizedDescription
        case .success(let url):
            load(url)
        }
    }

    private func load(_ url: URL) {
        Task {
            do {
                let data = try await Task.detached { try BackupWriter.readCoordinated(url) }.value
                pending = try BackupService.decode(data)
            } catch {
                message = error.localizedDescription
            }
        }
    }

    private func apply(_ file: BackupFile, _ mode: BackupService.RestoreMode) {
        do {
            let summary = try BackupService.restore(file, into: context, mode: mode)
            if participant.isEmpty || mode == .replace { participant = file.participantName }
            onboardingDone = true
            message = summary.text
        } catch {
            message = "Restore failed: \(error.localizedDescription)"
        }
    }
}

extension View {
    func restoreFlow(isPresented: Binding<Bool>, url: Binding<URL?> = .constant(nil)) -> some View {
        modifier(RestoreFlow(isPresented: isPresented, url: url))
    }
}
