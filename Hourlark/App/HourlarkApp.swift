import SwiftUI
import SwiftData
import UserNotifications

@main
struct HourlarkApp: App {
    @State private var timer = TimerStore()
    @State private var backup: BackupManager
    @Environment(\.scenePhase) private var scenePhase

    private let container: ModelContainer
    private let notificationDelegate = NotificationDelegate()

    init() {
        let container: ModelContainer
        do {
            // The iCloud entitlement is for backup files in iCloud Drive only. Without this, SwiftData
            // would try to sync the database through CloudKit, which these models aren't built for.
            let config = ModelConfiguration(cloudKitDatabase: .none)
            container = try ModelContainer(for: Cause.self, TimeEntry.self, SignOffSheet.self, ProofImage.self,
                                           configurations: config)
        } catch {
            fatalError("Couldn't open the Hourlark database: \(error)")
        }
        self.container = container
        _backup = State(initialValue: BackupManager(container: container))
        UNUserNotificationCenter.current().delegate = notificationDelegate
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(timer)
                .environment(backup)
        }
        .modelContainer(container)
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .active:
                backup.backupIfStale()
            case .background:
                // Finish any pending backup before iOS suspends the app.
                let id = UIApplication.shared.beginBackgroundTask()
                Task {
                    await backup.flushIfNeeded()
                    UIApplication.shared.endBackgroundTask(id)
                }
            default:
                break
            }
        }
    }
}

struct RootView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.scenePhase) private var scenePhase
    @Environment(TimerStore.self) private var timer
    @Query private var causes: [Cause]
    @Query private var sheets: [SignOffSheet]
    @AppStorage("onboardingDone") private var onboardingDone = false

    /// Picks up changes made outside the app (widget, lock screen, Shortcuts) and refreshes the widgets.
    private func sync() {
        timer.refresh()
        timer.ingestPending(into: context, causes: causes)
        timer.resumeActivityIfNeeded()
        WidgetSync.publish(context: context)
    }

    /// Existing users who already have causes never see onboarding.
    /// The Sign-offs tab only appears when a cause needs sign-off, or sheets already exist.
    private var showSignOffs: Bool {
        !sheets.isEmpty || causes.contains { $0.requiresSignOff && !$0.archived }
    }

    private var showOnboarding: Bool { !onboardingDone && causes.isEmpty }

    var body: some View {
        TabView {
            Tab("Track", systemImage: "timer") { TrackView() }
            Tab("Log", systemImage: "list.bullet.rectangle") { LogView() }
            if showSignOffs {
                Tab("Sign-offs", systemImage: "signature") { SignOffsView() }
            }
            Tab("Reports", systemImage: "chart.bar.doc.horizontal") { ReportsView() }
        }
        .fullScreenCover(isPresented: .constant(showOnboarding)) { OnboardingView() }
        .task { sync() }
        .onChange(of: scenePhase) { _, phase in if phase == .active { sync() } }
        .onReceive(NotificationCenter.default.publisher(for: SharedStore.timerChanged)) { _ in sync() }
        .onReceive(NotificationCenter.default.publisher(for: ModelContext.didSave)) { _ in
            WidgetSync.publish(context: context)
        }
    }
}
