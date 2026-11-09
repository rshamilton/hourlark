import SwiftUI
import SwiftData
import Charts

enum ReportPeriod: String, CaseIterable, Identifiable {
    case thisMonth = "This month"
    case last30 = "Last 30 days"
    case thisYear = "This year"
    case allTime = "All time"
    case custom = "Custom"

    var id: String { rawValue }
}

struct ReportsView: View {
    @Query(sort: \TimeEntry.startDate) private var allEntries: [TimeEntry]
    @Query(sort: \Cause.name) private var causes: [Cause]

    @AppStorage("participantName") private var participant = ""

    @State private var period: ReportPeriod = .thisMonth
    @State private var customFrom = Calendar.current.date(byAdding: .month, value: -1, to: .now) ?? .now
    @State private var customTo = Date.now
    @State private var causeID: UUID?
    @State private var includeProofs = true
    @State private var exportFile: ExportFile?
    @State private var errorMessage: String?
    @State private var showGuide = false

    private var interval: (from: Date?, to: Date?) {
        let cal = Calendar.current
        switch period {
        case .thisMonth:
            return (cal.date(from: cal.dateComponents([.year, .month], from: .now)), nil)
        case .last30:
            return (cal.date(byAdding: .day, value: -30, to: cal.startOfDay(for: .now)), nil)
        case .thisYear:
            return (cal.date(from: cal.dateComponents([.year], from: .now)), nil)
        case .allTime:
            return (nil, nil)
        case .custom:
            return (cal.startOfDay(for: customFrom), cal.date(byAdding: .day, value: 1, to: cal.startOfDay(for: customTo)))
        }
    }

    private var entries: [TimeEntry] {
        let (from, to) = interval
        return allEntries.filter { e in
            if let causeID, e.cause?.uuid != causeID { return false }
            if let from, e.startDate < from { return false }
            if let to, e.startDate >= to { return false }
            return true
        }
    }

    /// Whether sign-off belongs in this report at all: only when these hours involve a cause that needs it.
    private var signOff: Bool { entries.involvesSignOff }

    /// Why the export buttons are greyed out, if they are.
    private var emptyReason: String? {
        guard entries.isEmpty else { return nil }
        return allEntries.isEmpty
            ? "There are no hours to export yet. Log some time first."
            : "No hours match this period and cause. Try a longer period or All causes."
    }

    private var periodLabel: String {
        let cause = causes.first { $0.uuid == causeID }?.name ?? "All causes"
        let range: String
        switch period {
        case .allTime: range = "All time"
        default:
            let (from, to) = interval
            let lo = from.map(Fmt.date) ?? "start"
            let hi = (to.map { $0.addingTimeInterval(-1) } ?? .now)
            range = "\(lo) – \(Fmt.date(hi))"
        }
        return "\(range) · \(cause)"
    }

    private func seconds(_ status: VerificationStatus?) -> TimeInterval {
        entries.filter { status == nil || $0.status == status }.reduce(0) { $0 + $1.duration }
    }

    private struct Bucket: Identifiable {
        let id = UUID()
        let date: Date
        let status: String
        let hours: Double
    }

    private var chartUnit: Calendar.Component {
        guard let first = entries.first?.startDate, let last = entries.last?.startDate else { return .day }
        return last.timeIntervalSince(first) > 62 * 86_400 ? .month : .day
    }

