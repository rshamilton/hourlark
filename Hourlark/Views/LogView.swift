import SwiftUI
import SwiftData

struct LogView: View {
    @Environment(\.modelContext) private var context

    @Query(sort: \TimeEntry.startDate, order: .reverse) private var entries: [TimeEntry]
    @Query(sort: \Cause.name) private var causes: [Cause]

    @State private var filterCauseID: UUID?
    @State private var search = ""
    @State private var editing: TimeEntry?
    @State private var showNew = false

    private var filtered: [TimeEntry] {
        entries.filter { e in
            if let id = filterCauseID, e.cause?.uuid != id { return false }
            guard !search.isEmpty else { return true }
            return e.notes.localizedCaseInsensitiveContains(search)
                || (e.cause?.name.localizedCaseInsensitiveContains(search) ?? false)
        }
    }

    private var sections: [(month: Date, entries: [TimeEntry])] {
        let cal = Calendar.current
        let groups = Dictionary(grouping: filtered) {
            cal.date(from: cal.dateComponents([.year, .month], from: $0.startDate)) ?? $0.startDate
        }
        return groups.keys.sorted(by: >).map { ($0, groups[$0] ?? []) }
    }

    var body: some View {
        NavigationStack {
            Group {
                if entries.isEmpty {
                    ContentUnavailableView("No time logged yet",
                                           systemImage: "clock",
                                           description: Text("Start the timer on the Track tab, or tap + to add time you already did."))
                } else {
                    List {
                        if filtered.isEmpty {
                            ContentUnavailableView(search.isEmpty ? "No entries for this cause" : "No matches",
                                                   systemImage: "magnifyingglass",
                                                   description: Text(search.isEmpty ? "Pick another cause above, or choose All." : "Try a different search."))
                                .listRowBackground(Color.clear)
                        }
                        ForEach(sections, id: \.month) { section in
                            Section {
                                ForEach(section.entries) { entry in
                                    Button { editing = entry } label: { EntryRow(entry: entry) }
                                        .buttonStyle(.plain)
                                        .swipeActions {
                                            if !entry.isLocked {
                                                Button(role: .destructive) { context.delete(entry) } label: {
                                                    Label("Delete", systemImage: "trash")
                                                }
                                            }
                                        }
                                }
                            } header: {
                                HStack {
                                    Text(section.month.formatted(.dateTime.month(.wide).year()))
                                    Spacer()
                                    Text(Fmt.hm(section.entries.reduce(0) { $0 + $1.duration }))
                                        .monospacedDigit()
                                }
                            }
                        }
                    }
                    .searchable(text: $search, prompt: "Search notes or causes")
                }
            }
            .navigationTitle("Log")
            .safeAreaInset(edge: .top, spacing: 0) {
                if !entries.isEmpty && causes.count > 1 {
                    CauseChipBar(causes: causes.filter { !$0.archived }, selection: $filterCauseID, allowsAll: true)
                        .padding(.vertical, 8)
                        .background(.bar)
                }
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showNew = true } label: { Image(systemName: "plus") }
                        .accessibilityLabel("Add time")
                        .disabled(causes.isEmpty)
                }
            }
            .sheet(isPresented: $showNew) {
                EntryEditor(entry: nil, defaultCause: causes.first { $0.uuid == filterCauseID } ?? causes.first { !$0.archived })
            }
            .sheet(item: $editing) { EntryEditor(entry: $0, defaultCause: nil) }
        }
    }
}
