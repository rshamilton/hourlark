import SwiftUI
import SwiftData

struct CausesView: View {
    @Query(sort: \Cause.name) private var causes: [Cause]
    @State private var showNew = false

    private var active: [Cause] { causes.filter { !$0.archived } }
    private var archived: [Cause] { causes.filter(\.archived) }

    var body: some View {
            List {
                if causes.isEmpty {
                    ContentUnavailableView("No causes yet",
                                           systemImage: "heart.text.square",
                                           description: Text("A cause is anything you track time for: a charity, a job, a class."))
                }
                Section {
                    ForEach(active) { cause in
                        NavigationLink { CauseDetailView(cause: cause) } label: { CauseRow(cause: cause) }
                    }
                }
                if !archived.isEmpty {
                    Section("Archived") {
                        ForEach(archived) { cause in
                            NavigationLink { CauseDetailView(cause: cause) } label: { CauseRow(cause: cause) }
                        }
                    }
                }
            }
            .navigationTitle("Manage causes")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showNew = true } label: { Image(systemName: "plus") }
                        .accessibilityLabel("New cause")
                }
            }
            .sheet(isPresented: $showNew) { CauseEditor(cause: nil) }
    }
}

struct CauseRow: View {
    let cause: Cause

    var body: some View {
        HStack(spacing: 12) {
            CauseBadge(symbol: cause.symbol, tint: cause.tint)
            VStack(alignment: .leading, spacing: 4) {
                Text(cause.name).font(.headline)
                if !cause.organization.isEmpty {
                    Text(cause.organization).font(.subheadline).foregroundStyle(.secondary)
                }
                Label(cause.requiresSignOff ? "Needs sign-off" : "No sign-off",
                      systemImage: cause.requiresSignOff ? "signature" : "person.fill")
                    .font(.caption).foregroundStyle(.secondary)
                if cause.goalHours > 0 {
                    ProgressView(value: min(cause.totalSeconds / 3600, cause.goalHours), total: cause.goalHours)
                        .tint(cause.tint.swiftUIColor)
                }
            }
            Spacer()
            VStack(alignment: .trailing) {
                Text(Fmt.hm(cause.totalSeconds)).font(.headline).monospacedDigit()
                if cause.goalHours > 0 {
                    Text("of \(Int(cause.goalHours)) h").font(.caption).foregroundStyle(.secondary)
                }
            }
        }
        .padding(.vertical, 2)
    }
}

struct CauseDetailView: View {
    @Bindable var cause: Cause
    @State private var showEdit = false
    @State private var showSheet = false

    private var sortedEntries: [TimeEntry] { cause.entries.sorted { $0.startDate > $1.startDate } }

    var body: some View {
        List {
            Section {
                HStack {
                    StatTile(title: "Total", value: Fmt.hm(cause.totalSeconds))
                    if cause.requiresSignOff {
                        StatTile(title: "Signed", value: Fmt.hm(cause.seconds(with: .signed)), tint: .green)
                        StatTile(title: "Awaiting", value: Fmt.hm(cause.seconds(with: .awaitingSignature)), tint: .orange)
                        StatTile(title: "Not sent", value: Fmt.hm(cause.seconds(with: .notSubmitted)), tint: .secondary)
                    }
                }
                if cause.goalHours > 0 {
                    VStack(alignment: .leading, spacing: 6) {
                        let counted = cause.requiresSignOff ? cause.seconds(with: .signed) : cause.totalSeconds
                        let done = counted / 3600
                        ProgressView(value: min(done, cause.goalHours), total: cause.goalHours)
                            .tint(cause.requiresSignOff ? .green : cause.tint.swiftUIColor)
                        Text("\(String(format: "%.1f", done)) of \(String(format: "%g", cause.goalHours)) goal hours\(cause.requiresSignOff ? " signed" : "")")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
            if cause.requiresSignOff {
                Section {
                    Button { showSheet = true } label: {
                        Label("Create sign-off sheet", systemImage: "signature")
                    }
                    .disabled(cause.unsubmittedCount == 0)
                } footer: {
                    if cause.unsubmittedCount == 0 { Text("Log some hours first, then create a sheet to get them signed.") }
                }
            }
            Section("Entries") {
                if sortedEntries.isEmpty {
                    Text("Nothing logged for this cause yet.").foregroundStyle(.secondary)
                }
                ForEach(sortedEntries) { EntryRow(entry: $0, showCause: false) }
            }
        }
        .navigationTitle(cause.name)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) { Button("Edit") { showEdit = true } }
        }
        .sheet(isPresented: $showEdit) { CauseEditor(cause: cause) }
        .sheet(isPresented: $showSheet) { NewSheetView(initialCause: cause) }
    }
}

struct CauseEditor: View {
    let cause: Cause?

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    @State private var name: String
    @State private var organization: String
    @State private var supervisor: String
    @State private var symbol: String
    @State private var tint: CauseColor
    @State private var goalText: String
    @State private var requiresSignOff: Bool
    @State private var confirmDelete = false

