import AppKit

/// The findings as a PDF someone can attach to a ticket.
///
/// ⚠️ TYPESET, NOT A TEXT DUMP RENAMED. This is the artifact that leaves the
/// machine and gets read by somebody who never ran the scan, so it carries the
/// same hierarchy the app does — severity headings, the path in a mono face, the
/// evidence set back — and it paginates. A single long line of text in a PDF
/// runs off the page and takes the finding with it.
public enum PDFReport {
    private static let pageSize = CGSize(width: 612, height: 792)  // US Letter, 72dpi
    private static let margin: CGFloat = 54

    private enum Block {
        case title(String)
        case meta(String)
        case section(String)
        case heading(String)
        case body(String)
        case mono(String)
        case label(String, String)
        case gap(CGFloat)
    }

    public static func write(_ result: ScanResult, to url: URL, on date: Date = Date()) throws {
        var blocks: [Block] = [
            .title("Templeton Protect"),
            .meta(stampText(date)),
            .gap(6),
            .body(summaryLine(result)),
            .gap(14),
        ]

        if result.findings.isEmpty {
            blocks.append(.body("Nothing to worry about. No credentials are sitting in your AI conversation logs, and nothing another account on this Mac could read."))
        } else {
            var lastSeverity: Severity?
            for f in sortedForReport(result.findings) {
                if f.severity != lastSeverity {
                    blocks.append(.section(headingFor(f.severity)))
                    lastSeverity = f.severity
                }
                blocks.append(.heading(f.title))
                blocks.append(.body(redact(f.plain)))
                blocks.append(.mono(f.where_))
                blocks.append(.label("Found", redact(f.evidence)))
                blocks.append(.label("What to do", redact(f.remedy)))
                blocks.append(.label("How to check", redact(f.validation)))
                blocks.append(.label("Confirmed", f.verified ? "yes, by a direct check" : "no — pattern match only"))
                blocks.append(.gap(12))
            }
        }
        blocks.append(.gap(8))
        blocks.append(.meta("A Templeton Technologies Product · templetontech.com"))

        try render(blocks, to: url)
    }

    private static func stampText(_ date: Date) -> String {
        let f = DateFormatter(); f.dateStyle = .long; f.timeStyle = .short
        return f.string(from: date)
    }

    private static func attributed(_ block: Block) -> NSAttributedString? {
        let ink = NSColor.black
        let quiet = NSColor(white: 0.38, alpha: 1)
        func make(_ text: String, _ font: NSFont, _ color: NSColor, spacing: CGFloat = 3) -> NSAttributedString {
            let p = NSMutableParagraphStyle()
            p.lineSpacing = spacing
            return NSAttributedString(string: text, attributes: [.font: font, .foregroundColor: color, .paragraphStyle: p])
        }
        switch block {
        case .title(let t):   return make(t, .systemFont(ofSize: 24, weight: .semibold), ink)
        case .meta(let t):    return make(t, .systemFont(ofSize: 9), quiet)
        case .section(let t): return make(t.uppercased(), .systemFont(ofSize: 10, weight: .semibold), quiet)
        case .heading(let t): return make(t, .systemFont(ofSize: 13, weight: .semibold), ink)
        case .body(let t):    return make(t, .systemFont(ofSize: 10.5), ink, spacing: 4)
        case .mono(let t):    return make(t, .monospacedSystemFont(ofSize: 8.5, weight: .regular), quiet)
        case .label(let k, let v):
            let s = NSMutableAttributedString(attributedString: make("\(k): ", .systemFont(ofSize: 9.5, weight: .semibold), quiet))
            s.append(make(v, .systemFont(ofSize: 9.5), quiet))
            return s
        case .gap: return nil
        }
    }

    private static func spaceBefore(_ block: Block) -> CGFloat {
        switch block {
        case .section: return 16
        case .heading: return 10
        case .mono, .label: return 3
        case .body: return 5
        default: return 0
        }
    }

    private static func render(_ blocks: [Block], to url: URL) throws {
        var media = CGRect(origin: .zero, size: pageSize)
        guard let consumer = CGDataConsumer(url: url as CFURL),
              let ctx = CGContext(consumer: consumer, mediaBox: &media, nil) else {
            throw NSError(domain: "Protect", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "Could not create the PDF at \(url.path)."])
        }
        let width = pageSize.width - margin * 2
        var y = margin
        var open = false

        func newPage() {
            if open { ctx.endPDFPage() }
            ctx.beginPDFPage(nil)
            open = true
            y = margin
        }
        newPage()

        for block in blocks {
            if case .gap(let h) = block { y += h; continue }
            guard let text = attributed(block) else { continue }

            let framesetter = CTFramesetterCreateWithAttributedString(text)
            let fit = CTFramesetterSuggestFrameSizeWithConstraints(
                framesetter, CFRange(location: 0, length: 0), nil,
                CGSize(width: width, height: .greatestFiniteMagnitude), nil)
            let height = ceil(fit.height)
            y += spaceBefore(block)

            // ⚠️ A HEADING NEVER ENDS A PAGE. Breaking between a finding's title
            // and its first line leaves an orphan that reads as a different
            // finding on the next page.
            let needed = height + (isHeading(block) ? 40 : 0)
            if y + needed > pageSize.height - margin { newPage(); y += spaceBefore(block) }

            // CoreText draws from the bottom left; the report is written top down.
            let rect = CGRect(x: margin, y: pageSize.height - y - height, width: width, height: height)
            let path = CGPath(rect: rect, transform: nil)
            let frame = CTFramesetterCreateFrame(framesetter, CFRange(location: 0, length: 0), path, nil)
            CTFrameDraw(frame, ctx)
            y += height
        }

        if open { ctx.endPDFPage() }
        ctx.closePDF()
    }

    private static func isHeading(_ block: Block) -> Bool {
        if case .heading = block { return true }
        if case .section = block { return true }
        return false
    }
}
