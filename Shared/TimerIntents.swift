import AppIntents
import Foundation

/// A cause, as seen by Shortcuts, Siri and the widgets.
struct CauseEntity: AppEntity {
    static var typeDisplayRepresentation: TypeDisplayRepresentation = "Cause"
    static var defaultQuery = CauseQuery()

    var id: String
    var name: String
    var symbol: String
    var colorName: String

    init(_ cause: SharedCause) {
        id = cause.id
        name = cause.name
        symbol = cause.symbol
        colorName = cause.colorName
    }

    var shared: SharedCause { SharedCause(id: id, name: name, symbol: symbol, colorName: colorName) }

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(name)", image: .init(systemName: symbol))
    }
}

struct CauseQuery: EntityQuery {
    func entities(for identifiers: [String]) async throws -> [CauseEntity] {
        SharedStore.snapshot().causes.filter { identifiers.contains($0.id) }.map(CauseEntity.init)
    }

    func suggestedEntities() async throws -> [CauseEntity] {
        SharedStore.snapshot().causes.map(CauseEntity.init)
    }
}

/// Used by the home-screen widget, Siri and Shortcuts.
struct StartTimerIntent: AppIntent {
    static var title: LocalizedStringResource = "Start Timer"
    static var description = IntentDescription("Starts tracking time for a cause.")

    @Parameter(title: "Cause")
    var cause: CauseEntity

    static var parameterSummary: some ParameterSummary {
        Summary("Start timer for \(\.$cause)")
    }

    init() {}

    init(cause: CauseEntity) {
        self.cause = cause
    }

    func perform() async throws -> some IntentResult {
        let running = SharedStore.start(cause.shared)
        SharedStore.startLiveActivity(for: running)
        return .result()
    }
}

/// A Live Activity intent, so the Stop button on the lock screen runs even when the app is closed.
struct StopTimerIntent: LiveActivityIntent {
    static var title: LocalizedStringResource = "Stop Timer"
    static var description = IntentDescription("Stops the running timer and saves the time.")

    init() {}

    func perform() async throws -> some IntentResult {
        SharedStore.stop()
        await SharedStore.endLiveActivities()
        return .result()
    }
}
