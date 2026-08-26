#!/usr/bin/env swift
import AppKit
import Foundation

// MARK: - Paths

let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let assetsDir = root.appendingPathComponent("scripts/AppIcon.iconset")
let icnsURL = root.appendingPathComponent("scripts/AppIcon.icns")
let previewURL = root.appendingPathComponent("icon-preview.png")

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

// The icon is drawn from a few flat vector-like shapes instead of a photographic
// source image. This keeps the icon crisp at every size and, more importantly,
// keeps the generated .icns small enough for Mist's tiny-app goal.
func drawIcon(size: CGFloat) -> NSImage {
    let image = NSImage(size: NSSize(width: size, height: size))
    image.lockFocus()
    defer { image.unlockFocus() }

    guard let ctx = NSGraphicsContext.current?.cgContext else { return image }
    ctx.setShouldAntialias(true)
    ctx.setLineCap(.round)
    ctx.setLineJoin(.round)

    let bounds = CGRect(x: 0, y: 0, width: size, height: size)
    let background = CGColor(red: 0.13, green: 0.16, blue: 0.27, alpha: 1)
    let paper = CGColor(red: 0.95, green: 0.92, blue: 0.83, alpha: 1)
    let ink = CGColor(red: 0.07, green: 0.10, blue: 0.23, alpha: 1)
    let lavender = CGColor(red: 0.38, green: 0.38, blue: 0.61, alpha: 1)
    let sage = CGColor(red: 0.45, green: 0.54, blue: 0.45, alpha: 1)
    let coral = CGColor(red: 0.73, green: 0.39, blue: 0.30, alpha: 1)

    func roundedRect(_ rect: CGRect, radius: CGFloat, color: CGColor) {
        ctx.addPath(CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil))
        ctx.setFillColor(color)
        ctx.fillPath()
    }

    // A dark macOS-style squircle containing a simple paper card.
    roundedRect(bounds, radius: size * 0.224, color: background)
    roundedRect(
        CGRect(x: size * 0.16, y: size * 0.12, width: size * 0.68, height: size * 0.76),
        radius: size * 0.105,
        color: paper
    )

    // Coordinates below use top-left-style normalized y values for readability.
    func point(_ x: CGFloat, _ yFromTop: CGFloat) -> CGPoint {
        CGPoint(x: x * size, y: (1 - yFromTop) * size)
    }

    func stroke(_ points: [(CGFloat, CGFloat)], width: CGFloat, color: CGColor) {
        ctx.beginPath()
        ctx.setStrokeColor(color)
        ctx.setLineWidth(width)
        ctx.move(to: point(points[0].0, points[0].1))
        for item in points.dropFirst() {
            ctx.addLine(to: point(item.0, item.1))
        }
        ctx.strokePath()
    }

    // Markdown heading mark and its heading rule.
    stroke([(0.285, 0.255), (0.425, 0.255)], width: size * 0.052, color: ink)
    stroke([(0.275, 0.365), (0.415, 0.365)], width: size * 0.052, color: ink)
    stroke([(0.325, 0.185), (0.295, 0.435)], width: size * 0.052, color: ink)
    stroke([(0.395, 0.185), (0.365, 0.435)], width: size * 0.052, color: ink)
    stroke([(0.505, 0.31), (0.755, 0.31)], width: size * 0.052, color: ink)

    // Three quiet document accents: a compact, recognizable Markdown page.
    // CGRect uses a bottom-left origin, so convert the human-friendly top y here.
    func topRoundedRect(
        x: CGFloat,
        top: CGFloat,
        width: CGFloat,
        height: CGFloat,
        color: CGColor
    ) {
        roundedRect(
            CGRect(
                x: size * x,
                y: size * (1 - top - height),
                width: size * width,
                height: size * height
            ),
            radius: size * 0.05,
            color: color
        )
    }

    topRoundedRect(x: 0.245, top: 0.49, width: 0.18, height: 0.10, color: lavender)
    topRoundedRect(x: 0.475, top: 0.49, width: 0.27, height: 0.10, color: coral)
    topRoundedRect(x: 0.245, top: 0.66, width: 0.27, height: 0.10, color: sage)
    topRoundedRect(x: 0.575, top: 0.66, width: 0.17, height: 0.10, color: lavender)

    return image
}

func pngData(pixelSize: Int) -> Data? {
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

func main() throws {
    let fm = FileManager.default
    if fm.fileExists(atPath: assetsDir.path) {
        try fm.removeItem(at: assetsDir)
    }
    try fm.createDirectory(at: assetsDir, withIntermediateDirectories: true)

    print("==> Drawing compact vector iconset…")
    for (name, px) in iconEntries {
        guard let data = pngData(pixelSize: px) else {
            fputs("error: failed to render \(name)\n", stderr)
            exit(1)
        }
        try data.write(to: assetsDir.appendingPathComponent(name), options: .atomic)
        print("    \(name) (\(px)×\(px))")
    }

    print("==> Writing icon-preview.png…")
    guard let preview = pngData(pixelSize: 1024) else {
        fputs("error: failed to render preview\n", stderr)
        exit(1)
    }
    try preview.write(to: previewURL, options: .atomic)

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
