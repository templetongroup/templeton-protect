#!/usr/bin/env swift

import AppKit
import Foundation

// Templeton Protect's horizontal and stacked wordmark family.
//
// Like Radiant's lockup, every version pairs the existing Templeton swirl with
// heavy geometric type. The swirl is tinted from the bundled alpha artwork; it
// is never redrawn. Both colors come from Protect's four-color palette.

let navy = NSColor(
    calibratedRed: 25.0 / 255.0,
    green: 42.0 / 255.0,
    blue: 86.0 / 255.0,
    alpha: 1
)
let champagne = NSColor(
    calibratedRed: 247.0 / 255.0,
    green: 215.0 / 255.0,
    blue: 148.0 / 255.0,
    alpha: 1
)

let horizontalSize = NSSize(width: 1800, height: 320)
let stackedSize = NSSize(width: 1200, height: 1200)
let wordmark = "TEMPLETON PROTECT"

let scriptURL = URL(fileURLWithPath: #filePath)
let macURL = scriptURL.deletingLastPathComponent()
let resourcesURL = macURL.appendingPathComponent("Resources", isDirectory: true)
let outputURL = resourcesURL
    .appendingPathComponent("Brand", isDirectory: true)
    .appendingPathComponent("Templeton-Protect-Wordmarks", isDirectory: true)
let markURL = resourcesURL.appendingPathComponent("swirl-mark.png")

try FileManager.default.createDirectory(
    at: outputURL,
    withIntermediateDirectories: true
)

guard let sourceMark = NSImage(contentsOf: markURL) else {
    fatalError("Could not load \(markURL.path)")
}

func bitmap(size: NSSize) -> NSBitmapImageRep {
    let scale: CGFloat = 2
    guard let bitmap = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: Int(size.width * scale),
        pixelsHigh: Int(size.height * scale),
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bitmapFormat: [],
        bytesPerRow: 0,
        bitsPerPixel: 0
    ) else {
        fatalError("Could not create a \(Int(size.width * scale)) × \(Int(size.height * scale)) bitmap")
    }
    bitmap.size = size
    return bitmap
}

func tintedMark(size: NSSize, color: NSColor) -> NSImage {
    let markBitmap = bitmap(size: size)
    guard let context = NSGraphicsContext(bitmapImageRep: markBitmap) else {
        fatalError("Could not create the mark drawing context")
    }
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = context
    context.imageInterpolation = .high

    let bounds = NSRect(origin: .zero, size: size)
    color.setFill()
    bounds.fill()
    sourceMark.draw(
        in: bounds,
        from: .zero,
        operation: .destinationIn,
        fraction: 1
    )

    context.flushGraphics()
    NSGraphicsContext.restoreGraphicsState()

    let output = NSImage(size: size)
    output.addRepresentation(markBitmap)
    return output
}

func fittedFont(for string: String, maxWidth: CGFloat, startingAt start: CGFloat) -> NSFont {
    var pointSize = start
    while pointSize > 56 {
        let font = NSFont(name: "AvenirNext-Heavy", size: pointSize)
            ?? NSFont.systemFont(ofSize: pointSize, weight: .heavy)
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .kern: -2.5,
        ]
        if NSAttributedString(string: string, attributes: attributes).size().width <= maxWidth {
            return font
        }
        pointSize -= 1
    }
    return NSFont.systemFont(ofSize: pointSize, weight: .heavy)
}

func prepareCanvas(
    size: NSSize,
    background: NSColor?
) -> (bitmap: NSBitmapImageRep, context: NSGraphicsContext) {
    let canvasBitmap = bitmap(size: size)
    guard let context = NSGraphicsContext(bitmapImageRep: canvasBitmap) else {
        fatalError("Could not create the wordmark drawing context")
    }
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = context
    context.imageInterpolation = .high

    let canvas = NSRect(origin: .zero, size: size)
    NSColor.clear.setFill()
    canvas.fill()
    if let background {
        background.setFill()
        canvas.fill()
    }
    return (canvasBitmap, context)
}

