import SwiftUI
import SwiftData

struct TrackView: View {
    @Environment(\.modelContext) private var context
    @Environment(TimerStore.self) private var timer

    @Query(filter: #Predicate<Cause> { $0.archived == false }, sort: \Cause.name)
    private var causes: [Cause]
    @Query(sort: \TimeEntry.startDate, order: .reverse)
    private var entries: [TimeEntry]

    @AppStorage("lastCauseID") private var lastCauseID = ""

    @State private var showManual = false
    @State private var showSettings = false
    @State private var showNewCause = false
    @State private var editing: TimeEntry?
    @State private var pendingSwitch: Cause?

    private var selected: Cause? {
        if timer.isRunning, let running = causes.first(where: { $0.uuid == timer.causeID }) { return running }
        return causes.first { $0.uuid.uuidString == lastCauseID } ?? causes.first
    }

    private var runningName: String {
        causes.first { $0.uuid == timer.causeID }?.name ?? "the timer"
    }

    /// Tapping a chip while the timer runs asks before switching.
    private var selection: Binding<UUID?> {
        Binding(
            get: { selected?.uuid },
            set: { id in
                guard let id, let cause = causes.first(where: { $0.uuid == id }) else { return }
                if timer.isRunning && cause.uuid != timer.causeID {
                    pendingSwitch = cause
                } else {
                    lastCauseID = id.uuidString
                }
            })
    }

    private func seconds(in component: Calendar.Component?) -> TimeInterval {
        let cal = Calendar.current
        return entries.filter { e in
            switch component {
            case .none: true
            case .day: cal.isDateInToday(e.startDate)
            default: cal.isDate(e.startDate, equalTo: .now, toGranularity: .weekOfYear)
            }
        }.reduce(0) { $0 + $1.duration }
    }

    var body: some View {
        NavigationStack {
            Group {
                if causes.isEmpty {
                    EmptyCausesView()
                } else {
                    ScrollView {
                        VStack(spacing: 18) {
                            CauseChipBar(causes: causes, selection: selection) { showNewCause = true }
                            if let cause = selected { hero(cause) }
                            totals
                            if !entries.isEmpty { recent }
                        }
                        .padding(.vertical, 8)
                        .padding(.horizontal, 0)
                    }
                    .background(Color(.systemGroupedBackground))
                }
            }
            .navigationTitle("Hourlark")
            .navigationDestination(for: Cause.self) { CauseDetailView(cause: $0) }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { showSettings = true } label: { Image(systemName: "gearshape") }
                        .accessibilityLabel("Settings")
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showManual = true } label: { Image(systemName: "plus") }
                        .accessibilityLabel("Add time manually")
                        .disabled(causes.isEmpty)
                }
            }
            .sheet(isPresented: $showManual) { EntryEditor(entry: nil, defaultCause: selected) }
            .sheet(isPresented: $showNewCause) { CauseEditor(cause: nil) }
            .sheet(item: $editing) { EntryEditor(entry: $0, defaultCause: nil) }
            .sheet(isPresented: $showSettings) { SettingsView() }
            .sensoryFeedback(.impact(weight: .medium), trigger: timer.isRunning)
            .task { timer.resumeActivityIfNeeded() }
            .confirmationDialog(
                "Switch cause?",
                isPresented: Binding(get: { pendingSwitch != nil }, set: { if !$0 { pendingSwitch = nil } }),
                titleVisibility: .visible,
                presenting: pendingSwitch
            ) { target in
                Button("Save \(runningName) and start \(target.name)") {
                    timer.stop(into: context, causes: causes)
                    timer.start(target)
                    lastCauseID = target.uuid.uuidString
                }
                Button("Cancel", role: .cancel) {}
            } message: { _ in
                Text("The time so far is saved to \(runningName).")
            }
        }
    }

    // MARK: Hero

    private func hero(_ cause: Cause) -> some View {
        let fg = cause.tint.foreground
        return VStack(spacing: 16) {
            HStack(spacing: 8) {
                Image(systemName: cause.symbol)
                Text(cause.name).font(.headline).lineLimit(1)
                Spacer()
                NavigationLink(value: cause) {
                    Image(systemName: "slider.horizontal.3")
                        .imageScale(.medium)
                        .padding(6)
                        .contentShape(Rectangle())
                }
                .accessibilityLabel("Details and settings for \(cause.name)")
                if timer.isRunning {
                    Label("Running", systemImage: "circle.fill")
                        .font(.caption.weight(.semibold))
                        .labelStyle(.titleAndIcon)
                        .symbolEffect(.pulse)
                }
            }
            .foregroundStyle(fg.opacity(0.9))

            TimelineView(.periodic(from: .now, by: 1)) { tl in
                Text(Fmt.clock(timer.elapsed(at: tl.date)))
                    .font(.system(size: 58, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .minimumScaleFactor(0.7)
                    .lineLimit(1)
                    .foregroundStyle(fg)
                    .opacity(timer.isRunning ? 1 : 0.75)
            }

            Button {
                if timer.isRunning {
                    editing = timer.stop(into: context, causes: causes)
                } else {
                    timer.start(cause)
                }
            } label: {
                Label(timer.isRunning ? "Stop" : "Start",
                      systemImage: timer.isRunning ? "stop.fill" : "play.fill")
                    .font(.title3.weight(.bold))
                    .foregroundStyle(cause.tint.swiftUIColor)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(fg, in: Capsule())
            }
            .buttonStyle(.plain)

            if timer.isRunning {
                Button("Discard this session", role: .destructive) { timer.discard() }
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(fg.opacity(0.85))
            }

            if cause.goalHours > 0 {
                VStack(alignment: .leading, spacing: 6) {
                    ProgressView(value: min(cause.totalSeconds / 3600, cause.goalHours), total: cause.goalHours)
                        .tint(fg)
                    Text("\(Fmt.hm(cause.totalSeconds)) of \(String(format: "%g", cause.goalHours)) h goal")
                        .font(.caption).foregroundStyle(fg.opacity(0.85))
                }
            }
        }
        .padding(20)
        .background(cause.tint.swiftUIColor.gradient, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
        .shadow(color: cause.tint.swiftUIColor.opacity(0.35), radius: 16, y: 8)
        .padding(.horizontal, 16)
        .animation(.smooth, value: cause.uuid)
    }

    // MARK: Cards

    private var totals: some View {
        HStack {
            StatTile(title: "Today", value: Fmt.hm(seconds(in: .day)))
            StatTile(title: "This week", value: Fmt.hm(seconds(in: .weekOfYear)))
            StatTile(title: "All time", value: Fmt.hm(seconds(in: nil)))
        }
        .cardStyle()
        .padding(.horizontal, 16)
    }

    private var recent: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Recent").font(.headline).padding(.horizontal, 4)
            VStack(spacing: 0) {
                let items = Array(entries.prefix(5))
                ForEach(Array(items.enumerated()), id: \.element.id) { i, entry in
                    Button { editing = entry } label: {
                        EntryRow(entry: entry)
                            .padding(.vertical, 10)
                            .padding(.horizontal, 16)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    if i < items.count - 1 { Divider().padding(.leading, 64) }
                }
            }
            .background(Color(.secondarySystemGroupedBackground),
                        in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        }
        .padding(.horizontal, 16)
    }
}

/// Shown when there are no causes (for example after skipping onboarding).
struct EmptyCausesView: View {
    @Environment(\.modelContext) private var context
    @State private var showEditor = false

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                Image(systemName: "timer")
                    .font(.system(size: 52))
                    .foregroundStyle(Color.accentColor)
                Text("Add your first cause")
                    .font(.title.bold())
                Text("A cause is anything you track time for: volunteering, a job, a class. Everything stays on this iPhone.")
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
                VStack(spacing: 10) {
                    ForEach(CauseTemplate.all.filter { $0.id != "custom" }) { t in
                        Button {
                            context.insert(t.makeCause())
                        } label: {
                            HStack(spacing: 12) {
                                CauseBadge(symbol: t.symbol, tint: t.tint, size: 36)
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(t.title).font(.headline).foregroundStyle(.primary)
                                    Text(t.blurb).font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer()
                                Image(systemName: "plus.circle.fill").foregroundStyle(Color.accentColor)
                            }
                            .padding(12)
                            .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14))
                        }
                        .buttonStyle(.plain)
                    }
                    Button("Create a custom cause") { showEditor = true }
                        .buttonStyle(.bordered)
                        .padding(.top, 6)
                }
            }
            .padding(24)
        }
        .background(Color(.systemGroupedBackground))
        .sheet(isPresented: $showEditor) { CauseEditor(cause: nil) }
    }
}
