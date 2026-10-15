// Draws the Idea Forge app icon and writes Icon/AppIcon.icns.
// Run: swift Icon/make_icon.swift   (from the project folder)
//
// Motif: a glowing amber light bulb throwing forge sparks, on a deep indigo tile.

import AppKit

let S: CGFloat = 1024

func drawIcon(in ctx: CGContext) {
    let cs = CGColorSpaceCreateDeviceRGB()
    func color(_ hex: UInt32, _ a: CGFloat = 1) -> CGColor {
        CGColor(red: CGFloat((hex >> 16) & 0xff) / 255, green: CGFloat((hex >> 8) & 0xff) / 255,
                blue: CGFloat(hex & 0xff) / 255, alpha: a)
    }
    func grad(_ stops: [(UInt32, CGFloat, CGFloat)]) -> CGGradient {
        CGGradient(colorsSpace: cs, colors: stops.map { color($0.0, $0.1) } as CFArray,
                   locations: stops.map { $0.2 })!
    }

    // Tile: macOS-style rounded square.
    let inset: CGFloat = 100
    let tile = CGRect(x: inset, y: inset, width: S - 2 * inset, height: S - 2 * inset)
    let tilePath = CGPath(roundedRect: tile, cornerWidth: 185, cornerHeight: 185, transform: nil)
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -14), blur: 30, color: color(0x000000, 0.45))
    ctx.addPath(tilePath); ctx.setFillColor(color(0x1e1b4b)); ctx.fillPath()
    ctx.restoreGState()
    ctx.saveGState()
    ctx.addPath(tilePath); ctx.clip()
    ctx.drawLinearGradient(grad([(0x4c1d95, 1, 0), (0x1e1b4b, 1, 0.65), (0x0f0d2e, 1, 1)]),
                           start: CGPoint(x: 0, y: tile.maxY), end: CGPoint(x: 0, y: tile.minY), options: [])

    let c = CGPoint(x: 512, y: 590)   // bulb centre

    // Warm glow behind the bulb.
    ctx.drawRadialGradient(grad([(0xfbbf24, 0.55, 0), (0xf59e0b, 0.18, 0.5), (0xf59e0b, 0, 1)]),
                           startCenter: c, startRadius: 0, endCenter: c, endRadius: 400, options: [])

    // Glass bulb: a circle tapering into a neck.
    let bulb = CGMutablePath()
    let R: CGFloat = 205
    let neckW: CGFloat = 96, neckY: CGFloat = 345
    let a0 = CGFloat.pi * 1.5 - 0.62   // where the round part meets the taper
    let a1 = CGFloat.pi * 1.5 + 0.62
    bulb.addArc(center: c, radius: R, startAngle: a1, endAngle: a0 + 2 * .pi, clockwise: false)
    let left = CGPoint(x: c.x + R * cos(a0), y: c.y + R * sin(a0))
    let right = CGPoint(x: c.x + R * cos(a1), y: c.y + R * sin(a1))
    bulb.addQuadCurve(to: CGPoint(x: c.x - neckW, y: neckY), control: CGPoint(x: c.x - neckW - 6, y: left.y - 30))
    bulb.addLine(to: CGPoint(x: c.x + neckW, y: neckY))
    bulb.addQuadCurve(to: right, control: CGPoint(x: c.x + neckW + 6, y: right.y - 30))
    bulb.closeSubpath()
    ctx.saveGState()
    ctx.setShadow(offset: .zero, blur: 60, color: color(0xfbbf24, 0.9))
    ctx.addPath(bulb); ctx.setFillColor(color(0xfbbf24)); ctx.fillPath()
    ctx.restoreGState()
    ctx.saveGState()
    ctx.addPath(bulb); ctx.clip()
    ctx.drawRadialGradient(grad([(0xfffbeb, 1, 0), (0xfde68a, 1, 0.35), (0xf59e0b, 1, 0.8), (0xd97706, 1, 1)]),
                           startCenter: CGPoint(x: c.x - 40, y: c.y + 50), startRadius: 0,
                           endCenter: c, endRadius: R + 40, options: [])
    // Glass highlight.
    ctx.addPath(CGPath(ellipseIn: CGRect(x: c.x - 150, y: c.y + 40, width: 90, height: 130), transform: nil))
    ctx.setFillColor(color(0xffffff, 0.45)); ctx.fillPath()
    ctx.restoreGState()

    // Filament: a zig-zag spark inside the bulb.
    let fil = CGMutablePath()
    fil.move(to: CGPoint(x: c.x - 50, y: neckY + 10))
    fil.addLine(to: CGPoint(x: c.x - 50, y: c.y - 40))
    for (k, x) in [CGFloat(-25), 0, 25, 50].enumerated() {
        fil.addLine(to: CGPoint(x: c.x + x, y: c.y - 40 + (k % 2 == 0 ? 50 : 0)))
    }
    fil.addLine(to: CGPoint(x: c.x + 50, y: neckY + 10))
    ctx.addPath(fil)
    ctx.setLineWidth(15); ctx.setLineCap(.round); ctx.setLineJoin(.round)
    ctx.setStrokeColor(color(0xb45309)); ctx.strokePath()

    // Screw base: three steel bands and a dark cap.
    for i in 0..<3 {
        let y = neckY - 28 - CGFloat(i) * 40
        let w = neckW * 2 - CGFloat(i) * 10
        let r = CGRect(x: c.x - w / 2, y: y, width: w, height: 32)
        ctx.saveGState()
        ctx.addPath(CGPath(roundedRect: r, cornerWidth: 14, cornerHeight: 14, transform: nil)); ctx.clip()
        ctx.drawLinearGradient(grad([(0xe2e8f0, 1, 0), (0x94a3b8, 1, 0.6), (0x64748b, 1, 1)]),
                               start: CGPoint(x: r.minX, y: 0), end: CGPoint(x: r.maxX, y: 0), options: [])
        ctx.restoreGState()
    }
    ctx.addPath(CGPath(roundedRect: CGRect(x: c.x - 46, y: neckY - 148, width: 92, height: 34), cornerWidth: 16, cornerHeight: 16, transform: nil))
    ctx.setFillColor(color(0x334155)); ctx.fillPath()

    // Forge sparks flying up and out.
    let sparks: [(CGFloat, CGFloat, CGFloat)] = [(-300, 300, 20), (-250, 380, 13), (290, 320, 22), (330, 220, 12),
                                                 (-330, 150, 11), (250, 410, 14), (0, 330, 16), (-120, 400, 10), (140, 395, 11)]
    for (dx, dy, r) in sparks {
        let p = CGPoint(x: c.x + dx * 0.95, y: c.y + dy * 0.62)
        ctx.saveGState()
        ctx.setShadow(offset: .zero, blur: 24, color: color(0xfde68a, 0.95))
        ctx.addPath(CGPath(ellipseIn: CGRect(x: p.x - r, y: p.y - r, width: 2 * r, height: 2 * r), transform: nil))
        ctx.setFillColor(color(0xfef3c7)); ctx.fillPath()
        ctx.restoreGState()
    }

    ctx.restoreGState()   // end tile clip
}

