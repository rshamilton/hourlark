import Foundation

enum CSVExporter {
    static let baseHeader = ["Date", "Start time", "Cause", "Organization", "Hours (decimal)", "Duration (h:mm)", "Notes"]
    static let signOffHeader = ["Status", "Signed by", "Signed on", "Sheet ID"]

    static func csv(for entries: [TimeEntry]) -> String {
        let signOff = entries.involvesSignOff
        let header = baseHeader + (signOff ? signOffHeader : [])
        var lines = [header.map(escape).joined(separator: ",")]
        for e in entries.sorted(by: { $0.startDate < $1.startDate }) {
            let sheet = e.sheet
            var fields: [String] = [
                Fmt.isoDate(e.startDate),
                e.startDate.formatted(date: .omitted, time: .shortened),
                e.cause?.name ?? "",
                e.cause?.organization ?? "",
                Fmt.decimal(e.duration),
                Fmt.colonHM(e.duration),
                e.notes
            ]
            if signOff {
                fields += [
                    e.status.label,
                    sheet?.isSigned == true ? (sheet?.signedBy ?? "") : "",
                    sheet?.signedOn.map(Fmt.isoDate) ?? "",
                    sheet?.shortID ?? ""
                ]
            }
            lines.append(fields.map(escape).joined(separator: ","))
        }
        return lines.joined(separator: "\r\n") + "\r\n"
    }

    static func escape(_ field: String) -> String {
        // Neutralise spreadsheet formula injection, then quote when needed.
        var f = field
        if let first = f.first, "=+-@".contains(first) { f = "'" + f }
        if f.contains(",") || f.contains("\"") || f.contains("\n") || f.contains("\r") {
            return "\"" + f.replacingOccurrences(of: "\"", with: "\"\"") + "\""
        }
        return f
    }
}
