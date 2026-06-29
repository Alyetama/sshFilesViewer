import AppKit

// Renders a 1024×1024 PNG app-icon glyph: a rounded gradient tile with a
// "remote drive" SF Symbol. Usage: swift render_icon.swift <out.png>

let out = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "icon_1024.png"
let S = 1024

guard let rep = NSBitmapImageRep(
    bitmapDataPlanes: nil, pixelsWide: S, pixelsHigh: S,
    bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
    colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
) else { exit(1) }

NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
let ctx = NSGraphicsContext.current!.cgContext

let full = CGRect(x: 0, y: 0, width: S, height: S)

// Rounded gradient background (macOS app-icon style inset + corner radius).
ctx.saveGState()
let tile = full.insetBy(dx: 44, dy: 44)
let bg = CGPath(roundedRect: tile, cornerWidth: 205, cornerHeight: 205, transform: nil)
ctx.addPath(bg)
ctx.clip()
let space = CGColorSpaceCreateDeviceRGB()
let colors = [
    CGColor(red: 0.33, green: 0.45, blue: 0.99, alpha: 1),
    CGColor(red: 0.52, green: 0.27, blue: 0.95, alpha: 1)
] as CFArray
if let grad = CGGradient(colorsSpace: space, colors: colors, locations: [0, 1]) {
    ctx.drawLinearGradient(grad, start: CGPoint(x: 0, y: S), end: CGPoint(x: S, y: 0), options: [])
}
ctx.restoreGState()

// Centered white symbol.
let cfg = NSImage.SymbolConfiguration(pointSize: 560, weight: .semibold)
    .applying(NSImage.SymbolConfiguration(paletteColors: [.white]))
if let sym = NSImage(systemSymbolName: "externaldrive.connected.to.line.below.fill",
                     accessibilityDescription: nil)?.withSymbolConfiguration(cfg) {
    let ss = sym.size
    let scale = min(540.0 / ss.width, 540.0 / ss.height)
    let w = ss.width * scale, h = ss.height * scale
    let r = NSRect(x: (Double(S) - w) / 2, y: (Double(S) - h) / 2 - 6, width: w, height: h)
    sym.draw(in: r, from: .zero, operation: .sourceOver, fraction: 1.0)
}

NSGraphicsContext.restoreGraphicsState()

guard let data = rep.representation(using: .png, properties: [:]) else { exit(1) }
do {
    try data.write(to: URL(fileURLWithPath: out))
} catch {
    FileHandle.standardError.write(Data("render_icon: \(error)\n".utf8))
    exit(1)
}
