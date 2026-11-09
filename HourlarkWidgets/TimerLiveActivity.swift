import ActivityKit
import AppIntents
import SwiftUI
import WidgetKit

struct TimerLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: TimerActivityAttributes.self) { context in
            LockScreenView(attributes: context.attributes)
        } dynamicIsland: { context in
            let a = context.attributes
            let tint = ActivityTint.color(a.colorName)
            return DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Image(systemName: a.symbol).font(.title2).foregroundStyle(tint)
                }
                DynamicIslandExpandedRegion(.center) {
                    Text(a.causeName).font(.headline).lineLimit(1)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Text(a.startDate, style: .timer)
                        .font(.title3.monospacedDigit().weight(.semibold))
                        .frame(maxWidth: 90, alignment: .trailing)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    Button(intent: StopTimerIntent()) {
                        Label("Stop", systemImage: "stop.fill")
                            .font(.subheadline.weight(.semibold))
                            .frame(maxWidth: .infinity)
                    }
                    .tint(.red)
                }
            } compactLeading: {
                Image(systemName: a.symbol).foregroundStyle(tint)
            } compactTrailing: {
                Text(a.startDate, style: .timer)
                    .monospacedDigit()
                    .frame(maxWidth: 52)
            } minimal: {
                Image(systemName: a.symbol).foregroundStyle(tint)
            }
        }
    }
}

private struct LockScreenView: View {
    let attributes: TimerActivityAttributes

    var body: some View {
        let tint = ActivityTint.color(attributes.colorName)
        VStack(spacing: 12) {
            HStack(spacing: 14) {
                Image(systemName: attributes.symbol)
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(ActivityTint.foreground(attributes.colorName))
                    .frame(width: 46, height: 46)
                    .background(tint.gradient, in: RoundedRectangle(cornerRadius: 13, style: .continuous))
                VStack(alignment: .leading, spacing: 2) {
                    Text(attributes.causeName).font(.headline).lineLimit(1)
                    Text("Tracking time").font(.caption).foregroundStyle(.secondary)
                }
                Spacer(minLength: 8)
                Text(attributes.startDate, style: .timer)
                    .font(.system(.title, design: .rounded).monospacedDigit().weight(.semibold))
                    .multilineTextAlignment(.trailing)
                    .frame(maxWidth: 120, alignment: .trailing)
            }
            Button(intent: StopTimerIntent()) {
                Label("Stop", systemImage: "stop.fill")
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
            }
            .buttonStyle(.borderedProminent)
            .tint(.red)
        }
        .padding(16)
        .activityBackgroundTint(Color(.systemBackground).opacity(0.85))
    }
}
