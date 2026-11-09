import UIKit

enum PDFReports {
    private static let title = UIFont.systemFont(ofSize: 22, weight: .bold)
    private static let heading = UIFont.systemFont(ofSize: 13, weight: .semibold)
    private static let small = UIFont.systemFont(ofSize: 9)

    // MARK: Sign-off sheet (the page you print and get signed)

    static func signOffSheet(_ sheet: SignOffSheet, participant: String) -> Data {
        let c = PDFComposer()
        c.footerText = "Hourlark verification sheet \(sheet.shortID)"
        return c.render { c in
            c.text("Hours Verification Sheet", font: title, after: 2)
            c.text("Sheet ID \(sheet.shortID)  ·  Generated \(Fmt.date(.now))", font: small, color: .darkGray, after: 12)
            c.rule()

            let cause = sheet.cause
            c.keyValue("Participant", participant.isEmpty ? "______________________________" : participant)
            c.keyValue("Activity / cause", cause?.name ?? "—")
            if let org = cause?.organization, !org.isEmpty { c.keyValue("Organization", org) }
            if !sheet.verifierName.isEmpty { c.keyValue("Verifier", sheet.verifierName) }
            c.keyValue("Period", "\(Fmt.date(sheet.rangeStart)) – \(Fmt.date(sheet.rangeEnd))")
            c.space(8)

            c.beginTable([
                .init(title: "Date", width: 84),
                .init(title: "Description", width: 288),
                .init(title: "Hours", width: 66, align: .right),
                .init(title: "Decimal", width: 66, align: .right)
            ])
            for (i, e) in sheet.sortedEntries.enumerated() {
                c.row([Fmt.date(e.startDate),
                       e.notes.isEmpty ? "—" : e.notes,
                       Fmt.colonHM(e.duration),
                       Fmt.decimal(e.duration)], shaded: i % 2 == 1)
            }
            c.row(["", "Total", Fmt.colonHM(sheet.totalSeconds), Fmt.decimal(sheet.totalSeconds)], bold: true)
            c.endTable()

            c.space(18)
            c.ensure(190)
            c.text("Verification", font: heading, after: 4)
            c.text("I certify that the hours listed above were completed as described.",
                   font: .systemFont(ofSize: 11), after: 6)
            c.signatureRow([("Signature", 290), ("Date", 160)])
            c.signatureRow([("Printed name", 290), ("Title", 160)])
            c.signatureRow([("Phone or email (optional)", 468)])
        }
    }

    // MARK: Full report

    static func report(entries: [TimeEntry],
                       participant: String,
                       periodLabel: String,
                       includeProofs: Bool) -> Data {
        let sorted = entries.sorted { $0.startDate < $1.startDate }
        let signOff = entries.involvesSignOff
        let c = PDFComposer()
        c.footerText = "Hourlark report  ·  \(Fmt.date(.now))"

        return c.render { c in
            c.text("Hours Report", font: title, after: 2)
            c.text("Generated \(Fmt.date(.now))", font: small, color: .darkGray, after: 12)
            c.rule()
            c.keyValue("Participant", participant.isEmpty ? "—" : participant)
            c.keyValue("Period", periodLabel)
            c.space(10)

            // Summary by cause
            c.text("Summary", font: heading, after: 4)
            c.beginTable(signOff ? [
                .init(title: "Cause", width: 170),
                .init(title: "Total", width: 66, align: .right),
                .init(title: "Signed", width: 66, align: .right),
                .init(title: "Awaiting", width: 66, align: .right),
                .init(title: "Not sent", width: 66, align: .right),
                .init(title: "Decimal", width: 70, align: .right)
            ] : [
                .init(title: "Cause", width: 300),
                .init(title: "Total", width: 110, align: .right),
                .init(title: "Decimal", width: 110, align: .right)
            ])
            let byCause = Dictionary(grouping: sorted) { $0.cause?.uuid }
            let causes = byCause.values
                .compactMap { $0.first?.cause }
                .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
            for cause in causes {
                let es = byCause[cause.uuid] ?? []
                c.row(signOff
                      ? [cause.name, Fmt.colonHM(sum(es)), Fmt.colonHM(sum(es, .signed)),
                         Fmt.colonHM(sum(es, .awaitingSignature)), Fmt.colonHM(sum(es, .notSubmitted)),
                         Fmt.decimal(sum(es))]
                      : [cause.name, Fmt.colonHM(sum(es)), Fmt.decimal(sum(es))])
            }
            c.row(signOff
                  ? ["All causes", Fmt.colonHM(sum(sorted)), Fmt.colonHM(sum(sorted, .signed)),
                     Fmt.colonHM(sum(sorted, .awaitingSignature)), Fmt.colonHM(sum(sorted, .notSubmitted)),
                     Fmt.decimal(sum(sorted))]
                  : ["All causes", Fmt.colonHM(sum(sorted)), Fmt.decimal(sum(sorted))], bold: true)
            c.endTable()

            // Detail
            c.space(16)
            c.text("Entries", font: heading, after: 4)
            c.beginTable(signOff ? [
                .init(title: "Date", width: 70),
                .init(title: "Cause", width: 105),
                .init(title: "Notes", width: 167),
                .init(title: "Hours", width: 46, align: .right),
                .init(title: "Status", width: 116)
            ] : [
                .init(title: "Date", width: 76),
                .init(title: "Cause", width: 130),
                .init(title: "Notes", width: 262),
                .init(title: "Hours", width: 36, align: .right)
            ])
            for (i, e) in sorted.enumerated() {
                var status = e.status.label
                if e.status == .signed, let s = e.sheet { status += " (\(s.shortID))" }
                let cells = [Fmt.date(e.startDate), e.cause?.name ?? "—", e.notes, Fmt.colonHM(e.duration)]
                c.row(signOff ? cells + [status] : cells, shaded: i % 2 == 1)
            }
            c.endTable()

            // Proof of signature attached at the back
            guard signOff, includeProofs else { return }
            let sheets = Dictionary(grouping: sorted.compactMap(\.sheet)) { $0.uuid }
                .values.compactMap(\.first)
                .filter { !$0.proofs.isEmpty }
                .sorted { $0.createdAt < $1.createdAt }
            for sheet in sheets {
                for (index, proof) in sheet.sortedProofs.enumerated() {
                    guard let image = UIImage(data: proof.data) else { continue }
                    c.newPage()
                    c.text("Proof of signature", font: heading, after: 2)
                    var detail = "\(sheet.cause?.name ?? "—") · \(Fmt.date(sheet.rangeStart)) – \(Fmt.date(sheet.rangeEnd)) · "
                    detail += "\(Fmt.colonHM(sheet.totalSeconds)) h · sheet \(sheet.shortID)"
                    c.text(detail, font: small, color: .darkGray, after: 2)
                    if sheet.isSigned, let on = sheet.signedOn {
                        let by = sheet.signedBy.isEmpty ? "" : " by \(sheet.signedBy)"
                        c.text("Signed\(by) on \(Fmt.date(on)) · page \(index + 1) of \(sheet.proofs.count)",
                               font: small, color: .darkGray, after: 8)
                    } else {
                        c.text("Not yet marked signed · page \(index + 1) of \(sheet.proofs.count)",
                               font: small, color: .darkGray, after: 8)
                    }
                    c.imageFittingPage(image)
                }
            }
        }
    }

    private static func sum(_ entries: [TimeEntry], _ status: VerificationStatus? = nil) -> TimeInterval {
        entries.filter { status == nil || $0.status == status }.reduce(0) { $0 + $1.duration }
    }
}
