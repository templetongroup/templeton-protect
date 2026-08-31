import AppKit

/// The findings as a document somebody will read without having run the scan.
///
/// ⚠️ TYPESET, NOT A TEXT DUMP RENAMED. This is the artifact that leaves the
/// machine — attached to a ticket, forwarded to a client, printed. It carries
/// the same hierarchy the app does and it paginates, because a single long line
/// in a PDF runs off the page and takes the finding with it.
///
/// ⚠️ AND IT IS PRINTED ON WHITE. The app's palette is built for a navy screen;
/// champagne on paper is invisible and dusty rose is too light to read at 9pt.
/// The print palette is the same four colours darkened to carry ink — stated
/// here rather than reached for ad hoc, so the document stays one document.
public enum PDFReport {
    private static let pageSize = CGSize(width: 612, height: 792)  // US Letter at 72dpi
    private static let margin: CGFloat = 56
    private static let footerRoom: CGFloat = 46

    private enum Ink {
        static let navy = NSColor(red: 0.098, green: 0.165, blue: 0.337, alpha: 1)   // #192A56
        static let body = NSColor(red: 0.16, green: 0.18, blue: 0.22, alpha: 1)
        static let quiet = NSColor(white: 0.45, alpha: 1)
        static let rule = NSColor(white: 0.86, alpha: 1)
        static let panel = NSColor(white: 0.965, alpha: 1)
        /// Dusty rose and champagne, darkened until they carry on paper.
        static let critical = NSColor(red: 0.639, green: 0.239, blue: 0.212, alpha: 1)
        static let high = NSColor(red: 0.541, green: 0.400, blue: 0.098, alpha: 1)
        static let good = NSColor(red: 0.153, green: 0.400, blue: 0.290, alpha: 1)
    }

    private enum Block {
        case title(String)
        case meta(String)
        case counts(critical: Int, high: Int, minor: Int)
        case section(String)
        case heading(String, Severity)
        case body(String)
        case path(String)
        case label(String, String)
        case rule
        case gap(CGFloat)
    }

    public static func write(_ result: ScanResult, to url: URL, on date: Date = Date(),
                             mark: NSImage? = Bundle.main.image(forResource: "swirl-mark")) throws {
        let sorted = sortedForReport(result.findings)
        var blocks: [Block] = [
            .title("Templeton Protect"),
            .meta(stampText(date) + "  ·  " + machineLine(result)),
            .gap(10),
            .rule,
            .gap(16),
            .counts(critical: sorted.filter { $0.severity == .critical }.count,
                    high: sorted.filter { $0.severity == .high }.count,
                    minor: sorted.filter { $0.severity == .medium || $0.severity == .low }.count),
            .gap(20),
        ]

        if sorted.isEmpty {
            blocks.append(.body("Nothing to worry about. No credentials are sitting in your AI conversation logs, and nothing another account on this Mac could read."))
        } else {
            var lastSeverity: Severity?
            for f in sorted {
                if f.severity != lastSeverity {
                    blocks.append(.section(headingFor(f.severity)))
                    lastSeverity = f.severity
                }
                blocks.append(.heading(f.title, f.severity))
                blocks.append(.body(redact(f.plain)))
                blocks.append(.path(f.where_))
                blocks.append(.label("Found", redact(f.evidence)))
                blocks.append(.label("What to do", redact(f.remedy)))
                blocks.append(.label("How to check", redact(f.validation)))
                blocks.append(.label("Confirmed", f.verified ? "yes, by a direct check" : "no — pattern match only"))
                blocks.append(.gap(16))
            }
        }
        try render(blocks, to: url, mark: mark)
    }

    private static func stampText(_ date: Date) -> String {
        let f = DateFormatter(); f.dateStyle = .long; f.timeStyle = .short
        return f.string(from: date)
    }

    private static func machineLine(_ r: ScanResult) -> String {
        let tools = r.toolsFound.isEmpty ? "nothing" : r.toolsFound.joined(separator: ", ")
        return "\(r.filesRead.formatted()) files and settings checked across \(tools)"
    }

