import Foundation
import SwiftData
import WidgetKit
import AppIntents

extension SharedCause {
    init(_ cause: Cause) {
        self.init(id: cause.uuid.uuidString, name: cause.name, symbol: cause.symbol, colorName: cause.colorRaw)
    }
}

/// Publishes totals and the cause list to the App Group so widgets can draw them.
@MainActor
enum WidgetSync {
    static func publish(context: ModelContext) {
        let entries = (try? context.fetch(FetchDescriptor<TimeEntry>())) ?? []
        let causes = ((try? context.fetch(FetchDescriptor<Cause>())) ?? []).filter { !$0.archived }
        let cal = Calendar.current
        let now = Date.now

        var snapshot = WidgetSnapshot()
        for e in entries {
            snapshot.allSeconds += e.duration
            if cal.isDate(e.startDate, inSameDayAs: now) { snapshot.todaySeconds += e.duration }
            if cal.isDate(e.startDate, equalTo: now, toGranularity: .weekOfYear) { snapshot.weekSeconds += e.duration }
        }

        // Most recently used causes first, so the widget's buttons are the ones you actually use.
        var lastUsed: [UUID: Date] = [:]
        for e in entries {
            guard let id = e.cause?.uuid else { continue }
            lastUsed[id] = max(lastUsed[id] ?? .distantPast, e.startDate)
        }
        snapshot.causes = causes.sorted {
            let a = lastUsed[$0.uuid] ?? .distantPast, b = lastUsed[$1.uuid] ?? .distantPast
            return a != b ? a > b : $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }.map(SharedCause.init)
        snapshot.computedAt = now

        let causesChanged = snapshot.causes != SharedStore.snapshot().causes
        SharedStore.setSnapshot(snapshot)
        WidgetCenter.shared.reloadAllTimelines()
        // Only tell Siri/Shortcuts when the list of causes actually changed.
        if causesChanged { HourlarkShortcuts.updateAppShortcutParameters() }
    }
}

/// Siri phrases and Shortcuts tiles.
struct HourlarkShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: StartTimerIntent(),
                    phrases: ["Start \(.applicationName) timer for \(\.$cause)",
                              "Track \(\.$cause) in \(.applicationName)"],
                    shortTitle: "Start Timer",
                    systemImageName: "play.fill")
        AppShortcut(intent: StopTimerIntent(),
                    phrases: ["Stop \(.applicationName) timer"],
                    shortTitle: "Stop Timer",
                    systemImageName: "stop.fill")
    }
}
