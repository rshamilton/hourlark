import SwiftUI
import SwiftData
import PhotosUI

struct SignOffsView: View {
    @Query(sort: \SignOffSheet.createdAt, order: .reverse) private var sheets: [SignOffSheet]
    @Query(filter: #Predicate<Cause> { $0.archived == false && $0.requiresSignOff == true }) private var causes: [Cause]
    @State private var showNew = false
    @State private var showGuide = false

    private var awaiting: [SignOffSheet] { sheets.filter { !$0.isSigned } }
    private var signed: [SignOffSheet] { sheets.filter(\.isSigned) }

    var body: some View {
        NavigationStack {
            List {
                if sheets.isEmpty {
                    ContentUnavailableView {
                        Label("No sign-off sheets", systemImage: "signature")
                    } description: {
                        Text(causes.isEmpty
                             ? "Sign-offs are optional. If someone needs to verify a cause's hours, turn on \"Needs to be signed off\" when editing it."
                             : "Only needed if someone must verify your hours. Create a sheet, print it, get it signed, then photograph it here. Tap ? for a walkthrough.")
                    }
                }
                if !awaiting.isEmpty {
                    Section("Awaiting signature") {
                        ForEach(awaiting) { sheet in NavigationLink(value: sheet) { SheetRow(sheet: sheet) } }
                    }
                }
                if !signed.isEmpty {
                    Section("Signed") {
                        ForEach(signed) { sheet in NavigationLink(value: sheet) { SheetRow(sheet: sheet) } }
                    }
                }
            }
            .navigationTitle("Sign-offs")
            .navigationDestination(for: SignOffSheet.self) { SheetDetailView(sheet: $0) }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { showGuide = true } label: { Image(systemName: "questionmark.circle") }
                        .accessibilityLabel("How sign-offs work")
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showNew = true } label: { Image(systemName: "plus") }
                        .accessibilityLabel("New sign-off sheet")
                        .disabled(causes.isEmpty)
                }
            }
            .sheet(isPresented: $showNew) { NewSheetView(initialCause: nil) }
            .sheet(isPresented: $showGuide) { GuideView() }
        }
    }
}

struct SheetRow: View {
    let sheet: SignOffSheet

    /// "Nov 9, 2026" for one day, "Oct 15 – Oct 24, 2026" within a year, full dates across years.
    private var rangeText: String {
        let cal = Calendar.current
        if cal.isDate(sheet.rangeStart, inSameDayAs: sheet.rangeEnd) { return Fmt.date(sheet.rangeStart) }
        if cal.component(.year, from: sheet.rangeStart) == cal.component(.year, from: sheet.rangeEnd) {
            let start = sheet.rangeStart.formatted(.dateTime.month(.abbreviated).day())
            return "\(start) – \(Fmt.date(sheet.rangeEnd))"
        }
        return "\(Fmt.date(sheet.rangeStart)) – \(Fmt.date(sheet.rangeEnd))"
    }

    var body: some View {
        HStack(spacing: 12) {
            CauseBadge(symbol: sheet.cause?.symbol ?? "questionmark", tint: sheet.cause?.tint ?? .gray, size: 36)
            VStack(alignment: .leading, spacing: 3) {
                Text(sheet.cause?.name ?? "Unknown cause").font(.headline).lineLimit(2)
                Text(rangeText)
                    .font(.subheadline).foregroundStyle(.secondary)
                    .lineLimit(1).minimumScaleFactor(0.85)
                HStack(spacing: 8) {
                    StatusBadge(status: sheet.isSigned ? .signed : .awaitingSignature)
                    if !sheet.proofs.isEmpty {
                        Label("\(sheet.proofs.count)", systemImage: "photo").font(.caption2).foregroundStyle(.secondary)
                    }
                }
            }
            Spacer(minLength: 8)
            Text(Fmt.hm(sheet.totalSeconds)).font(.headline).monospacedDigit()
                .fixedSize(horizontal: true, vertical: false)
        }
    }
}

// MARK: - Create

