#!/usr/bin/env swift
import AppKit
import Foundation

// MARK: - Paths

let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let assetsDir = root.appendingPathComponent("scripts/AppIcon.iconset")
let icnsURL = root.appendingPathComponent("scripts/AppIcon.icns")
let previewURL = root.appendingPathComponent("icon-preview.png")

// iconset filename → pixel size
let iconEntries: [(String, Int)] = [
    ("icon_16x16.png", 16),
    ("icon_16x16@2x.png", 32),
    ("icon_32x32.png", 32),
    ("icon_32x32@2x.png", 64),
    ("icon_128x128.png", 128),
    ("icon_128x128@2x.png", 256),
    ("icon_256x256.png", 256),
    ("icon_256x256@2x.png", 512),
    ("icon_512x512.png", 512),
    ("icon_512x512@2x.png", 1024),
]

// MARK: - Drawing

/// Continuous corner-radius curve for a macOS-style squircle (approx. superellipse via rounded rect).
func squirclePath(in rect: CGRect, cornerRadius: CGFloat) -> NSBezierPath {
    let path = NSBezierPath(roundedRect: rect, xRadius: cornerRadius, yRadius: cornerRadius)
    return path
}

func drawIcon(size: CGFloat) -> NSImage {
    let image = NSImage(size: NSSize(width: size, height: size))
    image.lockFocus()
    defer { image.unlockFocus() }

    guard let ctx = NSGraphicsContext.current?.cgContext else { return image }
    ctx.setShouldAntialias(true)
    ctx.interpolationQuality = .high

    let bounds = CGRect(x: 0, y: 0, width: size, height: size)
    // macOS Big Sur+ icons use ~22.37% continuous corner radius relative to side
    let corner = size * 0.2237
    let path = squirclePath(in: bounds, cornerRadius: corner)

    // Clip to squircle
    path.addClip()

    // Vertical gradient: deep indigo → indigo → blue
    let colors: [CGColor] = [
        NSColor(srgbRed: 0.263, green: 0.220, blue: 0.792, alpha: 1).cgColor, // #4338CA
        NSColor(srgbRed: 0.388, green: 0.400, blue: 0.945, alpha: 1).cgColor, // #6366F1
        NSColor(srgbRed: 0.231, green: 0.510, blue: 0.965, alpha: 1).cgColor, // #3B82F6
    ]
    let locations: [CGFloat] = [0.0, 0.50, 1.0]
    if let gradient = CGGradient(
        colorsSpace: CGColorSpaceCreateDeviceRGB(),
        colors: colors as CFArray,
        locations: locations
    ) {
        ctx.drawLinearGradient(
            gradient,
            start: CGPoint(x: size * 0.5, y: size),
            end: CGPoint(x: size * 0.5, y: 0),
            options: []
        )
    }

    // Subtle top highlight for depth (very light, no hard shadow)
    let highlightColors: [CGColor] = [
        NSColor(srgbRed: 1, green: 1, blue: 1, alpha: 0.14).cgColor,
        NSColor(srgbRed: 1, green: 1, blue: 1, alpha: 0.0).cgColor,
    ]
    if let hi = CGGradient(
        colorsSpace: CGColorSpaceCreateDeviceRGB(),
        colors: highlightColors as CFArray,
        locations: [0.0, 1.0]
    ) {
        ctx.drawLinearGradient(
            hi,
            start: CGPoint(x: size * 0.5, y: size),
            end: CGPoint(x: size * 0.5, y: size * 0.55),
            options: []
        )
    }

    // White "M↓" markdown glyph — bold sans-serif M with downward arrow
    drawMarkdownGlyph(in: bounds, size: size)

    return image
}

func drawMarkdownGlyph(in bounds: CGRect, size: CGFloat) {
    let white = NSColor.white

    // Font size tuned so the mark reads at 16px and looks balanced at 1024
    let mFontSize = size * 0.42
    let font = NSFont.systemFont(ofSize: mFontSize, weight: .bold)

    let m = "M" as NSString
    let attrs: [NSAttributedString.Key: Any] = [
        .font: font,
        .foregroundColor: white,
    ]
    let mSize = m.size(withAttributes: attrs)

    // Center the M slightly above geometric center to leave room for the arrow
    let mOrigin = CGPoint(
        x: (bounds.width - mSize.width) / 2.0,
        y: (bounds.height - mSize.height) / 2.0 + size * 0.06
    )
    m.draw(at: mOrigin, withAttributes: attrs)

    // Downward arrow below-right of M (classic markdown logo echo)
    drawDownArrow(
        center: CGPoint(
            x: mOrigin.x + mSize.width * 0.72,
            y: mOrigin.y - size * 0.02
        ),
        size: size,
        color: white
    )
}

