import AppIntents
import SwiftUI
import WidgetKit

struct TimerWidgetEntry: TimelineEntry {
    let date: Date
    let running: RunningTimer?
    let totals: DisplayTotals
    let causes: [SharedCause]
}

struct TimerWidgetProvider: TimelineProvider {
    private func current() -> TimerWidgetEntry {
        TimerWidgetEntry(date: .now, running: SharedStore.running(),
                         totals: SharedStore.displayTotals(), causes: SharedStore.snapshot().causes)
    }

    func placeholder(in context: Context) -> TimerWidgetEntry {
        TimerWidgetEntry(date: .now, running: nil,
                         totals: DisplayTotals(today: 5400, week: 21600, all: 90000),
                         causes: [SharedCause(id: "1", name: "Community Service", symbol: "heart.fill", colorName: "red")])
    }

    func getSnapshot(in context: Context, completion: @escaping (TimerWidgetEntry) -> Void) {
        completion(context.isPreview ? placeholder(in: context) : current())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<TimerWidgetEntry>) -> Void) {
        // The app reloads this whenever data changes; refresh after midnight so "Today" resets.
        let midnight = Calendar.current.nextDate(after: .now, matching: DateComponents(hour: 0, minute: 1),
                                                 matchingPolicy: .nextTime) ?? .now.addingTimeInterval(3600)
        completion(Timeline(entries: [current()], policy: .after(midnight)))
    }
}

struct TimerWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "HourlarkTimerWidget", provider: TimerWidgetProvider()) { entry in
            TimerWidgetView(entry: entry)
        }
        .configurationDisplayName("Hourlark")
        .description("See today's hours and start or stop the timer.")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryRectangular, .accessoryInline])
    }
}

struct TimerWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: TimerWidgetEntry

    private var tint: Color { entry.running.map { ActivityTint.color($0.cause.colorName) } ?? .accentColor }
    private var fg: Color { entry.running.map { ActivityTint.foreground($0.cause.colorName) } ?? .primary }
    private var isAccessory: Bool { family == .accessoryRectangular || family == .accessoryInline }

    var body: some View {
        content
            .containerBackground(for: .widget) {
                if isAccessory {
                    Color.clear
                } else if entry.running != nil {
                    Rectangle().fill(tint.gradient)
                } else {
                    Color(.systemBackground)
                }
            }
    }

    @ViewBuilder
    private var content: some View {
        switch family {
        case .systemMedium: medium
        case .accessoryRectangular: rectangular
        case .accessoryInline: inline
        default: small
        }
    }

    // MARK: Small

    private var small: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let r = entry.running {
                Label(r.cause.name, systemImage: r.cause.symbol)
                    .font(.footnote.weight(.semibold)).lineLimit(1).foregroundStyle(fg.opacity(0.9))
                Text(r.startDate, style: .timer)
                    .font(.system(.title2, design: .rounded).monospacedDigit().weight(.bold))
                    .foregroundStyle(fg)
                Spacer(minLength: 0)
                stopButton
            } else {
                Text("Today").font(.footnote).foregroundStyle(.secondary)
                Text(Fmt.hm(entry.totals.today))
                    .font(.system(.title, design: .rounded).weight(.bold))
                    .minimumScaleFactor(0.7).lineLimit(1)
                Text("Week \(Fmt.hm(entry.totals.week))").font(.caption).foregroundStyle(.secondary)
                Spacer(minLength: 0)
                if let first = entry.causes.first { startButton(first) }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: Medium

    private var medium: some View {
        HStack(alignment: .top, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                if let r = entry.running {
                    Label(r.cause.name, systemImage: r.cause.symbol)
                        .font(.footnote.weight(.semibold)).lineLimit(1).foregroundStyle(fg.opacity(0.9))
                    Text(r.startDate, style: .timer)
                        .font(.system(size: 34, weight: .bold, design: .rounded).monospacedDigit())
                        .foregroundStyle(fg)
                    Spacer(minLength: 0)
                    stopButton
                } else {
                    Text("Today").font(.footnote).foregroundStyle(.secondary)
                    Text(Fmt.hm(entry.totals.today))
                        .font(.system(size: 34, weight: .bold, design: .rounded))
                        .minimumScaleFactor(0.7).lineLimit(1)
                    Text("This week \(Fmt.hm(entry.totals.week))")
                        .font(.caption).foregroundStyle(.secondary)
                    Spacer(minLength: 0)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if entry.running == nil {
                VStack(spacing: 6) {
                    ForEach(entry.causes.prefix(3)) { startButton($0) }
                    if entry.causes.isEmpty {
                        Text("Open Hourlark to add a cause").font(.caption).foregroundStyle(.secondary)
                    }
                }
                .frame(maxWidth: .infinity)
            }
        }
    }

    // MARK: Lock screen

    private var rectangular: some View {
        VStack(alignment: .leading, spacing: 2) {
            if let r = entry.running {
                Label(r.cause.name, systemImage: r.cause.symbol).font(.caption.weight(.semibold)).lineLimit(1)
                Text(r.startDate, style: .timer).font(.title3.monospacedDigit().weight(.semibold))
            } else {
                Label("Hourlark", systemImage: "timer").font(.caption.weight(.semibold))
                Text("Today \(Fmt.hm(entry.totals.today))").font(.title3.weight(.semibold))
                Text("Week \(Fmt.hm(entry.totals.week))").font(.caption)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var inline: some View {
        if let r = entry.running {
            Text("\(Image(systemName: r.cause.symbol)) \(r.startDate, style: .timer)")
        } else {
            Text("\(Image(systemName: "timer")) Today \(Fmt.hm(entry.totals.today))")
        }
    }

    // MARK: Buttons

    private var stopButton: some View {
        Button(intent: StopTimerIntent()) {
            Label("Stop", systemImage: "stop.fill")
                .font(.subheadline.weight(.bold))
                .foregroundStyle(tint)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 7)
                .background(fg, in: Capsule())
        }
        .buttonStyle(.plain)
    }

    private func startButton(_ cause: SharedCause) -> some View {
        let color = ActivityTint.color(cause.colorName)
        return Button(intent: StartTimerIntent(cause: CauseEntity(cause))) {
            HStack(spacing: 6) {
                Image(systemName: cause.symbol).font(.caption.weight(.bold))
                Text(cause.name).font(.caption.weight(.semibold)).lineLimit(1)
                Spacer(minLength: 0)
                Image(systemName: "play.fill").font(.caption2)
            }
            .foregroundStyle(ActivityTint.foreground(cause.colorName))
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .frame(maxWidth: .infinity)
            .background(color.gradient, in: Capsule())
        }
        .buttonStyle(.plain)
    }
}
