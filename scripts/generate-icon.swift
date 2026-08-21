#!/usr/bin/env swift
import AppKit
import Foundation

// MARK: - Paths

let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let sourceURL = root.appendingPathComponent("scripts/app-icon-source.png")
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

func loadSourceImage() -> NSImage {
    guard let image = NSImage(contentsOf: sourceURL) else {
        fputs("error: missing \(sourceURL.path)\n", stderr)
        exit(1)
    }
    return image
}

func drawIcon(size: CGFloat, source: NSImage) -> NSImage {
    let image = NSImage(size: NSSize(width: size, height: size))
    image.lockFocus()
    defer { image.unlockFocus() }

    guard let ctx = NSGraphicsContext.current?.cgContext else { return image }
    ctx.setShouldAntialias(true)
    ctx.interpolationQuality = .high

    let bounds = CGRect(x: 0, y: 0, width: size, height: size)
    let corner = size * 0.2237
    let path = NSBezierPath(roundedRect: bounds, xRadius: corner, yRadius: corner)
    path.addClip()

    source.draw(
        in: bounds,
        from: .zero,
        operation: .copy,
        fraction: 1.0,
        respectFlipped: true,
        hints: [.interpolation: NSImageInterpolation.high]
    )

    return image
}

func pngData(source: NSImage, pixelSize: Int) -> Data? {
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
        let drawn = drawIcon(size: CGFloat(pixelSize), source: source)
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
    let source = loadSourceImage()

    if fm.fileExists(atPath: assetsDir.path) {
        try fm.removeItem(at: assetsDir)
    }
    try fm.createDirectory(at: assetsDir, withIntermediateDirectories: true)

    print("==> Drawing iconset PNGs from \(sourceURL.lastPathComponent)…")
    for (name, px) in iconEntries {
        guard let data = pngData(source: source, pixelSize: px) else {
            fputs("error: failed to render \(name)\n", stderr)
            exit(1)
        }
        try data.write(to: assetsDir.appendingPathComponent(name), options: .atomic)
        print("    \(name) (\(px)×\(px))")
    }

    print("==> Writing icon-preview.png…")
    guard let preview = pngData(source: source, pixelSize: 1024) else {
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