func write(_ bitmap: NSBitmapImageRep, filename: String) throws {
    guard let png = bitmap.representation(using: .png, properties: [:]) else {
        fatalError("Could not encode \(filename)")
    }
    try png.write(to: outputURL.appendingPathComponent(filename), options: .atomic)
}

func writeHorizontal(background: NSColor?, ink: NSColor, filename: String) throws {
    let surface = prepareCanvas(size: horizontalSize, background: background)

    let markSize: CGFloat = 236
    let mark = tintedMark(
        size: NSSize(width: markSize, height: markSize),
        color: ink
    )
    mark.draw(in: NSRect(
        x: 38,
        y: (horizontalSize.height - markSize) / 2,
        width: markSize,
        height: markSize
    ))

    let textX: CGFloat = 314
    let font = fittedFont(
        for: wordmark,
        maxWidth: horizontalSize.width - textX - 40,
        startingAt: 134
    )
    let attributes: [NSAttributedString.Key: Any] = [
        .font: font,
        .foregroundColor: ink,
        .kern: -2.5,
    ]
    let text = NSAttributedString(string: wordmark, attributes: attributes)
    text.draw(at: NSPoint(
        x: textX,
        y: (horizontalSize.height - text.size().height) / 2
    ))

    surface.context.flushGraphics()
    NSGraphicsContext.restoreGraphicsState()
    try write(surface.bitmap, filename: filename)
}

func drawCentered(_ string: String, y: CGFloat, font: NSFont, ink: NSColor) {
    let attributes: [NSAttributedString.Key: Any] = [
        .font: font,
        .foregroundColor: ink,
        .kern: -2.5,
    ]
    let text = NSAttributedString(string: string, attributes: attributes)
    text.draw(at: NSPoint(
        x: (stackedSize.width - text.size().width) / 2,
        y: y
    ))
}

func writeStacked(background: NSColor?, ink: NSColor, filename: String) throws {
    let surface = prepareCanvas(size: stackedSize, background: background)

    let markSize: CGFloat = 390
    let mark = tintedMark(
        size: NSSize(width: markSize, height: markSize),
        color: ink
    )
    mark.draw(in: NSRect(
        x: (stackedSize.width - markSize) / 2,
        y: 730,
        width: markSize,
        height: markSize
    ))

    let stackedFont = fittedFont(
        for: "TEMPLETON",
        maxWidth: 970,
        startingAt: 164
    )
    drawCentered("TEMPLETON", y: 420, font: stackedFont, ink: ink)
    drawCentered("PROTECT", y: 245, font: stackedFont, ink: ink)

    surface.context.flushGraphics()
    NSGraphicsContext.restoreGraphicsState()
    try write(surface.bitmap, filename: filename)
}

// Horizontal family: two transparent masters and two presentation backgrounds.
try writeHorizontal(
    background: nil,
    ink: navy,
    filename: "horizontal-navy-transparent.png"
)
try writeHorizontal(
    background: nil,
    ink: champagne,
    filename: "horizontal-champagne-transparent.png"
)
try writeHorizontal(
    background: champagne,
    ink: navy,
    filename: "horizontal-navy-on-champagne.png"
)
try writeHorizontal(
    background: navy,
    ink: champagne,
    filename: "horizontal-champagne-on-navy.png"
)

// Stacked family: two transparent masters and two presentation backgrounds.
try writeStacked(
    background: nil,
    ink: navy,
    filename: "stacked-navy-transparent.png"
)
try writeStacked(
    background: nil,
    ink: champagne,
    filename: "stacked-champagne-transparent.png"
)
try writeStacked(
    background: champagne,
    ink: navy,
    filename: "stacked-navy-on-champagne.png"
)
try writeStacked(
    background: navy,
    ink: champagne,
    filename: "stacked-champagne-on-navy.png"
)

print("Wrote eight Templeton Protect wordmarks to \(outputURL.path)")
