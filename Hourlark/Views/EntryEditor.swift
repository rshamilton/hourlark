import SwiftUI
import SwiftData

struct EntryEditor: View {
    let entry: TimeEntry?

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Cause.name) private var causes: [Cause]

    @State private var causeID: UUID?
    @State private var start: Date
    @State private var hours: Int
    @State private var minutes: Int
    @State private var notes: String

    init(entry: TimeEntry?, defaultCause: Cause?) {
        self.entry = entry
        _causeID = State(initialValue: entry?.cause?.uuid ?? defaultCause?.uuid)
        _start = State(initialValue: entry?.startDate ?? .now)
        let total = Int(((entry?.duration ?? 3600) / 60).rounded())
        _hours = State(initialValue: total / 60)
        _minutes = State(initialValue: total % 60)
        _notes = State(initialValue: entry?.notes ?? "")
    }

    private var locked: Bool { entry?.isLocked == true }
    private var duration: TimeInterval { TimeInterval(hours * 3600 + minutes * 60) }
    private var pickable: [Cause] { causes.filter { !$0.archived || $0.uuid == causeID } }
    private var canSave: Bool { causeID != nil && duration > 0 && !locked }

    var body: some View {
        NavigationStack {
            Form {
                if locked {
                    Section {
                        Label("On a signed sheet, so it's locked.", systemImage: "lock.fill")
                            .foregroundStyle(.secondary)
                    }
                }
                Section {
                    Picker("Cause", selection: $causeID) {
                        ForEach(pickable) { Text($0.name).tag(Optional($0.uuid)) }
                    }
                    DatePicker("Started", selection: $start, in: ...Date.now.addingTimeInterval(86_400))
                }
                .disabled(locked)

                Section("Duration") {
                    // Ranges include the current value so long or odd-minute entries (a timer
                    // rounded to 7 min, a forgotten 30 h session) are never silently clamped.
                    Stepper("Hours: \(hours)", value: $hours, in: 0...max(24, hours))
                    Stepper("Minutes: \(minutes)", value: $minutes, in: 0...59)
                    LabeledContent("Total", value: duration > 0 ? Fmt.hm(duration) : "—")
                }
                .disabled(locked)

                Section("Notes") {
                    TextField("What did you do?", text: $notes, axis: .vertical)
                        .lineLimit(2...6)
                }
                .disabled(locked)

                if let entry, !locked {
                    Section {
                        Button("Delete entry", role: .destructive) {
                            context.delete(entry)
                            dismiss()
                        }
                    }
                }
            }
            .navigationTitle(entry == nil ? "Add Time" : "Edit Entry")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }.disabled(!canSave)
                }
            }
        }
    }

    private func save() {
        guard let cause = causes.first(where: { $0.uuid == causeID }) else { return }
        if let entry {
            entry.startDate = start
            entry.duration = duration
            entry.notes = notes
            entry.cause = cause
        } else {
            let new = TimeEntry(startDate: start, duration: duration, notes: notes)
            context.insert(new)
            new.cause = cause
        }
        dismiss()
    }
}