    private static let symbols = [
        "heart.fill", "hands.sparkles.fill", "leaf.fill", "book.fill", "graduationcap.fill",
        "briefcase.fill", "hammer.fill", "cross.case.fill", "pawprint.fill", "fork.knife",
        "music.note", "figure.run", "building.2.fill", "star.fill", "paintbrush.fill", "bolt.fill"
    ]

    init(cause: Cause?) {
        self.cause = cause
        _name = State(initialValue: cause?.name ?? "")
        _organization = State(initialValue: cause?.organization ?? "")
        _supervisor = State(initialValue: cause?.supervisorName ?? "")
        _symbol = State(initialValue: cause?.symbol ?? "heart.fill")
        _tint = State(initialValue: cause?.tint ?? .blue)
        _requiresSignOff = State(initialValue: cause?.requiresSignOff ?? true)
        let goal = cause?.goalHours ?? 0
        _goalText = State(initialValue: goal > 0 ? String(format: "%g", goal) : "")
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Name (e.g. Food Bank)", text: $name)
                    TextField("Organization (optional)", text: $organization)
                }
                Section {
                    Toggle("Needs to be signed off", isOn: $requiresSignOff.animation())
                    if requiresSignOff {
                        TextField("Usual supervisor / verifier (optional)", text: $supervisor)
                    }
                } header: {
                    Text("Verification")
                } footer: {
                    Text(requiresSignOff
                         ? "You'll print sheets for this cause, get them signed, and attach a photo as proof."
                         : "Hours are just tracked and exported. There are no sign-off steps for this cause.")
                }
                Section("Goal") {
                    TextField("Required hours (optional)", text: $goalText)
                        .keyboardType(.decimalPad)
                }
                Section("Color") {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 5), spacing: 12) {
                        ForEach(CauseColor.allCases) { c in
                            Circle().fill(c.swiftUIColor.gradient)
                                .frame(width: 34, height: 34)
                                .overlay { if c == tint { Image(systemName: "checkmark").foregroundStyle(.white).bold() } }
                                .onTapGesture { tint = c }
                                .accessibilityLabel(c.rawValue)
                                .accessibilityAddTraits(c == tint ? [.isButton, .isSelected] : .isButton)
                        }
                    }
                    .padding(.vertical, 4)
                }
                Section("Icon") {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 6), spacing: 12) {
                        ForEach(Self.symbols, id: \.self) { s in
                            Image(systemName: s)
                                .frame(width: 38, height: 38)
                                .background(s == symbol ? tint.swiftUIColor.opacity(0.25) : .clear, in: RoundedRectangle(cornerRadius: 10))
                                .onTapGesture { symbol = s }
                                .accessibilityLabel(s)
                                .accessibilityAddTraits(s == symbol ? [.isButton, .isSelected] : .isButton)
                        }
                    }
                    .padding(.vertical, 4)
                }
                if let cause {
                    Section {
                        Button(cause.archived ? "Unarchive" : "Archive") {
                            cause.archived.toggle()
                            dismiss()
                        }
                        Button("Delete cause and all its time", role: .destructive) { confirmDelete = true }
                    } footer: {
                        Text("Archiving hides a cause from the timer but keeps its history and reports.")
                    }
                }
            }
            .navigationTitle(cause == nil ? "New Cause" : "Edit Cause")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .confirmationDialog("Delete this cause?", isPresented: $confirmDelete, titleVisibility: .visible) {
                Button("Delete everything", role: .destructive) {
                    if let cause { context.delete(cause) }
                    dismiss()
                }
            } message: {
                Text("All its time entries, sign-off sheets, and proof photos will be permanently deleted from this iPhone.")
            }
        }
    }

    private func save() {
        let goal = Double(goalText.replacingOccurrences(of: ",", with: ".")) ?? 0
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        if let cause {
            cause.name = trimmed
            cause.organization = organization
            cause.supervisorName = supervisor
            cause.symbol = symbol
            cause.tint = tint
            cause.goalHours = max(0, goal)
            cause.requiresSignOff = requiresSignOff
        } else {
            context.insert(Cause(name: trimmed, organization: organization, supervisorName: supervisor,
                                 symbol: symbol, tint: tint, goalHours: max(0, goal),
                                 requiresSignOff: requiresSignOff))
        }
        dismiss()
    }
}