    private var buckets: [Bucket] {
        let cal = Calendar.current
        let unit = chartUnit
        var sums: [String: Double] = [:]
        var dates: [String: Date] = [:]
        for e in entries {
            let start = cal.dateInterval(of: unit, for: e.startDate)?.start ?? e.startDate
            let key = "\(start.timeIntervalSince1970)|\(e.status.label)"
            sums[key, default: 0] += e.duration / 3600
            dates[key] = start
        }
        return sums.map { key, hours in
            Bucket(date: dates[key] ?? .now, status: String(key.split(separator: "|").last ?? ""), hours: hours)
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Filter") {
                    Picker("Period", selection: $period) {
                        ForEach(ReportPeriod.allCases) { Text($0.rawValue).tag($0) }
                    }
                    if period == .custom {
                        DatePicker("From", selection: $customFrom, displayedComponents: .date)
                        DatePicker("To", selection: $customTo, displayedComponents: .date)
                    }
                    Picker("Cause", selection: $causeID) {
                        Text("All causes").tag(UUID?.none)
                        ForEach(causes) { Text($0.name).tag(Optional($0.uuid)) }
                    }
                }

                Section("Summary") {
                    HStack {
                        StatTile(title: "Total", value: Fmt.hm(seconds(nil)))
                        if signOff {
                            StatTile(title: "Signed", value: Fmt.hm(seconds(.signed)), tint: .green)
                            StatTile(title: "Awaiting", value: Fmt.hm(seconds(.awaitingSignature)), tint: .orange)
                            StatTile(title: "Not sent", value: Fmt.hm(seconds(.notSubmitted)), tint: .secondary)
                        }
                    }
                    if entries.isEmpty {
                        Text("No entries in this range.").foregroundStyle(.secondary)
                    } else {
                        if signOff {
                            Chart(buckets) { b in
                                BarMark(x: .value("Date", b.date, unit: chartUnit == .month ? .month : .day),
                                        y: .value("Hours", b.hours))
                                    .foregroundStyle(by: .value("Status", b.status))
                            }
                            .chartForegroundStyleScale([
                                VerificationStatus.signed.label: Color.green,
                                VerificationStatus.awaitingSignature.label: Color.orange,
                                VerificationStatus.notSubmitted.label: Color.gray,
                                VerificationStatus.notRequired.label: Color.teal
                            ])
                            .chartLegend(position: .bottom)
                            .frame(height: 180)
                            .accessibilityLabel("Hours over time, split by signature status")
                        } else {
                            Chart(buckets) { b in
                                BarMark(x: .value("Date", b.date, unit: chartUnit == .month ? .month : .day),
                                        y: .value("Hours", b.hours))
                                    .foregroundStyle(Color.accentColor)
                            }
                            .frame(height: 180)
                            .accessibilityLabel("Hours over time")
                        }
                    }
                }

                Section {
                    if signOff {
                        Toggle("Attach signed proof at the back", isOn: $includeProofs)
                    }
                    Button { exportPDF() } label: { Label("Export PDF report", systemImage: "doc.richtext") }
                    Button { exportXLSX() } label: { Label("Export Excel workbook (.xlsx)", systemImage: "tablecells.badge.ellipsis") }
                    Button { exportCSV() } label: { Label("Export plain spreadsheet (CSV)", systemImage: "tablecells") }
                } header: {
                    Text("Export")
                } footer: {
                    if let reason = emptyReason {
                        Label(reason, systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                    } else {
                        Text("Made on this iPhone. You choose where they go.")
                    }
                }
                .disabled(entries.isEmpty)
            }
            .navigationTitle("Reports")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showGuide = true } label: { Image(systemName: "questionmark.circle") }
                        .accessibilityLabel("How reports work")
                }
            }
            .sheet(isPresented: $showGuide) { GuideView() }
            .sheet(item: $exportFile) { ShareSheet(url: $0.url).presentationDetents([.medium, .large]) }
            .alert("Couldn't create file", isPresented: .constant(errorMessage != nil)) {
                Button("OK") { errorMessage = nil }
            } message: { Text(errorMessage ?? "") }
        }
    }

    private func exportPDF() {
        let data = PDFReports.report(entries: entries, participant: participant,
                                     periodLabel: periodLabel, includeProofs: includeProofs)
        write(data, name: "Hourlark-Report-\(Fmt.isoDate(.now)).pdf")
    }

    private func exportXLSX() {
        write(XLSXExporter.workbook(for: entries), name: "Hourlark-Hours-\(Fmt.isoDate(.now)).xlsx")
    }

    private func exportCSV() {
        let text = "\u{FEFF}" + CSVExporter.csv(for: entries)
        write(Data(text.utf8), name: "Hourlark-Hours-\(Fmt.isoDate(.now)).csv")
    }

    private func write(_ data: Data, name: String) {
        do { exportFile = ExportFile(url: try TempFiles.write(data, name: name)) }
        catch { errorMessage = error.localizedDescription }
    }
}
