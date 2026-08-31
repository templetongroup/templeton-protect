#!/usr/bin/env swift

import AppKit
import Foundation

// Templeton Protect's horizontal wordmark.
//
// Like Radiant's lockup, this pairs the existing Templeton swirl with a heavy,
// geometric product name. The swirl is tinted from the bundled alpha artwork;
// it is never redrawn. Both colors come from Protect's four-color palette.

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

let canvasSize = NSSize(width: 1800, height: 320)
let markSize: CGFloat = 236
let markX: CGFloat = 38
let textX: CGFloat = 314
let wordmark = "TEMPLETON PROTECT"

let scriptURL = URL(fileURLWithPath: #filePath)
let macURL = scriptURL.deletingLastPathComponent()
let resourcesURL = macURL.appendingPathComponent("Resources", isDirectory: true)
let markURL = resourcesURL.appendingPathComponent("swirl-mark.png")

guard let sourceMark = NSImage(contentsOf: markURL) else {
    fatalError("Could not load \(markURL.path)")
}

func tintedMark(size: NSSize) -> NSImage {
    let output = NSImage(size: size)
    output.lockFocus()
    NSGraphicsContext.current?.imageInterpolation = .high

    let bounds = NSRect(origin: .zero, size: size)
    navy.setFill()
    bounds.fill()
    sourceMark.draw(
        in: bounds,
        from: .zero,
        operation: .destinationIn,
        fraction: 1
    )

    output.unlockFocus()
    return output
}

func fittedFont(maxWidth: CGFloat) -> NSFont {
    var pointSize: CGFloat = 134
    while pointSize > 72 {
        let font = NSFont(name: "AvenirNext-Heavy", size: pointSize)
            ?? NSFont.systemFont(ofSize: pointSize, weight: .heavy)
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .kern: -2.5,
        ]
        if NSAttributedString(string: wordmark, attributes: attributes).size().width <= maxWidth {
            return font
        }
        pointSize -= 1
    }
    return NSFont.systemFont(ofSize: pointSize, weight: .heavy)
}

func writeWordmark(background: NSColor?, filename: String) throws {
    let image = NSImage(size: canvasSize)
    image.lockFocus()
    NSGraphicsContext.current?.imageInterpolation = .high

    let canvas = NSRect(origin: .zero, size: canvasSize)
    NSColor.clear.setFill()
    canvas.fill()
    if let background {
        background.setFill()
        canvas.fill()
    }

    let mark = tintedMark(size: NSSize(width: markSize, height: markSize))
    let markRect = NSRect(
        x: markX,
        y: (canvasSize.height - markSize) / 2,
        width: markSize,
        height: markSize
    )
    mark.draw(in: markRect)

    let font = fittedFont(maxWidth: canvasSize.width - textX - 40)
    let attributes: [NSAttributedString.Key: Any] = [
        .font: font,
        .foregroundColor: navy,
        .kern: -2.5,
    ]
    let text = NSAttributedString(string: wordmark, attributes: attributes)
    let textSize = text.size()
    text.draw(at: NSPoint(x: textX, y: (canvasSize.height - textSize.height) / 2))

    image.unlockFocus()

    guard
        let tiff = image.tiffRepresentation,
        let bitmap = NSBitmapImageRep(data: tiff),
        let png = bitmap.representation(using: .png, properties: [:])
    else {
        fatalError("Could not encode \(filename)")
    }

    try png.write(to: resourcesURL.appendingPathComponent(filename), options: .atomic)
}

try writeWordmark(background: nil, filename: "templeton-protect-wordmark.png")
try writeWordmark(
    background: champagne,
    filename: "templeton-protect-wordmark-on-champagne.png"
)

print("Wrote Templeton Protect wordmark assets to \(resourcesURL.path)")
