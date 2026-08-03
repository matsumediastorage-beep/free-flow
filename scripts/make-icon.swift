#!/usr/bin/env swift
// Generates Flow's app icon: a waveform on a warm gradient, rendered at every
// size macOS asks for, then packed into Resources/AppIcon.icns.
//
//   swift scripts/make-icon.swift
//
// Regenerate only when the artwork changes — the .icns is committed.

import AppKit
import Foundation

let sizes = [16, 32, 64, 128, 256, 512, 1024]
let outputDir = URL(fileURLWithPath: "build/AppIcon.iconset")

try? FileManager.default.createDirectory(at: outputDir, withIntermediateDirectories: true)

/// Bar heights as a fraction of the icon — an asymmetric waveform reads as
/// "audio" far faster than an even one.
let bars: [CGFloat] = [0.26, 0.46, 0.72, 1.0, 0.80, 0.54, 0.34]

func drawIcon(size: Int) -> NSImage {
    let side = CGFloat(size)
    let image = NSImage(size: NSSize(width: side, height: side))
    image.lockFocus()

    guard let ctx = NSGraphicsContext.current?.cgContext else {
        image.unlockFocus()
        return image
    }

    // macOS icon grid: artwork occupies the middle ~80%, with a squircle radius.
    let inset = side * 0.10
    let rect = CGRect(x: inset, y: inset, width: side - inset * 2, height: side - inset * 2)
    let radius = rect.width * 0.2237

    let path = CGPath(
        roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil)
    ctx.saveGState()
    ctx.addPath(path)
    ctx.clip()

    let gradient = CGGradient(
        colorsSpace: CGColorSpaceCreateDeviceRGB(),
        colors: [
            CGColor(red: 0.42, green: 0.36, blue: 0.95, alpha: 1),  // indigo
            CGColor(red: 0.93, green: 0.42, blue: 0.51, alpha: 1),  // coral
        ] as CFArray,
        locations: [0, 1]
    )!
    ctx.drawLinearGradient(
        gradient,
        start: CGPoint(x: rect.minX, y: rect.maxY),
        end: CGPoint(x: rect.maxX, y: rect.minY),
        options: []
    )
    ctx.restoreGState()

    // Waveform
    let barWidth = rect.width * 0.075
    let spacing = rect.width * 0.055
    let totalWidth = CGFloat(bars.count) * barWidth + CGFloat(bars.count - 1) * spacing
    var x = rect.midX - totalWidth / 2
    let maxHeight = rect.height * 0.52

    ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 0.97))
    for fraction in bars {
        let height = max(barWidth, maxHeight * fraction)
        let barRect = CGRect(
            x: x, y: rect.midY - height / 2, width: barWidth, height: height)
        ctx.addPath(
            CGPath(
                roundedRect: barRect,
                cornerWidth: barWidth / 2,
                cornerHeight: barWidth / 2,
                transform: nil))
        ctx.fillPath()
        x += barWidth + spacing
    }

    image.unlockFocus()
    return image
}

func writePNG(_ image: NSImage, to url: URL) throws {
    guard let tiff = image.tiffRepresentation,
        let rep = NSBitmapImageRep(data: tiff),
        let png = rep.representation(using: .png, properties: [:])
    else {
        throw NSError(domain: "icon", code: 1)
    }
    try png.write(to: url)
}

for size in sizes {
    let image = drawIcon(size: size)
    try writePNG(image, to: outputDir.appendingPathComponent("icon_\(size)x\(size).png"))
    // Retina variant: the @2x of half this size.
    if size >= 32 {
        try writePNG(
            image, to: outputDir.appendingPathComponent("icon_\(size / 2)x\(size / 2)@2x.png"))
    }
}

print("Wrote iconset to \(outputDir.path)")