func renderFull(_ px: Int) -> Data {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px, bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                               colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    let g = NSGraphicsContext(bitmapImageRep: rep)!
    let ctx = g.cgContext
    ctx.scaleBy(x: CGFloat(px) / S, y: CGFloat(px) / S)
    drawIcon(in: ctx)
    return rep.representation(using: .png, properties: [:])!
}

// Every size is shrunk from one full-size drawing. Shadow and glow blur are measured in device pixels, so
// drawing straight at 16–64 px let them spill over the whole image as a faint grey square.
enum Full {
    static let png = renderFull(1024)
    static let image = NSBitmapImageRep(data: png)!.cgImage!
}

func render(_ px: Int) -> Data {
    if px == Full.image.width { return Full.png }
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px, bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                               colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    let ctx = NSGraphicsContext(bitmapImageRep: rep)!.cgContext
    ctx.interpolationQuality = .high
    ctx.draw(Full.image, in: CGRect(x: 0, y: 0, width: px, height: px))
    return rep.representation(using: .png, properties: [:])!
}

let root = URL(fileURLWithPath: CommandLine.arguments[0]).deletingLastPathComponent()
let iconset = root.appendingPathComponent("AppIcon.iconset")
try? FileManager.default.removeItem(at: iconset)
try! FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)
for base in [16, 32, 128, 256, 512] {
    try! render(base).write(to: iconset.appendingPathComponent("icon_\(base)x\(base).png"))
    try! render(base * 2).write(to: iconset.appendingPathComponent("icon_\(base)x\(base)@2x.png"))
}
try! render(1024).write(to: root.appendingPathComponent("preview.png"))
let p = Process()
p.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
p.arguments = ["-c", "icns", iconset.path, "-o", root.appendingPathComponent("AppIcon.icns").path]
try! p.run(); p.waitUntilExit()
try? FileManager.default.removeItem(at: iconset)
print(p.terminationStatus == 0 ? "Wrote \(root.path)/AppIcon.icns" : "iconutil failed")
