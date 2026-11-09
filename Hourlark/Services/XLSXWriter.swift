import Foundation

/// Minimal .xlsx writer with no dependencies: XML parts packed into an uncompressed ZIP.
enum XLSXCell {
    case text(String)
    case number(Double)
    /// A calendar date, shown in the user's local time zone.
    case date(Date)
    case boldText(String)
    case boldNumber(Double)
    case empty
}

struct XLSXSheet {
    var name: String
    var columns: [(title: String, width: Double)]
    var rows: [[XLSXCell]]
}

enum XLSXWriter {
    static func build(sheets: [XLSXSheet]) -> Data {
        var zip = ZipWriter()
        zip.add("[Content_Types].xml", contentTypes(sheetCount: sheets.count))
        zip.add("_rels/.rels", rootRels)
        zip.add("xl/workbook.xml", workbook(sheets))
        zip.add("xl/_rels/workbook.xml.rels", workbookRels(sheetCount: sheets.count))
        zip.add("xl/styles.xml", styles)
        for (i, sheet) in sheets.enumerated() {
            zip.add("xl/worksheets/sheet\(i + 1).xml", worksheet(sheet))
        }
        return zip.finish()
    }

    // MARK: Parts

    private static let header = #"<?xml version="1.0" encoding="UTF-8" standalone="yes"?>"#

    private static func contentTypes(sheetCount: Int) -> String {
        var s = header + #"<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">"#
        s += #"<Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>"#
        s += #"<Default Extension="xml" ContentType="application/xml"/>"#
        s += #"<Override PartName="/xl/workbook.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"/>"#
        s += #"<Override PartName="/xl/styles.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.styles+xml"/>"#
        for i in 1...max(sheetCount, 1) {
            s += #"<Override PartName="/xl/worksheets/sheet\#(i).xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/>"#
        }
        return s + "</Types>"
    }

    private static let rootRels = header + #"<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="xl/workbook.xml"/></Relationships>"#

    private static func workbook(_ sheets: [XLSXSheet]) -> String {
        var s = header + #"<workbook xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships"><sheets>"#
        for (i, sheet) in sheets.enumerated() {
            s += #"<sheet name="\#(escape(sheetName(sheet.name)))" sheetId="\#(i + 1)" r:id="rId\#(i + 1)"/>"#
        }
        return s + "</sheets></workbook>"
    }

    private static func workbookRels(sheetCount: Int) -> String {
        var s = header + #"<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">"#
        for i in 1...max(sheetCount, 1) {
            s += #"<Relationship Id="rId\#(i)" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" Target="worksheets/sheet\#(i).xml"/>"#
        }
        s += #"<Relationship Id="rId\#(sheetCount + 1)" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles" Target="styles.xml"/>"#
        return s + "</Relationships>"
    }

    /// Style indexes: 0 normal, 1 header, 2 date, 3 decimal, 4 bold text, 5 bold decimal.
    private static let styles = header + """
    <styleSheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">\
    <numFmts count="2"><numFmt numFmtId="164" formatCode="yyyy\\-mm\\-dd"/><numFmt numFmtId="165" formatCode="0.00"/></numFmts>\
    <fonts count="2"><font><sz val="11"/><name val="Calibri"/></font><font><b/><sz val="11"/><name val="Calibri"/></font></fonts>\
    <fills count="3"><fill><patternFill patternType="none"/></fill><fill><patternFill patternType="gray125"/></fill>\
    <fill><patternFill patternType="solid"><fgColor rgb="FFD9EEF0"/><bgColor indexed="64"/></patternFill></fill></fills>\
    <borders count="1"><border><left/><right/><top/><bottom/><diagonal/></border></borders>\
    <cellStyleXfs count="1"><xf numFmtId="0" fontId="0" fillId="0" borderId="0"/></cellStyleXfs>\
    <cellXfs count="6">\
    <xf numFmtId="0" fontId="0" fillId="0" borderId="0" xfId="0"/>\
    <xf numFmtId="0" fontId="1" fillId="2" borderId="0" xfId="0" applyFont="1" applyFill="1"/>\
    <xf numFmtId="164" fontId="0" fillId="0" borderId="0" xfId="0" applyNumberFormat="1"/>\
    <xf numFmtId="165" fontId="0" fillId="0" borderId="0" xfId="0" applyNumberFormat="1"/>\
    <xf numFmtId="0" fontId="1" fillId="0" borderId="0" xfId="0" applyFont="1"/>\
    <xf numFmtId="165" fontId="1" fillId="0" borderId="0" xfId="0" applyNumberFormat="1" applyFont="1"/>\
    </cellXfs>\
    <cellStyles count="1"><cellStyle name="Normal" xfId="0" builtinId="0"/></cellStyles>\
    </styleSheet>
    """

    private static func worksheet(_ sheet: XLSXSheet) -> String {
        var s = header + #"<worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">"#
        s += #"<sheetViews><sheetView workbookViewId="0"><pane ySplit="1" topLeftCell="A2" activePane="bottomLeft" state="frozen"/></sheetView></sheetViews>"#
        s += "<cols>"
        for (i, col) in sheet.columns.enumerated() {
            s += #"<col min="\#(i + 1)" max="\#(i + 1)" width="\#(col.width)" customWidth="1"/>"#
        }
        s += "</cols><sheetData>"

        s += #"<row r="1">"#
        for (i, col) in sheet.columns.enumerated() {
            s += cell(ref: ref(col: i, row: 1), .text(col.title), style: 1)
        }
        s += "</row>"

        for (r, row) in sheet.rows.enumerated() {
            let rowNumber = r + 2
            s += #"<row r="\#(rowNumber)">"#
            for (c, value) in row.enumerated() {
                s += cell(ref: ref(col: c, row: rowNumber), value)
            }
            s += "</row>"
        }
        s += "</sheetData>"
        if !sheet.rows.isEmpty && sheet.columns.count > 0 {
            s += #"<autoFilter ref="A1:\#(ref(col: sheet.columns.count - 1, row: sheet.rows.count + 1))"/>"#
        }
        return s + "</worksheet>"
    }

