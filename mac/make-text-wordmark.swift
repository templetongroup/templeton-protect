#!/usr/bin/env swift

import AppKit
import Foundation

// Templeton Protect's TEXT-ONLY wordmark.
//
// ⚠️ A SEPARATE SCRIPT, NOT AN EDIT TO make-wordmark.swift. That one belongs to
// the other agent working this repo and builds the swirl-plus-type lockup; this
// builds the type on its own. Two scripts, two jobs, and neither overwrites the
// other's output.
//
// Radiant's wordmark is pure type — "RADIANT" set heavy and wide, no mark beside
// it — and Tony asked for Protect's equivalent in the champagne. So there is no
// swirl here on purpose: the lockup with the mark already exists next door for
// the places that need it.
//
//   swift mac/make-text-wordmark.swift

let navy = NSColor(calibratedRed: 25/255, green: 42/255, blue: 86/255, alpha: 1)
let champagne = NSColor(calibratedRed: 247/255, green: 215/255, blue: 148/255, alpha: 1)

let brandRoot = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()
    .appendingPathComponent("Resources/Brand/Templeton-Protect-Wordmarks")

/// The largest size that still fits the width, found by measuring rather than
/// guessing — the two strings differ in length by more than two to one, and a
/// fixed point size would leave one of them either clipped or lost in space.
func fitted(_ string: String, maxWidth: CGFloat, tracking: CGFloat) -> NSFont {
    var size: CGFloat = 400
    while size > 8 {
        let font = NSFont(name: "AvenirNext-Heavy", size: size)
            ?? NSFont.systemFont(ofSize: size, weight: .heavy)
        let w = (string as NSString).size(withAttributes: [
            .font: font, .kern: tracking * size,
        ]).width
        if w <= maxWidth { return font }
        size -= 1
    }
    return NSFont.systemFont(ofSize: 8, weight: .heavy)
}

func render(text: String, ink: NSColor, background: NSColor?, size: NSSize, to url: URL) {
    guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil,
                                     pixelsWide: Int(size.width), pixelsHigh: Int(size.height),
                                     bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                                     isPlanar: false, colorSpaceName: .calibratedRGB,
                                     bytesPerRow: 0, bitsPerPixel: 0) else { return }
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)

    if let background {
        background.setFill()
        NSBezierPath(rect: NSRect(origin: .zero, size: size)).fill()
    }

    // ⚠️ TRACKING IS SLIGHTLY NEGATIVE, LIKE RADIANT'S. Heavy geometric caps set
    // at default spacing read as a row of separate letters rather than one
    // word; pulling them together is what makes it a mark.
    let tracking: CGFloat = -0.015
    let inset = size.width * 0.055
    let font = fitted(text, maxWidth: size.width - inset * 2, tracking: tracking)
    let attrs: [NSAttributedString.Key: Any] = [
        .font: font,
        .foregroundColor: ink,
        .kern: tracking * font.pointSize,
    ]
    let line = NSAttributedString(string: text, attributes: attrs)
    let measured = line.size()
    // Optically centred: cap-height text sits high in its line box, so centring
    // on the box alone leaves it looking too low.
    let origin = NSPoint(x: (size.width - measured.width) / 2,
                         y: (size.height - measured.height) / 2 + measured.height * 0.045)
    line.draw(at: origin)

    NSGraphicsContext.restoreGraphicsState()
    if let data = rep.representation(using: .png, properties: [:]) {
        try? data.write(to: url)
        print("  \(url.lastPathComponent)")
    }
}

try? FileManager.default.createDirectory(at: brandRoot, withIntermediateDirectories: true)
print("text wordmarks →")

// "PROTECT" alone is the direct parallel to "RADIANT": one word, filling the
// frame. The full name is there for anywhere the company has to be said too.
for (text, slug, size) in [
    ("PROTECT", "text-protect", NSSize(width: 1400, height: 380)),
    ("TEMPLETON PROTECT", "text-templeton-protect", NSSize(width: 1800, height: 300)),
] {
    render(text: text, ink: champagne, background: nil,
           size: size, to: brandRoot.appendingPathComponent("\(slug)-champagne-transparent.png"))
    render(text: text, ink: champagne, background: navy,
           size: size, to: brandRoot.appendingPathComponent("\(slug)-champagne-on-navy.png"))
    render(text: text, ink: navy, background: nil,
           size: size, to: brandRoot.appendingPathComponent("\(slug)-navy-transparent.png"))
}