struct NewSheetView: View {
    let initialCause: Cause?

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query(filter: #Predicate<Cause> { $0.archived == false && $0.requiresSignOff == true }, sort: \Cause.name)
    private var causes: [Cause]

    @State private var causeID: UUID?
    @State private var from = Calendar.current.date(byAdding: .month, value: -1, to: .now) ?? .now
    @State private var to = Date.now
    @State private var verifier = ""
    @State private var excluded: Set<UUID> = []

    private var cause: Cause? { causes.first { $0.uuid == causeID } }

    private var eligible: [TimeEntry] {
        guard let cause else { return [] }
        let cal = Calendar.current
        let lo = cal.startOfDay(for: from)
        let hi = cal.date(byAdding: .day, value: 1, to: cal.startOfDay(for: to)) ?? to
        return cause.entries
            .filter { $0.sheet == nil && $0.startDate >= lo && $0.startDate < hi }
            .sorted { $0.startDate < $1.startDate }
    }

    private var chosen: [TimeEntry] { eligible.filter { !excluded.contains($0.uuid) } }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Cause", selection: $causeID) {
                        Text("Choose…").tag(UUID?.none)
                        ForEach(causes) { Text($0.name).tag(Optional($0.uuid)) }
                    }
                    DatePicker("From", selection: $from, displayedComponents: .date)
                    DatePicker("To", selection: $to, displayedComponents: .date)
                    TextField("Who will sign? (optional)", text: $verifier)
                }

                Section {
                    if cause == nil {
                        Text("Pick a cause to see its unsubmitted hours.").foregroundStyle(.secondary)
                    } else if eligible.isEmpty {
                        Text("No unsubmitted entries in this range.").foregroundStyle(.secondary)
                    }
                    ForEach(eligible) { entry in
                        Button {
                            if excluded.contains(entry.uuid) { excluded.remove(entry.uuid) } else { excluded.insert(entry.uuid) }
                        } label: {
                            HStack {
                                Image(systemName: excluded.contains(entry.uuid) ? "circle" : "checkmark.circle.fill")
                                    .foregroundStyle(excluded.contains(entry.uuid) ? Color.secondary : Color.accentColor)
                                EntryRow(entry: entry, showCause: false)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                } header: {
                    Text("Entries to include")
                } footer: {
                    if !chosen.isEmpty { Text("\(chosen.count) entries · \(Fmt.hm(chosen.reduce(0) { $0 + $1.duration }))") }
                }
            }
            .navigationTitle("New Sign-off Sheet")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Create") { create() }.disabled(chosen.isEmpty)
                }
            }
            .onAppear {
                if causeID == nil { causeID = initialCause?.uuid ?? causes.first?.uuid }
                applyDefaults()
            }
            .onChange(of: causeID) { applyDefaults() }
        }
    }

    private func applyDefaults() {
        excluded = []
        guard let cause else { return }
        verifier = cause.supervisorName
        let open = cause.entries.filter { $0.sheet == nil }
        if let earliest = open.map(\.startDate).min() { from = earliest }
        if let latest = open.map(\.startDate).max() { to = max(latest, .now) } else { to = .now }
    }

    private func create() {
        guard let cause else { return }
        let entries = chosen
        let sheet = SignOffSheet(rangeStart: entries.map(\.startDate).min() ?? from,
                                 rangeEnd: entries.map(\.startDate).max() ?? to,
                                 verifierName: verifier)
        context.insert(sheet)
        sheet.cause = cause
        for e in entries { e.sheet = sheet }
        dismiss()
    }
}

// MARK: - Detail

struct SheetDetailView: View {
    @Bindable var sheet: SignOffSheet

    @AppStorage("participantName") private var participant = ""
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    @State private var exportFile: ExportFile?
    @State private var showScanner = false
    @State private var pickerItems: [PhotosPickerItem] = []
    @State private var viewing: ProofImage?
    @State private var showMarkSigned = false
    @State private var confirmDelete = false
    @State private var errorMessage: String?

    var body: some View {
        List {
            Section {
                LabeledContent("Cause", value: sheet.cause?.name ?? "—")
                LabeledContent("Period", value: "\(Fmt.date(sheet.rangeStart)) – \(Fmt.date(sheet.rangeEnd))")
                LabeledContent("Total", value: Fmt.hm(sheet.totalSeconds))
                if !sheet.verifierName.isEmpty { LabeledContent("Verifier", value: sheet.verifierName) }
                LabeledContent("Sheet ID", value: sheet.shortID)
                if sheet.isSigned, let on = sheet.signedOn {
                    LabeledContent("Signed", value: Fmt.date(on) + (sheet.signedBy.isEmpty ? "" : " by \(sheet.signedBy)"))
                        .foregroundStyle(.green)
                }
            }

            Section {
                Button { exportSheet() } label: { Label("Print or share sheet (PDF)", systemImage: "printer") }
            } header: {
                Text("1 · Print")
            } footer: {
                Text("Print this, have your supervisor sign it, then add a photo below.")
            }

            Section {
                if !sheet.proofs.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack {
                            ForEach(sheet.sortedProofs) { proof in
                                if let image = UIImage(data: proof.data) {
                                    Button { viewing = proof } label: {
                                        Image(uiImage: image)
                                            .resizable().scaledToFill()
                                            .frame(width: 84, height: 110)
                                            .clipShape(RoundedRectangle(cornerRadius: 8))
                                    }
                                    .buttonStyle(.plain)
                                    .accessibilityLabel("Proof photo")
                                }
                            }
                        }
                    }
                }
                if DocumentScanner.isSupported {
                    Button { showScanner = true } label: { Label("Scan signed sheet", systemImage: "doc.viewfinder") }
                }
                PhotosPicker(selection: $pickerItems, maxSelectionCount: 5, matching: .images) {
                    Label("Choose from photos", systemImage: "photo.on.rectangle")
                }
            } header: {
                Text("2 · Attach proof")
            }

