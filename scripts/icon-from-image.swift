#!/usr/bin/env swift
// Packs a square source image into Resources/AppIcon.icns, fitted to Apple's
// icon grid.
//
//   swift scripts/icon-from-image.swift artwork.png
//
// Use this when the artwork comes from a designer or an image generator.
// `make-icon.swift` is the other path — it draws the icon in code.
//
// Generated artwork is never quite icon-ready, and three things go wrong every
// time. This fixes all of them automatically rather than by eyeballing numbers:
//
//  * **Speckles.** Diffusion models leave a halo of near-transparent noise
//    around the subject. Invisible on white, obvious against a dark Dock.
//  * **Wrong scale.** macOS reserves a margin around every icon: the solid
//    shape occupies ~80.5% of the canvas (824 of 1024 px). Art drawn edge to
//    edge looks oversized next to every other icon in the Dock.
//  * **Off-centre.** A few pixels of drift is invisible at full size and very
//    visible in a row of 32px icons.
//
// Glow and shadow are deliberately allowed to spill outside the 80.5% box —
// that margin is exactly what it's for. Only the *solid* shape is measured.

import AppKit
import Foundation

// The ten representations an .iconset may contain, as (pixel size, name).
// `icon_1024x1024.png` and `icon_64x64.png` are NOT valid iconset names —
// iconutil ignores them, so emitting them was pure wasted work.
let variants: [(pixels: Int, name: String)] = [
    (16, "icon_16x16"), (32, "icon_16x16@2x"),
    (32, "icon_32x32"), (64, "icon_32x32@2x"),
    (128, "icon_128x128"), (256, "icon_128x128@2x"),
    (256, "icon_256x256"), (512, "icon_256x256@2x"),
    (512, "icon_512x512"), (1024, "icon_512x512@2x"),
]

/// Fraction of the canvas Apple's grid gives the solid shape of a
/// rounded-rectangle icon: 824 of 1024 points.
let targetFill: CGFloat = 824.0 / 1024.0

/// Alpha at or below this is treated as noise and erased. High enough to catch
/// generator speckle, low enough to keep the faint outer edge of a real glow.
let noiseFloor: CGFloat = 0.06

/// Alpha above this counts as the solid body, the thing that gets measured.
let solidThreshold: CGFloat = 0.5

guard CommandLine.arguments.count > 1 else {
    FileHandle.standardError.write(
        "usage: swift scripts/icon-from-image.swift <source-image>\n".data(using: .utf8)!)
    exit(2)
}

let sourcePath = (CommandLine.arguments[1] as NSString).expandingTildeInPath
guard let loaded = NSImage(contentsOfFile: sourcePath) else {
    FileHandle.standardError.write("!! Couldn't read \(sourcePath)\n".data(using: .utf8)!)
    exit(1)
}

guard let sourceRep = loaded.representations.first else {
    FileHandle.standardError.write("!! No image data in \(sourcePath)\n".data(using: .utf8)!)
    exit(1)
}
let width = sourceRep.pixelsWide
let height = sourceRep.pixelsHigh
print("==> Source \(width)×\(height)")

// Redraw into a bitmap we own, in a known format.
//
// The alternative — mutating the rep that came out of the file with
// `setColor` — inherits whatever exotic colour space the generator wrote, and
// AppKit then fails to re-encode it ("Unrecognized colorspace number -1"). A
// fresh sRGB RGBA buffer sidesteps that, and raw byte access is orders of
// magnitude faster than `colorAt` over a million pixels.
guard let canvas = NSBitmapImageRep(
    bitmapDataPlanes: nil,
    pixelsWide: width, pixelsHigh: height,
    bitsPerSample: 8, samplesPerPixel: 4,
    hasAlpha: true, isPlanar: false,
    colorSpaceName: .deviceRGB,
    bytesPerRow: width * 4, bitsPerPixel: 32
) else {
    FileHandle.standardError.write("!! Couldn't allocate a bitmap\n".data(using: .utf8)!)
    exit(1)
}

NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: canvas)
NSGraphicsContext.current?.cgContext.clear(
    CGRect(x: 0, y: 0, width: CGFloat(width), height: CGFloat(height)))
loaded.draw(
    in: NSRect(x: 0, y: 0, width: CGFloat(width), height: CGFloat(height)),
    from: .zero, operation: .sourceOver, fraction: 1.0)
NSGraphicsContext.restoreGraphicsState()

guard let pixels = canvas.bitmapData else {
    FileHandle.standardError.write("!! No pixel data\n".data(using: .utf8)!)
    exit(1)
}
let rowBytes = canvas.bytesPerRow

// MARK: - Strip the speckle halo