    // ── text ──────────────────────────────────────────────────────────────
    private static func make(_ text: String, _ font: NSFont, _ color: NSColor,
                             spacing: CGFloat = 3, tracking: CGFloat = 0) -> NSAttributedString {
        let p = NSMutableParagraphStyle()
        p.lineSpacing = spacing
        var attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: color, .paragraphStyle: p]
        if tracking != 0 { attrs[.kern] = tracking }
        return NSAttributedString(string: text, attributes: attrs)
    }

    private static func attributed(_ block: Block) -> NSAttributedString? {
        switch block {
        case .title(let t):   return make(t, .systemFont(ofSize: 25, weight: .bold), Ink.navy)
        case .meta(let t):    return make(t, .systemFont(ofSize: 9), Ink.quiet)
        case .section(let t): return make(t.uppercased(), .systemFont(ofSize: 9.5, weight: .bold), Ink.quiet, tracking: 1.3)
        case .heading(let t, _): return make(t, .systemFont(ofSize: 13, weight: .semibold), Ink.navy)
        case .body(let t):    return make(t, .systemFont(ofSize: 10.5), Ink.body, spacing: 4)
        case .path(let t):    return make(t, .monospacedSystemFont(ofSize: 8, weight: .regular), Ink.quiet, spacing: 2)
        case .label(let k, let v):
            let s = NSMutableAttributedString(attributedString: make("\(k)  ", .systemFont(ofSize: 9, weight: .semibold), Ink.navy))
            s.append(make(v, .systemFont(ofSize: 9), Ink.body, spacing: 2))
            return s
        case .counts, .rule, .gap: return nil
        }
    }

    private static func spaceBefore(_ block: Block) -> CGFloat {
        switch block {
        case .section: return 20
        case .heading: return 12
        case .path:    return 6
        case .label:   return 4
        case .body:    return 6
        default:       return 0
        }
    }

    private static func height(_ block: Block, width: CGFloat) -> CGFloat {
        switch block {
        case .rule: return 1
        case .gap(let h): return h
        case .counts: return 52
        default:
            guard let text = attributed(block) else { return 0 }
            let fs = CTFramesetterCreateWithAttributedString(text)
            let fit = CTFramesetterSuggestFrameSizeWithConstraints(
                fs, CFRange(location: 0, length: 0), nil,
                CGSize(width: width - inset(block), height: .greatestFiniteMagnitude), nil)
            // A path sits in a tinted box, so it carries its own padding.
            return ceil(fit.height) + (isPath(block) ? 10 : 0)
        }
    }

    /// Findings are indented under their severity heading; the top matter is not.
    private static func inset(_ block: Block) -> CGFloat {
        switch block {
        case .body, .path, .label: return 14
        // ⚠️ THE HEADING IS INDENTED TOO, or the severity dot lands on top of
        // its first letter — which it did: "OpenAI key…" rendered with a rose
        // blob over the O.
        case .heading: return 14
        default: return 0
        }
    }

    private static func isPath(_ block: Block) -> Bool { if case .path = block { return true }; return false }
    private static func isHeading(_ block: Block) -> Bool {
        if case .heading = block { return true }
        if case .section = block { return true }
        return false
    }

    // ── drawing ───────────────────────────────────────────────────────────
    private static func render(_ blocks: [Block], to url: URL, mark: NSImage?) throws {
        var media = CGRect(origin: .zero, size: pageSize)
        guard let consumer = CGDataConsumer(url: url as CFURL),
              let ctx = CGContext(consumer: consumer, mediaBox: &media, nil) else {
            throw NSError(domain: "Protect", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "Could not create the PDF at \(url.path)."])
        }

        var markImage: CGImage?
        if let mark { markImage = mark.cgImage(forProposedRect: nil, context: nil, hints: nil) }

        let width = pageSize.width - margin * 2
        var y = margin
        var page = 0
        var open = false

        func newPage() {
            if open { drawFooter(ctx, page: page); ctx.endPDFPage() }
            ctx.beginPDFPage(nil)
            page += 1
            open = true
            drawWatermark(ctx, markImage)
            y = margin
        }
        newPage()

        for block in blocks {
            let h = height(block, width: width)
            let need = h + (isHeading(block) ? 46 : 0)
            y += spaceBefore(block)
            if y + need > pageSize.height - margin - footerRoom {
                newPage()
                y += spaceBefore(block)
            }
            draw(block, in: ctx, at: &y, width: width)
        }

        if open { drawFooter(ctx, page: page); ctx.endPDFPage() }
        ctx.closePDF()
    }

    /// ⚠️ BEHIND EVERYTHING AND NEARLY GONE. A watermark that competes with the
    /// text makes the report harder to read, which for a security report is a
    /// real cost, not a stylistic one. It is drawn first, at 4%, bleeding off
    /// the corner so it reads as stationery rather than as a stamp.
    private static func drawWatermark(_ ctx: CGContext, _ mark: CGImage?) {
        guard let mark else { return }
        // ⚠️ CLIP TO IT AND FILL, DO NOT DRAW IT. The asset is white ink on
        // transparency — the screen wants that, and drawing it on white paper
        // produces exactly nothing, which is what the first version did. Using
        // it as a mask and filling navy is what puts it on the page.
        ctx.saveGState()
        let size: CGFloat = 460
        let box = CGRect(x: pageSize.width - size * 0.62, y: -size * 0.30, width: size, height: size)
        ctx.clip(to: box, mask: mark)
        ctx.setFillColor(Ink.navy.withAlphaComponent(0.055).cgColor)
        ctx.fill(box)
        ctx.restoreGState()
    }

    private static func drawFooter(_ ctx: CGContext, page: Int) {
        let y = margin - 14
        ctx.saveGState()
        ctx.setStrokeColor(Ink.rule.cgColor)
        ctx.setLineWidth(0.5)
        ctx.move(to: CGPoint(x: margin, y: y + 16))
        ctx.addLine(to: CGPoint(x: pageSize.width - margin, y: y + 16))
        ctx.strokePath()
        ctx.restoreGState()

        drawLine(make("Templeton Protect is a Templeton Technologies product",
                      .systemFont(ofSize: 7.5), Ink.quiet), ctx, x: margin, baseline: y)
        let n = make("\(page)", .systemFont(ofSize: 7.5), Ink.quiet)
        drawLine(n, ctx, x: pageSize.width - margin - n.size().width, baseline: y)
    }

    private static func drawLine(_ text: NSAttributedString, _ ctx: CGContext, x: CGFloat, baseline: CGFloat) {
        let line = CTLineCreateWithAttributedString(text)
        ctx.textPosition = CGPoint(x: x, y: baseline)
        CTLineDraw(line, ctx)
    }

    private static func draw(_ block: Block, in ctx: CGContext, at y: inout CGFloat, width: CGFloat) {
        switch block {
        case .gap(let h):
            y += h
            return

        case .rule:
            ctx.saveGState()
            ctx.setStrokeColor(Ink.rule.cgColor)
            ctx.setLineWidth(1)
            ctx.move(to: CGPoint(x: margin, y: pageSize.height - y))
            ctx.addLine(to: CGPoint(x: pageSize.width - margin, y: pageSize.height - y))
            ctx.strokePath()
            ctx.restoreGState()
            y += 1
            return

        case .counts(let c, let h, let m):
            // Three figures across the page. The number is the thing, so it is
            // set large and the label under it small.
            let cells: [(Int, String, NSColor)] = [
                (c, "critical", Ink.critical), (h, "worth fixing", Ink.high), (m, "minor", Ink.quiet),
            ]
            let cellW = width / 3
            for (i, cell) in cells.enumerated() {
                let x = margin + CGFloat(i) * cellW
                drawLine(make("\(cell.0)", .systemFont(ofSize: 26, weight: .bold), cell.2),
                         ctx, x: x, baseline: pageSize.height - y - 26)
                drawLine(make(cell.1.uppercased(), .systemFont(ofSize: 8, weight: .semibold), Ink.quiet, tracking: 1.1),
                         ctx, x: x, baseline: pageSize.height - y - 44)
            }
            y += 52
            return

        case .path(let p):
            // A tinted box, so a long path reads as data rather than prose.
            let text = make(p, .monospacedSystemFont(ofSize: 8, weight: .regular), Ink.quiet, spacing: 2)
            let w = width - inset(block)
            let fs = CTFramesetterCreateWithAttributedString(text)
            let fit = CTFramesetterSuggestFrameSizeWithConstraints(
                fs, CFRange(location: 0, length: 0), nil,
                CGSize(width: w - 12, height: .greatestFiniteMagnitude), nil)
            let boxH = ceil(fit.height) + 10
            let box = CGRect(x: margin + inset(block), y: pageSize.height - y - boxH, width: w, height: boxH)
            ctx.saveGState()
            ctx.setFillColor(Ink.panel.cgColor)
            ctx.addPath(CGPath(roundedRect: box, cornerWidth: 3, cornerHeight: 3, transform: nil))
            ctx.fillPath()
            ctx.restoreGState()
            let inner = box.insetBy(dx: 6, dy: 5)
            let frame = CTFramesetterCreateFrame(fs, CFRange(location: 0, length: 0),
                                                 CGPath(rect: inner, transform: nil), nil)
            CTFrameDraw(frame, ctx)
            y += boxH
            return

        case .heading(let t, let severity):
            // A severity dot beside the title, so scanning down the left edge
            // sorts the document without reading it.
            let dot = CGRect(x: margin + 2, y: pageSize.height - y - 11, width: 6, height: 6)
            ctx.saveGState()
            ctx.setFillColor(tint(severity).cgColor)
            ctx.fillEllipse(in: dot)
            ctx.restoreGState()
            _ = t
            fallthrough

        default:
            guard let text = attributed(block) else { return }
            let x = margin + inset(block)
            let w = width - inset(block)
            let fs = CTFramesetterCreateWithAttributedString(text)
            let fit = CTFramesetterSuggestFrameSizeWithConstraints(
                fs, CFRange(location: 0, length: 0), nil,
                CGSize(width: w, height: .greatestFiniteMagnitude), nil)
            let h = ceil(fit.height)
            // CoreText draws from the bottom left; the report is written top down.
            let rect = CGRect(x: x, y: pageSize.height - y - h, width: w, height: h)
            let frame = CTFramesetterCreateFrame(fs, CFRange(location: 0, length: 0),
                                                 CGPath(rect: rect, transform: nil), nil)
            CTFrameDraw(frame, ctx)
            y += h
        }
    }

    private static func tint(_ s: Severity) -> NSColor {
        switch s {
        case .critical: return Ink.critical
        case .high: return Ink.high
        case .medium, .low: return Ink.quiet
        }
    }
}
