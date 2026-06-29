import AppKit

// Renders a 1024×1024 PNG app-icon glyph: a rounded gradient tile with a white
// folder carrying a terminal-prompt ">_" — "files" + "SSH/terminal".
// Usage: swift render_icon.swift <out.png>

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
let space = CGColorSpaceCreateDeviceRGB()

func rgb(_ r: Double, _ g: Double, _ b: Double, _ a: Double = 1) -> CGColor {
    CGColor(colorSpace: space, components: [CGFloat(r), CGFloat(g), CGFloat(b), CGFloat(a)])!
}

let full = CGRect(x: 0, y: 0, width: S, height: S)
let tile = full.insetBy(dx: 44, dy: 44)
let tilePath = CGPath(roundedRect: tile, cornerWidth: 205, cornerHeight: 205, transform: nil)

// --- Background: blue → violet gradient with a soft top sheen.
ctx.saveGState()
ctx.addPath(tilePath); ctx.clip()
if let grad = CGGradient(colorsSpace: space,
                         colors: [rgb(0.31, 0.49, 1.0), rgb(0.46, 0.24, 0.94)] as CFArray,
                         locations: [0, 1]) {
    ctx.drawLinearGradient(grad, start: CGPoint(x: 140, y: Double(S) - 90),
                           end: CGPoint(x: Double(S) - 140, y: 90), options: [])
}
if let sheen = CGGradient(colorsSpace: space,
                          colors: [rgb(1, 1, 1, 0.16), rgb(1, 1, 1, 0)] as CFArray,
                          locations: [0, 1]) {
    ctx.drawLinearGradient(sheen, start: CGPoint(x: 0, y: Double(S)),
                           end: CGPoint(x: 0, y: Double(S) * 0.52), options: [])
}
ctx.restoreGState()

let white = rgb(1, 1, 1)
let whiteSoft = rgb(0.92, 0.94, 0.99)

// --- Folder back tab (peeks above the body), with a drop shadow.
ctx.saveGState()
ctx.setShadow(offset: CGSize(width: 0, height: -24), blur: 54, color: rgb(0.10, 0.06, 0.30, 0.40))
let tab = CGPath(roundedRect: CGRect(x: 252, y: 605, width: 290, height: 120),
                 cornerWidth: 40, cornerHeight: 40, transform: nil)
ctx.addPath(tab); ctx.setFillColor(whiteSoft); ctx.fillPath()
ctx.restoreGState()

// --- Folder body (front), subtle vertical white gradient for depth.
let body = CGRect(x: 232, y: 300, width: 560, height: 352)
let bodyPath = CGPath(roundedRect: body, cornerWidth: 48, cornerHeight: 48, transform: nil)
ctx.saveGState()
ctx.setShadow(offset: CGSize(width: 0, height: -10), blur: 26, color: rgb(0.10, 0.06, 0.30, 0.22))
ctx.addPath(bodyPath); ctx.setFillColor(white); ctx.fillPath()
ctx.restoreGState()
ctx.saveGState()
ctx.addPath(bodyPath); ctx.clip()
if let g = CGGradient(colorsSpace: space, colors: [white, whiteSoft] as CFArray, locations: [0, 1]) {
    ctx.drawLinearGradient(g, start: CGPoint(x: 0, y: 652), end: CGPoint(x: 0, y: 300), options: [])
}
ctx.restoreGState()

// --- Terminal prompt ">_" centered on the folder body (≈ 512, 476).
let green = rgb(0.27, 0.70, 0.41)
ctx.setLineCap(.round)
ctx.setLineJoin(.round)
ctx.setLineWidth(40)
ctx.setStrokeColor(green)
ctx.beginPath()
ctx.move(to: CGPoint(x: 388, y: 548))
ctx.addLine(to: CGPoint(x: 484, y: 476))
ctx.addLine(to: CGPoint(x: 388, y: 404))
ctx.strokePath()

ctx.setFillColor(green)
let underscore = CGPath(roundedRect: CGRect(x: 520, y: 404, width: 150, height: 38),
                        cornerWidth: 19, cornerHeight: 19, transform: nil)
ctx.addPath(underscore); ctx.fillPath()

NSGraphicsContext.restoreGraphicsState()

guard let data = rep.representation(using: .png, properties: [:]) else { exit(1) }
do {
    try data.write(to: URL(fileURLWithPath: out))
} catch {
    FileHandle.standardError.write(Data("render_icon: \(error)\n".utf8))
    exit(1)
}