            Section {
                if sheet.isSigned {
                    Button("Mark as not signed", role: .destructive) { sheet.signedOn = nil; sheet.signedBy = "" }
                } else {
                    Button { showMarkSigned = true } label: { Label("Mark as signed", systemImage: "checkmark.seal") }
                }
            } header: {
                Text("3 · Confirm")
            } footer: {
                if !sheet.isSigned && sheet.proofs.isEmpty {
                    Text("Tip: attach a photo first so the proof is included in your reports.")
                }
            }

            Section("Entries") {
                ForEach(sheet.sortedEntries) { EntryRow(entry: $0, showCause: false) }
            }

            Section {
                Button("Delete sheet", role: .destructive) { confirmDelete = true }
            } footer: {
                Text("Deleting a sheet keeps your logged time but removes the sheet and its proof photos.")
            }
        }
        .navigationTitle("Sign-off Sheet")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $exportFile) { ShareSheet(url: $0.url).presentationDetents([.medium, .large]) }
        .fullScreenCover(isPresented: $showScanner) {
            DocumentScanner { images in
                for image in images { addProof(image) }
            }
            .ignoresSafeArea()
        }
        .sheet(item: $viewing) { ProofViewer(proof: $0) }
        .sheet(isPresented: $showMarkSigned) { MarkSignedView(sheet: sheet) }
        .onChange(of: pickerItems) { loadPickedPhotos() }
        .confirmationDialog("Delete this sheet?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Delete sheet", role: .destructive) {
                context.delete(sheet)
                dismiss()
            }
        }
        .alert("Couldn't create PDF", isPresented: .constant(errorMessage != nil)) {
            Button("OK") { errorMessage = nil }
        } message: { Text(errorMessage ?? "") }
    }

    private func exportSheet() {
        let data = PDFReports.signOffSheet(sheet, participant: participant)
        do {
            let name = "Hourlark-SignOff-\(sheet.shortID).pdf"
            exportFile = ExportFile(url: try TempFiles.write(data, name: name))
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func addProof(_ image: UIImage) {
        guard let data = ImageTools.compressedJPEG(from: image) else { return }
        let proof = ProofImage(data: data)
        context.insert(proof)
        proof.sheet = sheet
    }

    private func loadPickedPhotos() {
        let items = pickerItems
        guard !items.isEmpty else { return }
        Task {
            for item in items {
                if let data = try? await item.loadTransferable(type: Data.self), let image = UIImage(data: data) {
                    addProof(image)
                }
            }
            pickerItems = []
        }
    }
}

struct MarkSignedView: View {
    @Bindable var sheet: SignOffSheet
    @Environment(\.dismiss) private var dismiss
    @State private var signer = ""
    @State private var date = Date.now

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Who signed? (optional)", text: $signer)
                    DatePicker("Date signed", selection: $date, in: ...Date.now, displayedComponents: .date)
                } footer: {
                    Text("Once signed, the entries on this sheet are locked so your records match the paper.")
                }
            }
            .navigationTitle("Mark as Signed")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        sheet.signedBy = signer
                        sheet.signedOn = date
                        dismiss()
                    }
                }
            }
            .onAppear { signer = sheet.verifierName }
        }
        .presentationDetents([.medium])
    }
}

struct ProofViewer: View {
    let proof: ProofImage
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var confirmDelete = false

    var body: some View {
        NavigationStack {
            ScrollView([.horizontal, .vertical]) {
                if let image = UIImage(data: proof.data) {
                    Image(uiImage: image).resizable().scaledToFit()
                }
            }
            .navigationTitle("Proof")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } }
                ToolbarItem(placement: .destructiveAction) {
                    Button(role: .destructive) { confirmDelete = true } label: { Image(systemName: "trash") }
                }
            }
            .confirmationDialog("Delete this photo?", isPresented: $confirmDelete, titleVisibility: .visible) {
                Button("Delete photo", role: .destructive) {
                    context.delete(proof)
                    dismiss()
                }
            }
        }
    }
}
