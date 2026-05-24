#!/usr/bin/env swift
// Generates AppIcon PNGs from the gauge motif in design/preview.html and
// writes them into ClaudeFuel/Assets.xcassets/AppIcon.appiconset/.
//
// Usage:  swift Scripts/generate-app-icon.swift
//
// Re-run whenever the icon design changes; the generated PNGs are checked in.

import AppKit
import CoreGraphics

// Render sizes required by AppIcon.appiconset (logical size × scale).
let sizes: [(name: String, pixels: Int)] = [
    ("icon_16x16.png",       16),
    ("icon_16x16@2x.png",    32),
    ("icon_32x32.png",       32),
    ("icon_32x32@2x.png",    64),
    ("icon_128x128.png",    128),
    ("icon_128x128@2x.png", 256),
    ("icon_256x256.png",    256),
    ("icon_256x256@2x.png", 512),
    ("icon_512x512.png",    512),
    ("icon_512x512@2x.png", 1024),
]

let outDir = URL(fileURLWithPath: "ClaudeFuel/Assets.xcassets/AppIcon.appiconset")

func render(pixels: Int) -> Data {
    let size = CGFloat(pixels)
    let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!
    let ctx = CGContext(
        data: nil,
        width: pixels, height: pixels,
        bitsPerComponent: 8, bytesPerRow: 0,
        space: colorSpace,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    )!

    // Background: rounded-rect (Big Sur squircle ≈ 22.37% corner radius) with a
    // warm radial gradient from the design's light variant.
    let radius = size * 0.2237
    let rect = CGRect(x: 0, y: 0, width: size, height: size)
    let path = CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil)
    ctx.saveGState()
    ctx.addPath(path)
    ctx.clip()

    let bgColors = [
        CGColor(srgbRed: 0xf6/255, green: 0xef/255, blue: 0xe2/255, alpha: 1), // #f6efe2
        CGColor(srgbRed: 0xe7/255, green: 0xd8/255, blue: 0xc0/255, alpha: 1), // #e7d8c0
    ]
    let gradient = CGGradient(colorsSpace: colorSpace,
                              colors: bgColors as CFArray,
                              locations: [0.0, 1.0])!
    // Radial gradient centred at (30%, 25%) like the CSS preview.
    let start = CGPoint(x: size * 0.30, y: size * (1 - 0.25))
    ctx.drawRadialGradient(gradient,
                           startCenter: start, startRadius: 0,
                           endCenter: start, endRadius: size * 1.2,
                           options: [])

    // Map the SVG's 100×100 viewBox onto the icon, scaled to ~60% (matches the
    // 60/96 icon ratio in the design preview).
    let viewBox: CGFloat = 100
    let motifScale = size * 0.62 / viewBox
    let motifOffset = (size - viewBox * motifScale) / 2
    ctx.translateBy(x: motifOffset, y: motifOffset)
    ctx.scaleBy(x: motifScale, y: motifScale)
    // SVG y-down → CG y-up.
    ctx.translateBy(x: 0, y: viewBox)
    ctx.scaleBy(x: 1, y: -1)

    let trackColor = CGColor(srgbRed: 0xe3/255, green: 0xd4/255, blue: 0xba/255, alpha: 1) // #e3d4ba
    let fillColor  = CGColor(srgbRed: 0xc4/255, green: 0x63/255, blue: 0x3f/255, alpha: 1) // #c4633f (terracotta)
    let inkColor   = CGColor(srgbRed: 0x2b/255, green: 0x27/255, blue: 0x22/255, alpha: 1) // #2b2722

    // Gauge full track: arc from (18,70) to (82,70), large-arc, 34px radius.
    // CSS coords; centre derives from the two endpoints + radius (centre ≈ (50,70)).
    let centre = CGPoint(x: 50, y: 70)
    let radiusG: CGFloat = 34

    ctx.setLineWidth(11)
    ctx.setLineCap(.round)

    // Full arc (track): from angle to angle, 180° around the top half.
    ctx.setStrokeColor(trackColor)
    ctx.addArc(center: centre, radius: radiusG,
               startAngle: .pi, endAngle: 0, clockwise: false)
    ctx.strokePath()

    // Filled portion (terracotta): from 180° to ~225° — the "used" arc on the left.
    ctx.setStrokeColor(fillColor)
    ctx.addArc(center: centre, radius: radiusG,
               startAngle: .pi, endAngle: .pi * 1.25, clockwise: false)
    ctx.strokePath()

    // Needle: from pivot (50,62) to (70,36).
    ctx.setStrokeColor(inkColor)
    ctx.setLineWidth(6)
    ctx.move(to: CGPoint(x: 50, y: 62))
    ctx.addLine(to: CGPoint(x: 70, y: 36))
    ctx.strokePath()

    // Pivot dot.
    ctx.setFillColor(inkColor)
    ctx.addArc(center: CGPoint(x: 50, y: 62), radius: 6.5,
               startAngle: 0, endAngle: .pi * 2, clockwise: false)
    ctx.fillPath()

    ctx.restoreGState()

    let cgImage = ctx.makeImage()!
    let bitmap = NSBitmapImageRep(cgImage: cgImage)
    bitmap.size = NSSize(width: pixels, height: pixels)
    return bitmap.representation(using: .png, properties: [:])!
}

try? FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)

for (name, pixels) in sizes {
    let data = render(pixels: pixels)
    let url = outDir.appending(path: name)
    try! data.write(to: url)
    print("wrote \(name) (\(pixels)×\(pixels))")
}

// Re-emit Contents.json so each entry references its filename.
struct Image: Encodable {
    let idiom: String
    let scale: String
    let size: String
    let filename: String
}
struct Contents: Encodable {
    let images: [Image]
    let info: Info
    struct Info: Encodable { let author = "xcode"; let version = 1 }
}

let images: [Image] = [
    .init(idiom: "mac", scale: "1x", size: "16x16",   filename: "icon_16x16.png"),
    .init(idiom: "mac", scale: "2x", size: "16x16",   filename: "icon_16x16@2x.png"),
    .init(idiom: "mac", scale: "1x", size: "32x32",   filename: "icon_32x32.png"),
    .init(idiom: "mac", scale: "2x", size: "32x32",   filename: "icon_32x32@2x.png"),
    .init(idiom: "mac", scale: "1x", size: "128x128", filename: "icon_128x128.png"),
    .init(idiom: "mac", scale: "2x", size: "128x128", filename: "icon_128x128@2x.png"),
    .init(idiom: "mac", scale: "1x", size: "256x256", filename: "icon_256x256.png"),
    .init(idiom: "mac", scale: "2x", size: "256x256", filename: "icon_256x256@2x.png"),
    .init(idiom: "mac", scale: "1x", size: "512x512", filename: "icon_512x512.png"),
    .init(idiom: "mac", scale: "2x", size: "512x512", filename: "icon_512x512@2x.png"),
]

let encoder = JSONEncoder()
encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
let json = try encoder.encode(Contents(images: images, info: .init()))
try json.write(to: outDir.appending(path: "Contents.json"))
print("updated Contents.json")
