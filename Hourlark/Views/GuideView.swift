import SwiftUI

/// A short walkthrough of printing, signing and exporting. It opens on "what do you need?" so it
/// reads as optional and for everyone: signatures, plain reports and spreadsheets are separate paths.
struct GuideView: View {
    @Environment(\.dismiss) private var dismiss

    enum Need: String, CaseIterable, Identifiable {
        case signed = "Get hours signed"
        case report = "Make a report"
        case sheet = "Spreadsheet"

        var id: String { rawValue }

        var symbol: String {
            switch self {
            case .signed: "signature"
            case .report: "doc.richtext"
            case .sheet: "tablecells"
            }
        }

        var intro: String {
            switch self {
            case .signed:
                "For school, court, scholarships or any group that wants proof. A supervisor signs a printed sheet, and a photo of it is kept with your hours."
            case .report:
                "A tidy PDF of your hours for a boss, teacher or your own records. No signature needed."
            case .sheet:
                "Your hours as a file for Excel, Numbers or Google Sheets."
            }
        }

        var steps: [Step] {
            switch self {
            case .signed:
                [
                    Step("slider.horizontal.3", "Turn on sign-off", "On the Track tab, tap the sliders button on your cause, then Edit, and switch on “Needs to be signed off”. The Sign-offs tab appears."),
                    Step("timer", "Log your hours", "Use the timer on the Track tab, or tap + to add time you did earlier."),
                    Step("signature", "Create a sheet", "Open the Sign-offs tab and tap +. Choose the cause and dates, and the hours are listed for you."),
                    Step("printer", "Print it", "On the sheet, tap “Print or share sheet (PDF)”. Print it, or send it to whoever signs."),
                    Step("pencil.and.scribble", "Get it signed", "Your supervisor signs the paper. Nothing else is needed from them, and they never need the app."),
                    Step("doc.viewfinder", "Photograph it", "Back on the sheet, tap “Scan signed sheet” or choose a photo. The proof stays with your hours."),
                    Step("checkmark.seal", "Mark it signed", "Those hours turn green and lock, so they always match the paper."),
                    Step("doc.richtext", "Export when you need it", "Reports can attach every signed photo at the back of the PDF.")
                ]
            case .report:
                [
                    Step("timer", "Log your hours", "Use the timer on the Track tab, or tap + to add time."),
                    Step("chart.bar.doc.horizontal", "Open Reports", "Pick a period and, if you like, a single cause."),
                    Step("doc.richtext", "Export PDF report", "Tap “Export PDF report”. Turn off the proof switch if you don't have any."),
                    Step("square.and.arrow.up", "Share or save it", "Send it by Messages or Mail, print it, or save it to Files.")
                ]
            case .sheet:
                [
                    Step("timer", "Log your hours", "Use the timer on the Track tab, or tap + to add time."),
                    Step("chart.bar.doc.horizontal", "Open Reports", "Pick a period and, if you like, a single cause."),
                    Step("tablecells.badge.ellipsis", "Choose a format", "Excel (.xlsx) opens in Excel, Numbers and Sheets. CSV works almost everywhere."),
                    Step("square.and.arrow.up", "Share or save it", "AirDrop it, email it, or save it to Files.")
                ]
            }
        }
    }

    struct Step: Identifiable {
        let id = UUID()
        let symbol: String
        let title: String
        let detail: String
        init(_ symbol: String, _ title: String, _ detail: String) {
            self.symbol = symbol; self.title = title; self.detail = detail
        }
    }

    @State private var need: Need = .report

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Hourlark works for everyone")
                            .font(.title2.bold())
                        Text("Signatures are optional. Pick what you need. You can change your mind for any cause at any time.")
                            .foregroundStyle(.secondary)
                    }

                    Picker("What do you need?", selection: $need) {
                        ForEach(Need.allCases) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.segmented)

                    Label {
                        Text(need.intro).font(.subheadline)
                    } icon: {
                        Image(systemName: need.symbol).foregroundStyle(Color.accentColor)
                    }
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16, style: .continuous))

                    VStack(alignment: .leading, spacing: 0) {
                        let steps = need.steps
                        ForEach(Array(steps.enumerated()), id: \.element.id) { i, step in
                            HStack(alignment: .top, spacing: 14) {
                                ZStack {
                                    Circle().fill(Color.accentColor.opacity(0.15)).frame(width: 40, height: 40)
                                    Image(systemName: step.symbol).foregroundStyle(Color.accentColor)
                                }
                                VStack(alignment: .leading, spacing: 3) {
                                    Text("\(i + 1). \(step.title)").font(.headline)
                                    Text(step.detail).font(.subheadline).foregroundStyle(.secondary)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                                Spacer(minLength: 0)
                            }
                            .padding(.vertical, 10)
                            .accessibilityElement(children: .combine)
                        }
                    }

                    Label("Everything here happens on your iPhone. Nothing is uploaded or shared unless you choose to send a file yourself.",
                          systemImage: "lock.shield.fill")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                .padding(20)
                .animation(.smooth, value: need)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("How it works")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
        }
    }
}
