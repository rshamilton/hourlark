import Foundation
import Observation
import SwiftData

/// The running stopwatch. The real state lives in the App Group (`SharedStore`) so widgets,
/// the lock-screen Stop button, Siri and Shortcuts can all start and stop it.
@Observable
final class TimerStore {
    private(set) var startDate: Date?
    private(set) var causeID: UUID?

    init() { refresh() }

    var isRunning: Bool { startDate != nil }

    func elapsed(at now: Date = .now) -> TimeInterval {
        guard let startDate else { return 0 }
        return max(0, now.timeIntervalSince(startDate))
    }

    /// Re-reads shared state (it may have been changed by a widget or Shortcut).
    func refresh() {
        let running = SharedStore.running()
        startDate = running?.startDate
        causeID = running.flatMap { UUID(uuidString: $0.cause.id) }
    }

    @MainActor
    func start(_ cause: Cause) {
        let running = SharedStore.start(SharedCause(cause))
        refresh()
        SharedStore.startLiveActivity(for: running)
        ReminderManager.scheduleLongTimerIfEnabled(causeName: cause.name)
    }

    /// After a relaunch, make sure the lock-screen timer still exists for a running timer.
    @MainActor
    func resumeActivityIfNeeded() {
        guard let running = SharedStore.running(), !SharedStore.liveActivityActive else { return }
        SharedStore.startLiveActivity(for: running)
    }

    /// Stops the timer and saves an entry, rounded to the nearest minute (minimum one minute).
    @MainActor
    @discardableResult
    func stop(into context: ModelContext, causes: [Cause]) -> TimeEntry? {
        guard SharedStore.stop() != nil else { return nil }
        refresh()
        Task { await SharedStore.endLiveActivities() }
        // The session was just queued; save it now and remove it from the queue.
        return ingestPending(into: context, causes: causes).last
    }

    @MainActor
    func discard() {
        SharedStore.discardRunning()
        refresh()
        Task { await SharedStore.endLiveActivities() }
    }

    /// Saves sessions that were stopped outside the app (widget, Live Activity, Shortcuts).
    @MainActor
    @discardableResult
    func ingestPending(into context: ModelContext, causes: [Cause]) -> [TimeEntry] {
        let sessions = SharedStore.pending()
        guard !sessions.isEmpty else { return [] }
        var created: [TimeEntry] = []
        for s in sessions {
            guard let cause = causes.first(where: { $0.uuid.uuidString == s.causeID }) else { continue }
            let entry = TimeEntry(startDate: s.start, duration: s.duration)
            context.insert(entry)
            entry.cause = cause
            created.append(entry)
        }
        // Sessions for causes that no longer exist are dropped rather than retried forever.
        SharedStore.clearPending(ids: Set(sessions.map(\.id)))
        return created
    }
}