    private static func cell(ref: String, _ value: XLSXCell, style: Int? = nil) -> String {
        switch value {
        case .empty:
            return ""
        case .text(let t):
            return inline(ref, t, style: style ?? 0)
        case .boldText(let t):
            return inline(ref, t, style: 4)
        case .number(let n):
            return #"<c r="\#(ref)" s="3"><v>\#(n)</v></c>"#
        case .boldNumber(let n):
            return #"<c r="\#(ref)" s="5"><v>\#(n)</v></c>"#
        case .date(let d):
            return #"<c r="\#(ref)" s="2"><v>\#(serial(d))</v></c>"#
        }
    }

    private static func inline(_ ref: String, _ text: String, style: Int) -> String {
        #"<c r="\#(ref)" t="inlineStr" s="\#(style)"><is><t xml:space="preserve">\#(escape(text))</t></is></c>"#
    }

    // MARK: Helpers

    /// Column index 0 → "A", 26 → "AA".
    static func ref(col: Int, row: Int) -> String {
        var n = col + 1
        var letters = ""
        while n > 0 {
            let r = (n - 1) % 26
            letters = String(UnicodeScalar(UInt8(65 + r))) + letters
            n = (n - 1) / 26
        }
        return "\(letters)\(row)"
    }

    /// Excel date serial for the local calendar day of `date`.
    static func serial(_ date: Date) -> Int {
        let c = Calendar.current.dateComponents([.year, .month, .day], from: date)
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = TimeZone(identifier: "UTC") ?? .gmt
        let day = utc.date(from: c) ?? date
        return Int(floor(day.timeIntervalSince1970 / 86_400)) + 25_569
    }

    static func escape(_ s: String) -> String {
        var out = ""
        for scalar in s.unicodeScalars {
            switch scalar {
            case "&": out += "&amp;"
            case "<": out += "&lt;"
            case ">": out += "&gt;"
            case "\"": out += "&quot;"
            default:
                // XML 1.0 forbids most control characters.
                if scalar.value >= 0x20 || scalar == "\n" || scalar == "\t" { out.unicodeScalars.append(scalar) }
            }
        }
        return out
    }

    /// Sheet names: max 31 chars, none of  : \ / ? * [ ]
    private static func sheetName(_ name: String) -> String {
        let cleaned = name.filter { !":\\/?*[]".contains($0) }
        return String(cleaned.prefix(31))
    }
}

// MARK: - ZIP (stored, no compression)

struct ZipWriter {
    private var body = Data()
    private var central = Data()
    private var count: UInt16 = 0

    mutating func add(_ name: String, _ text: String) {
        add(name, Data(text.utf8))
    }

    mutating func add(_ name: String, _ data: Data) {
        let nameBytes = Data(name.utf8)
        let crc = Self.crc32(data)
        let offset = UInt32(body.count)
        let dosTime: UInt16 = 0
        let dosDate: UInt16 = ((2026 - 1980) << 9) | (1 << 5) | 1

        body.append(le32(0x0403_4B50))
        body.append(le16(20))
        body.append(le16(0x0800))
        body.append(le16(0))
        body.append(le16(dosTime))
        body.append(le16(dosDate))
        body.append(le32(crc))
        body.append(le32(UInt32(data.count)))
        body.append(le32(UInt32(data.count)))
        body.append(le16(UInt16(nameBytes.count)))
        body.append(le16(0))
        body.append(nameBytes)
        body.append(data)

        central.append(le32(0x0201_4B50))
        central.append(le16(20))
        central.append(le16(20))
        central.append(le16(0x0800))
        central.append(le16(0))
        central.append(le16(dosTime))
        central.append(le16(dosDate))
        central.append(le32(crc))
        central.append(le32(UInt32(data.count)))
        central.append(le32(UInt32(data.count)))
        central.append(le16(UInt16(nameBytes.count)))
        central.append(le16(0))
        central.append(le16(0))
        central.append(le16(0))
        central.append(le16(0))
        central.append(le32(0))
        central.append(le32(offset))
        central.append(nameBytes)
        count += 1
    }

    func finish() -> Data {
        var out = body
        let cdOffset = UInt32(out.count)
        out.append(central)
        out.append(le32(0x0605_4B50))
        out.append(le16(0))
        out.append(le16(0))
        out.append(le16(count))
        out.append(le16(count))
        out.append(le32(UInt32(central.count)))
        out.append(le32(cdOffset))
        out.append(le16(0))
        return out
    }

    private func le16(_ v: UInt16) -> Data { withUnsafeBytes(of: v.littleEndian) { Data($0) } }
    private func le32(_ v: UInt32) -> Data { withUnsafeBytes(of: v.littleEndian) { Data($0) } }

    private static let table: [UInt32] = (0..<256).map { i -> UInt32 in
        var c = UInt32(i)
        for _ in 0..<8 { c = (c & 1) != 0 ? (0xEDB8_8320 ^ (c >> 1)) : (c >> 1) }
        return c
    }

    static func crc32(_ data: Data) -> UInt32 {
        var c: UInt32 = 0xFFFF_FFFF
        for byte in data { c = table[Int((c ^ UInt32(byte)) & 0xFF)] ^ (c >> 8) }
        return c ^ 0xFFFF_FFFF
    }
}