let noiseCutoff = UInt8(noiseFloor * 255)
var erased = 0
for y in 0..<height {
    for x in 0..<width {
        let offset = y * rowBytes + x * 4
        let alpha = pixels[offset + 3]
        guard alpha > 0, alpha <= noiseCutoff else { continue }
        // Premultiplied: clearing means zeroing the whole pixel.
        pixels[offset] = 0
        pixels[offset + 1] = 0
        pixels[offset + 2] = 0
        pixels[offset + 3] = 0
        erased += 1
    }
}
print("==> Erased \(erased) speckle pixels below \(noiseFloor) alpha")

// MARK: - Measure the solid body

let solidCutoff = UInt8(solidThreshold * 255)
var minX = width, minY = height, maxX = -1, maxY = -1
for y in 0..<height {
    for x in 0..<width {
        guard pixels[y * rowBytes + x * 4 + 3] > solidCutoff else { continue }
        if x < minX { minX = x }
        if x > maxX { maxX = x }
        if y < minY { minY = y }
        if y > maxY { maxY = y }
    }
}

guard maxX > minX, maxY > minY else {
    FileHandle.standardError.write("!! Found no solid pixels\n".data(using: .utf8)!)
    exit(1)
}

let solidWidth = CGFloat(maxX - minX + 1)
let solidHeight = CGFloat(maxY - minY + 1)
// Uniform scale off the longer side, so a slightly non-square subject still
// fits inside the grid box rather than overflowing it.
let solidExtent = max(solidWidth, solidHeight)

print(
    String(
        format: "==> Solid body %.0f×%.0f (%.1f%% of canvas) — target %.1f%%",
        solidWidth, solidHeight, solidExtent / CGFloat(width) * 100, targetFill * 100))

/// Centre of the solid body, in bottom-left (Core Graphics) coordinates.
let bodyCentre = CGPoint(
    x: (CGFloat(minX) + CGFloat(maxX) + 1) / 2,
    y: CGFloat(height) - (CGFloat(minY) + CGFloat(maxY) + 1) / 2
)

let cleaned = NSImage(size: NSSize(width: width, height: height))
cleaned.addRepresentation(canvas)

// MARK: - Render

/// Makes one PNG at the requested size.
///
/// Draws into an explicitly-allocated sRGB bitmap rather than using
/// `lockFocus()`. `lockFocus` inherits the display's colour space, and
/// round-tripping that through `tiffRepresentation` is what produced
/// "CGImageDestinationFinalize failed" on this artwork.
func render(size: Int) -> Data? {
    let side = CGFloat(size)
    let scale = (side * targetFill) / solidExtent

    // Place the scaled artwork so its solid body lands dead centre.
    let drawn = CGSize(width: CGFloat(width) * scale, height: CGFloat(height) * scale)
    let origin = CGPoint(
        x: side / 2 - bodyCentre.x * scale,
        y: side / 2 - bodyCentre.y * scale
    )

    guard let out = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: size, pixelsHigh: size,
        bitsPerSample: 8, samplesPerPixel: 4,
        hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: size * 4, bitsPerPixel: 32
    ) else { return nil }
    out.size = NSSize(width: side, height: side)

    NSGraphicsContext.saveGraphicsState()
    defer { NSGraphicsContext.restoreGraphicsState() }
    guard let context = NSGraphicsContext(bitmapImageRep: out) else { return nil }
    NSGraphicsContext.current = context
    context.imageInterpolation = .high
    context.cgContext.clear(CGRect(x: 0, y: 0, width: side, height: side))

    cleaned.draw(
        in: NSRect(origin: origin, size: drawn),
        from: .zero,
        operation: .sourceOver,
        fraction: 1.0
    )

    return out.representation(using: .png, properties: [:])
}

let outputDir = URL(fileURLWithPath: "build/AppIcon.iconset")
try? FileManager.default.removeItem(at: outputDir)
try FileManager.default.createDirectory(at: outputDir, withIntermediateDirectories: true)

// Render each distinct pixel size once, then write it under every name that
// wants it — the 2x names are the same image as the next size up.
var rendered: [Int: Data] = [:]
for variant in variants {
    if rendered[variant.pixels] == nil {
        guard let data = render(size: variant.pixels) else {
            FileHandle.standardError.write(
                "!! Failed at \(variant.pixels)px\n".data(using: .utf8)!)
            exit(1)
        }
        rendered[variant.pixels] = data
    }
    try rendered[variant.pixels]!.write(
        to: outputDir.appendingPathComponent("\(variant.name).png"))
}
print("==> Rendered \(rendered.count) sizes into \(variants.count) representations")

let iconutil = Process()
iconutil.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
iconutil.arguments = ["-c", "icns", outputDir.path, "-o", "Resources/AppIcon.icns"]
try iconutil.run()
iconutil.waitUntilExit()

guard iconutil.terminationStatus == 0 else {
    FileHandle.standardError.write("!! iconutil failed\n".data(using: .utf8)!)
    exit(1)
}

print("==> Resources/AppIcon.icns")
print("    Rebuild to pick it up: ./scripts/build-app.sh release --install")