func drawDownArrow(center: CGPoint, size: CGFloat, color: NSColor) {
    let stemW = max(size * 0.045, 1.5)
    let stemH = size * 0.14
    let headW = size * 0.12
    let headH = size * 0.09

    // Stem top sits near center; arrow points down
    let stemTop = center.y
    let stemBottom = stemTop - stemH
    let cx = center.x

    let path = NSBezierPath()
    // Stem rectangle as path
    let stemRect = CGRect(
        x: cx - stemW / 2,
        y: stemBottom + headH * 0.35,
        width: stemW,
        height: stemH - headH * 0.15
    )
    path.appendRect(stemRect)

    // Arrow head (triangle pointing down)
    let tipY = stemBottom - headH * 0.15
    let headTop = tipY + headH
    path.move(to: CGPoint(x: cx, y: tipY))
    path.line(to: CGPoint(x: cx - headW / 2, y: headTop))
    path.line(to: CGPoint(x: cx + headW / 2, y: headTop))
    path.close()

    color.setFill()
    path.fill()
}

func pngData(from image: NSImage, pixelSize: Int) -> Data? {
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: pixelSize,
        pixelsHigh: pixelSize,
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0
    )
    guard let rep else { return nil }
    rep.size = NSSize(width: pixelSize, height: pixelSize)

    NSGraphicsContext.saveGraphicsState()
    if let ctx = NSGraphicsContext(bitmapImageRep: rep) {
        NSGraphicsContext.current = ctx
        ctx.imageInterpolation = .high
        // Draw crisp: render at exact pixel size rather than downscaling a bitmap
        let drawn = drawIcon(size: CGFloat(pixelSize))
        drawn.draw(
            in: NSRect(x: 0, y: 0, width: pixelSize, height: pixelSize),
            from: .zero,
            operation: .copy,
            fraction: 1.0
        )
    }
    NSGraphicsContext.restoreGraphicsState()

    return rep.representation(using: .png, properties: [:])
}

// MARK: - Main

func main() throws {
    let fm = FileManager.default

    // Fresh iconset directory
    if fm.fileExists(atPath: assetsDir.path) {
        try fm.removeItem(at: assetsDir)
    }
    try fm.createDirectory(at: assetsDir, withIntermediateDirectories: true)

    print("==> Drawing iconset PNGs…")
    for (name, px) in iconEntries {
        guard let data = pngData(from: drawIcon(size: CGFloat(px)), pixelSize: px) else {
            fputs("error: failed to render \(name)\n", stderr)
            exit(1)
        }
        let url = assetsDir.appendingPathComponent(name)
        try data.write(to: url, options: .atomic)
        print("    \(name) (\(px)×\(px))")
    }

    // 1024 preview at project root
    print("==> Writing icon-preview.png…")
    guard let preview = pngData(from: drawIcon(size: 1024), pixelSize: 1024) else {
        fputs("error: failed to render preview\n", stderr)
        exit(1)
    }
    try preview.write(to: previewURL, options: .atomic)

    // iconutil → AppIcon.icns
    print("==> Running iconutil…")
    if fm.fileExists(atPath: icnsURL.path) {
        try fm.removeItem(at: icnsURL)
    }
    let proc = Process()
    proc.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
    proc.arguments = ["-c", "icns", assetsDir.path, "-o", icnsURL.path]
    let errPipe = Pipe()
    proc.standardError = errPipe
    try proc.run()
    proc.waitUntilExit()
    if proc.terminationStatus != 0 {
        let err = String(data: errPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        fputs("error: iconutil failed: \(err)\n", stderr)
        exit(1)
    }

    print("==> Done:")
    print("    \(assetsDir.path)")
    print("    \(icnsURL.path)")
    print("    \(previewURL.path)")
}

do {
    try main()
} catch {
    fputs("error: \(error)\n", stderr)
    exit(1)
}
