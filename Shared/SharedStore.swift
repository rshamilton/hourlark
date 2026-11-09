import ActivityKit
import Foundation
import UserNotifications
import WidgetKit

// MARK: - Shared types (used by the app, the widgets, and App Intents)

struct SharedCause: Codable, Hashable, Identifiable, Sendable {
    var id: String
    var name: String
    var symbol: String
    var colorName: String
}

struct RunningTimer: Codable, Sendable {
    var cause: SharedCause
    var startDate: Date
}

/// A finished timer session that hasn't been saved into the database yet
/// (for example, stopped from a widget while the app wasn't running).
struct PendingSession: Codable, Identifiable, Sendable {
    var id = UUID()
    var causeID: String
    var start: Date
    var duration: TimeInterval
}

struct WidgetSnapshot: Codable, Sendable {
    var todaySeconds = 0.0
    var weekSeconds = 0.0
    var allSeconds = 0.0
    var causes: [SharedCause] = []
    var computedAt = Date.distantPast
}

struct DisplayTotals: Sendable {
    var today = 0.0
    var week = 0.0
    var all = 0.0
}

// MARK: - App Group storage

enum SharedConfig {
    static let groupID = "group.com.ryanhamilton.hourlark"
    /// Tests swap this for an isolated suite.
    static var defaults = UserDefaults(suiteName: groupID) ?? .standard
}

/// The one place timer state lives, so the app, widgets, Live Activity and Shortcuts all agree.
enum SharedStore {
    static let timerChanged = Notification.Name("com.ryanhamilton.hourlark.timerChanged")

    private enum Keys {
        static let running = "shared.running"
        static let pending = "shared.pending"
        static let snapshot = "shared.snapshot"
    }

    private static var defaults: UserDefaults { SharedConfig.defaults }

    // MARK: Running timer

    static func running() -> RunningTimer? {
        guard let data = defaults.data(forKey: Keys.running) else { return nil }
        return try? JSONDecoder().decode(RunningTimer.self, from: data)
    }

    private static func setRunning(_ timer: RunningTimer?) {
        if let timer, let data = try? JSONEncoder().encode(timer) {
            defaults.set(data, forKey: Keys.running)
        } else {
            defaults.removeObject(forKey: Keys.running)
        }
    }

    /// Starts a timer. If one is already running it is stopped (and queued) first.
    @discardableResult
    static func start(_ cause: SharedCause, at date: Date = .now) -> RunningTimer {
        if running() != nil { stop(at: date) }
        let timer = RunningTimer(cause: cause, startDate: date)
        setRunning(timer)
        notifyChanged()
        return timer
    }

    /// Stops the timer and queues the session, rounded to the nearest minute (minimum one minute).
    @discardableResult
    static func stop(at date: Date = .now) -> PendingSession? {
        guard let r = running() else { return nil }
        let raw = date.timeIntervalSince(r.startDate)
        let session = PendingSession(causeID: r.cause.id, start: r.startDate,
                                     duration: max(60, (raw / 60).rounded() * 60))
        appendPending(session)
        setRunning(nil)
        cancelLongTimerReminder()
        notifyChanged()
        return session
    }

    /// Stops without saving anything.
    static func discardRunning() {
        setRunning(nil)
        cancelLongTimerReminder()
        notifyChanged()
    }

    // MARK: Pending sessions

    static func pending() -> [PendingSession] {
        guard let data = defaults.data(forKey: Keys.pending) else { return [] }
        return (try? JSONDecoder().decode([PendingSession].self, from: data)) ?? []
    }

    private static func setPending(_ sessions: [PendingSession]) {
        if sessions.isEmpty {
            defaults.removeObject(forKey: Keys.pending)
        } else if let data = try? JSONEncoder().encode(sessions) {
            defaults.set(data, forKey: Keys.pending)
        }
    }

    static func appendPending(_ session: PendingSession) {
        setPending(pending() + [session])
    }

    static func clearPending(ids: Set<UUID>) {
        setPending(pending().filter { !ids.contains($0.id) })
    }

    // MARK: Snapshot for widgets

    static func snapshot() -> WidgetSnapshot {
        guard let data = defaults.data(forKey: Keys.snapshot) else { return WidgetSnapshot() }
        return (try? JSONDecoder().decode(WidgetSnapshot.self, from: data)) ?? WidgetSnapshot()
    }

    static func setSnapshot(_ snapshot: WidgetSnapshot) {
        if let data = try? JSONEncoder().encode(snapshot) { defaults.set(data, forKey: Keys.snapshot) }
    }

    /// Snapshot totals plus anything still waiting to be saved, with stale days/weeks zeroed.
    static func displayTotals(now: Date = .now) -> DisplayTotals {
        let snap = snapshot()
        let cal = Calendar.current
        var t = DisplayTotals(today: snap.todaySeconds, week: snap.weekSeconds, all: snap.allSeconds)
        if !cal.isDate(snap.computedAt, inSameDayAs: now) { t.today = 0 }
        if !cal.isDate(snap.computedAt, equalTo: now, toGranularity: .weekOfYear) { t.week = 0 }
        for p in pending() {
            t.all += p.duration
            if cal.isDate(p.start, inSameDayAs: now) { t.today += p.duration }
            if cal.isDate(p.start, equalTo: now, toGranularity: .weekOfYear) { t.week += p.duration }
        }
        return t
    }

    // MARK: Side effects

    /// Tests turn this off so the running app doesn't react to their fake timers.
    static var sendsNotifications = true

    static func notifyChanged() {
        guard sendsNotifications else { return }
        WidgetCenter.shared.reloadAllTimelines()
        NotificationCenter.default.post(name: timerChanged, object: nil)
    }

    private static func cancelLongTimerReminder() {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: ["timer-long"])
    }

    // MARK: Live Activity

    static var liveActivityActive: Bool { !Activity<TimerActivityAttributes>.activities.isEmpty }

    /// Best effort. iOS only lets some processes start activities, so failures are ignored.
    static func startLiveActivity(for timer: RunningTimer) {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        for activity in Activity<TimerActivityAttributes>.activities {
            Task { await activity.end(nil, dismissalPolicy: .immediate) }
        }
        let attributes = TimerActivityAttributes(causeName: timer.cause.name, symbol: timer.cause.symbol,
                                                 colorName: timer.cause.colorName, startDate: timer.startDate)
        _ = try? Activity.request(attributes: attributes, content: .init(state: .init(), staleDate: nil))
    }

    static func endLiveActivities() async {
        for activity in Activity<TimerActivityAttributes>.activities {
            await activity.end(nil, dismissalPolicy: .immediate)
        }
    }
}
