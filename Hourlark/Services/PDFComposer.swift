import UIKit

/// A tiny top-to-bottom PDF layout engine (US Letter) with automatic page breaks.
final class PDFComposer {
    static let pageSize = CGSize(width: 612, height: 792)
    let margin: CGFloat = 54

    var footerText = ""

    private var ctx: UIGraphicsPDFRendererContext!
    private(set) var y: CGFloat = 0
    private(set) var pageNumber = 0
    private var tableHeader: [Column]?

    struct Column {
        var title: String
        var width: CGFloat
        var align: NSTextAlignment = .left
    }

    var contentWidth: CGFloat { Self.pageSize.width - margin * 2 }
    private var bottomLimit: CGFloat { Self.pageSize.height - margin - 14 }
    var remainingHeight: CGFloat { bottomLimit - y }

    func render(_ draw: (PDFComposer) -> Void) -> Data {
        let format = UIGraphicsPDFRendererFormat()
        format.documentInfo = [
            kCGPDFContextCreator as String: "Hourlark",
            kCGPDFContextTitle as String: footerText
        ]
        let renderer = UIGraphicsPDFRenderer(bounds: CGRect(origin: .zero, size: Self.pageSize), format: format)
        return renderer.pdfData { context in
            self.ctx = context
            self.pageNumber = 0
            self.newPage()
            draw(self)
            self.drawFooter()
        }
    }

    func newPage() {
        if pageNumber > 0 { drawFooter() }
        ctx.beginPage()
        pageNumber += 1
        y = margin
    }

    func space(_ h: CGFloat) { y += h }

    func ensure(_ h: CGFloat) {
        if y + h > bottomLimit { newPage() }
    }

    @discardableResult
    func text(_ s: String,
              font: UIFont = .systemFont(ofSize: 11),
              color: UIColor = .black,
              align: NSTextAlignment = .left,
              after: CGFloat = 4,
              x: CGFloat? = nil,
              width: CGFloat? = nil,
              advance: Bool = true) -> CGFloat {
        let attrs = attributes(font: font, color: color, align: align)
        let w = width ?? contentWidth
        let h = height(of: s, width: w, attrs: attrs)
        if advance { ensure(h) }
        (s as NSString).draw(in: CGRect(x: x ?? margin, y: y, width: w, height: h), withAttributes: attrs)
        if advance { y += h + after }
        return h
    }

    /// "Label   Value" on one line.
    func keyValue(_ key: String, _ value: String, keyWidth: CGFloat = 110) {
        let keyFont = UIFont.systemFont(ofSize: 11, weight: .semibold)
        let valFont = UIFont.systemFont(ofSize: 11)
        let h1 = height(of: key, width: keyWidth, attrs: attributes(font: keyFont, color: .darkGray, align: .left))
        let h2 = height(of: value, width: contentWidth - keyWidth, attrs: attributes(font: valFont, color: .black, align: .left))
        let h = max(h1, h2)
        ensure(h)
        text(key, font: keyFont, color: .darkGray, x: margin, width: keyWidth, advance: false)
        text(value, font: valFont, x: margin + keyWidth, width: contentWidth - keyWidth, advance: false)
        y += h + 3
    }

    func rule(color: UIColor = .lightGray, after: CGFloat = 6) {
        ensure(2)
        let path = UIBezierPath()
        path.move(to: CGPoint(x: margin, y: y))
        path.addLine(to: CGPoint(x: margin + contentWidth, y: y))
        color.setStroke()
        path.lineWidth = 0.5
        path.stroke()
        y += after
    }

    /// Draws a labelled blank line (for handwritten signatures etc.). Columns are (label, width).
    func signatureRow(_ fields: [(String, CGFloat)], lineHeight: CGFloat = 34) {
        ensure(lineHeight + 16)
        var x = margin
        let lineY = y + lineHeight
        for (label, width) in fields {
            let path = UIBezierPath()
            path.move(to: CGPoint(x: x, y: lineY))
            path.addLine(to: CGPoint(x: x + width, y: lineY))
            UIColor.black.setStroke()
            path.lineWidth = 0.75
            path.stroke()
            (label as NSString).draw(
                in: CGRect(x: x, y: lineY + 2, width: width, height: 14),
                withAttributes: attributes(font: .systemFont(ofSize: 9), color: .darkGray, align: .left)
            )
            x += width + 18
        }
        y = lineY + 20
    }

    // MARK: Tables

