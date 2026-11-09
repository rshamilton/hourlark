import Foundation

/// Turns time entries into an Excel workbook with an "Entries" sheet and a "Summary" sheet.
enum XLSXExporter {
    static func workbook(for entries: [TimeEntry]) -> Data {
        let sorted = entries.sorted { $0.startDate < $1.startDate }
        let signOff = entries.involvesSignOff

        let entryRows: [[XLSXCell]] = sorted.map { e in
            let sheet = e.sheet
            var row: [XLSXCell] = [
                .date(e.startDate),
                .text(e.startDate.formatted(date: .omitted, time: .shortened)),
                .text(e.cause?.name ?? ""),
                .text(e.cause?.organization ?? ""),
                .number(e.duration / 3600),
                .text(Fmt.colonHM(e.duration)),
                .text(e.notes)
            ]
            if signOff {
                row += [
                    .text(e.status.label),
                    .text(sheet?.isSigned == true ? sheet?.signedBy ?? "" : ""),
                    sheet?.signedOn.map { .date($0) } ?? .empty,
                    .text(sheet?.shortID ?? "")
                ]
            }
            return row
        }

        let entriesSheet = XLSXSheet(
            name: "Entries",
            columns: [("Date", 12), ("Start time", 11), ("Cause", 22), ("Organization", 22), ("Hours", 9),
                      ("Duration (h:mm)", 15), ("Notes", 40)]
                + (signOff ? [("Status", 20), ("Signed by", 18), ("Signed on", 12), ("Sheet ID", 11)] : []),
            rows: entryRows)

        // Summary by cause
        let grouped = Dictionary(grouping: sorted) { $0.cause?.uuid }
        let causes = grouped.values.compactMap { $0.first?.cause }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }

        func hours(_ es: [TimeEntry], _ status: VerificationStatus? = nil) -> Double {
            es.filter { status == nil || $0.status == status }.reduce(0) { $0 + $1.duration } / 3600
        }

        var summaryRows: [[XLSXCell]] = causes.map { c in
            let es = grouped[c.uuid] ?? []
            var row: [XLSXCell] = [.text(c.name), .number(hours(es))]
            if signOff {
                row += [.number(hours(es, .signed)), .number(hours(es, .awaitingSignature)),
                        .number(hours(es, .notSubmitted)), .number(hours(es, .notRequired))]
            }
            return row
        }
        var totalRow: [XLSXCell] = [.boldText("Total"), .boldNumber(hours(sorted))]
        if signOff {
            totalRow += [.boldNumber(hours(sorted, .signed)), .boldNumber(hours(sorted, .awaitingSignature)),
                         .boldNumber(hours(sorted, .notSubmitted)), .boldNumber(hours(sorted, .notRequired))]
        }
        summaryRows.append(totalRow)

        let summarySheet = XLSXSheet(
            name: "Summary",
            columns: [("Cause", 26), ("Total hours", 13)]
                + (signOff ? [("Signed", 11), ("Awaiting signature", 18), ("Not submitted", 14), ("No sign-off needed", 19)] : []),
            rows: summaryRows)

        return XLSXWriter.build(sheets: [entriesSheet, summarySheet])
    }
}
