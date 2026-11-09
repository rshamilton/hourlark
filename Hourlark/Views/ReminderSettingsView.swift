import SwiftUI

struct ReminderSettingsView: View {
    @AppStorage(ReminderManager.Keys.dailyOn) private var dailyOn = false
    @AppStorage(ReminderManager.Keys.dailyMinutes) private var minutes = 19 * 60
    @AppStorage(ReminderManager.Keys.dailyDays) private var dayMask = 0b1111111
    @AppStorage(ReminderManager.Keys.longOn) private var longOn = false
    @AppStorage(ReminderManager.Keys.longHours) private var longHours = 4

    @State private var denied = false
    @Environment(\.openURL) private var openURL

    private var timeBinding: Binding<Date> {
        Binding(
            get: { Calendar.current.date(bySettingHour: minutes / 60, minute: minutes % 60, second: 0, of: .now) ?? .now },
            set: { date in
                let c = Calendar.current.dateComponents([.hour, .minute], from: date)
                minutes = (c.hour ?? 19) * 60 + (c.minute ?? 0)
                reapply()
            })
    }

    var body: some View {
        Form {
            if denied {
                Section {
                    Label("Notifications are turned off for Hourlark.", systemImage: "bell.slash.fill")
                        .foregroundStyle(.orange)
                    Button("Open iOS Settings") {
                        if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
                    }
                }
            }

            Section {
                Toggle("Daily reminder", isOn: Binding(
                    get: { dailyOn },
                    set: { newValue in toggle(newValue) { dailyOn = $0; reapply() } }))
                if dailyOn {
                    DatePicker("Time", selection: timeBinding, displayedComponents: .hourAndMinute)
                    HStack(spacing: 6) {
                        ForEach(0..<7, id: \.self) { index in
                            dayButton(index)
                        }
                    }
                    .padding(.vertical, 4)
                }
            } header: {
                Text("Log your hours")
            } footer: {
                Text("A nudge on the days you pick.")
            }

            Section {
                Toggle("Timer running long", isOn: Binding(
                    get: { longOn },
                    set: { newValue in toggle(newValue) { longOn = $0 } }))
                if longOn {
                    Stepper("After \(longHours) hours", value: $longHours, in: 1...12)
                }
            } header: {
                Text("Timer left running")
            } footer: {
                Text("Applies the next time you start the timer.")
            }
        }
        .navigationTitle("Reminders")
        .navigationBarTitleDisplayMode(.inline)
        .task { denied = await ReminderManager.isDenied() }
    }

    private func dayButton(_ index: Int) -> some View {
        let on = dayMask & (1 << index) != 0
        let symbol = Calendar.current.veryShortStandaloneWeekdaySymbols[index]
        return Button {
            dayMask ^= (1 << index)
            if dayMask == 0 { dayMask = 1 << index }
            reapply()
        } label: {
            Text(symbol)
                .font(.subheadline.weight(.semibold))
                .frame(maxWidth: .infinity, minHeight: 36)
                .foregroundStyle(on ? Color.white : Color.primary)
                .background(on ? Color.accentColor : Color(.tertiarySystemFill), in: Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Calendar.current.standaloneWeekdaySymbols[index])
        .accessibilityAddTraits(on ? .isSelected : [])
    }

    private func reapply() {
        ReminderManager.applyDaily(enabled: dailyOn, minutes: minutes, dayMask: dayMask)
    }

    /// Asks for notification permission when turning something on.
    private func toggle(_ newValue: Bool, apply: @escaping (Bool) -> Void) {
        guard newValue else { apply(false); return }
        Task {
            let granted = await ReminderManager.requestAuthorization()
            denied = !granted
            apply(granted)
        }
    }
}