    func beginTable(_ columns: [Column]) {
        tableHeader = columns
        drawHeaderRow(columns)
    }

    func endTable() { tableHeader = nil }

    private func drawHeaderRow(_ columns: [Column]) {
        let font = UIFont.systemFont(ofSize: 9.5, weight: .bold)
        var x = margin
        let h: CGFloat = 16
        ensureRaw(h)
        UIColor(white: 0.92, alpha: 1).setFill()
        UIBezierPath(rect: CGRect(x: margin, y: y, width: contentWidth, height: h)).fill()
        for col in columns {
            text(col.title.uppercased(), font: font, color: .darkGray, align: col.align,
                 x: x + 3, width: col.width - 6, advance: false, yOffset: 3)
            x += col.width
        }
        y += h + 2
    }

    func row(_ cells: [String], bold: Bool = false, shaded: Bool = false) {
        guard let columns = tableHeader, columns.count == cells.count else { return }
        let font = UIFont.systemFont(ofSize: 10, weight: bold ? .bold : .regular)
        let heights = zip(cells, columns).map {
            height(of: $0, width: $1.width - 6, attrs: attributes(font: font, color: .black, align: $1.align))
        }
        let h = (heights.max() ?? 12) + 6
        if y + h > bottomLimit {
            newPage()
            drawHeaderRow(columns)
        }
        if shaded {
            UIColor(white: 0.96, alpha: 1).setFill()
            UIBezierPath(rect: CGRect(x: margin, y: y, width: contentWidth, height: h)).fill()
        }
        var x = margin
        for (cell, col) in zip(cells, columns) {
            text(cell, font: font, color: .black, align: col.align, x: x + 3, width: col.width - 6, advance: false, yOffset: 3)
            x += col.width
        }
        y += h
        UIColor(white: 0.85, alpha: 1).setStroke()
        let line = UIBezierPath()
        line.move(to: CGPoint(x: margin, y: y))
        line.addLine(to: CGPoint(x: margin + contentWidth, y: y))
        line.lineWidth = 0.4
        line.stroke()
    }

    // MARK: Images

    /// Draws an image scaled to fit the remaining page area (starting a new page if too little room).
    func imageFittingPage(_ image: UIImage) {
        if remainingHeight < 200 { newPage() }
        let maxW = contentWidth
        let maxH = remainingHeight
        let scale = min(maxW / image.size.width, maxH / image.size.height, 1.5)
        let w = image.size.width * scale, h = image.size.height * scale
        let rect = CGRect(x: margin + (maxW - w) / 2, y: y, width: w, height: h)
        image.draw(in: rect)
        UIColor.lightGray.setStroke()
        UIBezierPath(rect: rect).stroke()
        y += h + 8
    }

    // MARK: Helpers

    private func ensureRaw(_ h: CGFloat) {
        if y + h > bottomLimit { newPage() }
    }

    private func drawFooter() {
        let attrs = attributes(font: .systemFont(ofSize: 8), color: .gray, align: .left)
        let fy = Self.pageSize.height - margin + 4
        (footerText as NSString).draw(in: CGRect(x: margin, y: fy, width: contentWidth - 60, height: 12), withAttributes: attrs)
        let right = attributes(font: .systemFont(ofSize: 8), color: .gray, align: .right)
        ("Page \(pageNumber)" as NSString).draw(in: CGRect(x: margin + contentWidth - 60, y: fy, width: 60, height: 12), withAttributes: right)
    }

    private func attributes(font: UIFont, color: UIColor, align: NSTextAlignment) -> [NSAttributedString.Key: Any] {
        let para = NSMutableParagraphStyle()
        para.alignment = align
        para.lineBreakMode = .byWordWrapping
        return [.font: font, .foregroundColor: color, .paragraphStyle: para]
    }

    private func height(of s: String, width: CGFloat, attrs: [NSAttributedString.Key: Any]) -> CGFloat {
        ceil((s as NSString).boundingRect(
            with: CGSize(width: width, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: attrs, context: nil).height)
    }
}

private extension PDFComposer {
    @discardableResult
    func text(_ s: String, font: UIFont, color: UIColor, align: NSTextAlignment,
              x: CGFloat, width: CGFloat, advance: Bool, yOffset: CGFloat) -> CGFloat {
        let attrs = attributes(font: font, color: color, align: align)
        let h = height(of: s, width: width, attrs: attrs)
        (s as NSString).draw(in: CGRect(x: x, y: y + yOffset, width: width, height: h), withAttributes: attrs)
        return h
    }
}
