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

let markURL = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()
    .appendingPathComponent("Resources/swirl-mark.png")
let sourceMark = NSImage(contentsOf: markURL)

/// ⚠️ THE SWIRL IS LIFTED, NEVER REDRAWN — the same rule make-wordmark.swift
/// follows and the same one NOTES.md records for the icon. Filling the box and
/// masking it with the artwork's own alpha keeps every thin inner arc exactly as
/// drawn; re-rendering it through a blur/threshold pass at a new size ate those
/// arcs and turned the rings into blobs.
///
/// ⚠️ MASK IN ITS OWN BITMAP, THEN DRAW THE RESULT. Filling and masking directly
/// on the final canvas looked right and was not: `.destinationIn` erases the
/// destination wherever the mark is transparent, so it punched a hole through
/// the navy background inside the mark's rect and left the swirl sitting in a
/// transparent square. Isolating it is the whole fix.
func tintedMark(_ color: NSColor, side: CGFloat) -> NSImage? {
    guard let mark = sourceMark else { return nil }
    let px = Int(side * 2)   // 2x, so the arcs survive the downscale
    guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px,
                                     bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                                     isPlanar: false, colorSpaceName: .deviceRGB,
                                     bytesPerRow: 0, bitsPerPixel: 0) else { return nil }
    rep.size = NSSize(width: side, height: side)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    NSGraphicsContext.current?.imageInterpolation = .high
    let bounds = NSRect(x: 0, y: 0, width: side, height: side)
    color.setFill()
    NSBezierPath(rect: bounds).fill()
    mark.draw(in: bounds, from: .zero, operation: .destinationIn, fraction: 1)
    NSGraphicsContext.current?.flushGraphics()
    NSGraphicsContext.restoreGraphicsState()
    let out = NSImage(size: bounds.size)
    out.addRepresentation(rep)
    return out
}

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

/// Swirl on the left, type on the right, optically balanced.
///
/// ⚠️ THE SWIRL IS SIZED FROM THE CAP HEIGHT, NOT THE CANVAS. Pinning it to the
/// frame makes the mark grow and shrink against the type whenever the string
/// length changes — PROTECT and TEMPLETON PROTECT are set at very different
/// point sizes, and a fixed-fraction swirl looked correct beside one and
/// oversized beside the other.
func renderLockup(text: String, ink: NSColor, background: NSColor?, size: NSSize, to url: URL) {
    guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil,
                                     pixelsWide: Int(size.width), pixelsHigh: Int(size.height),
                                     bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                                     isPlanar: false, colorSpaceName: .calibratedRGB,
                                     bytesPerRow: 0, bitsPerPixel: 0) else { return }
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    NSGraphicsContext.current?.imageInterpolation = .high

    if let background {
        background.setFill()
        NSBezierPath(rect: NSRect(origin: .zero, size: size)).fill()
    }

    let tracking: CGFloat = -0.015
    let inset = size.width * 0.045
    // The swirl and its gap claim a share of the width before the type is fitted,
    // or the type would be measured against room it does not have.
    let markShare: CGFloat = 0.20
    let available = size.width - inset * 2 - size.width * markShare
    let font = fitted(text, maxWidth: available, tracking: tracking)
    let attrs: [NSAttributedString.Key: Any] = [
        .font: font, .foregroundColor: ink, .kern: tracking * font.pointSize,
    ]
    let line = NSAttributedString(string: text, attributes: attrs)
    let measured = line.size()

    let markSide = font.capHeight * 1.62
    let gap = markSide * 0.42
    let total = markSide + gap + measured.width
    let left = (size.width - total) / 2
    let midY = size.height / 2

    tintedMark(ink, side: markSide)?.draw(
        in: NSRect(x: left, y: midY - markSide / 2, width: markSide, height: markSide),
        from: .zero, operation: .sourceOver, fraction: 1)
    line.draw(at: NSPoint(x: left + markSide + gap,
                          y: midY - measured.height / 2 + measured.height * 0.045))

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

print("lockups (swirl + type) →")
for (text, slug, size) in [
    ("PROTECT", "lockup-protect", NSSize(width: 1600, height: 420)),
    ("TEMPLETON PROTECT", "lockup-templeton-protect", NSSize(width: 2000, height: 360)),
] {
    renderLockup(text: text, ink: champagne, background: nil,
                 size: size, to: brandRoot.appendingPathComponent("\(slug)-champagne-transparent.png"))
    renderLockup(text: text, ink: champagne, background: navy,
                 size: size, to: brandRoot.appendingPathComponent("\(slug)-champagne-on-navy.png"))
    renderLockup(text: text, ink: navy, background: nil,
                 size: size, to: brandRoot.appendingPathComponent("\(slug)-navy-transparent.png"))
}
