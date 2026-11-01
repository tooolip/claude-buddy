// Draws the default "Mochi" skin as sprite strips plus a manifest.
// Usage: swift Tools/make-skin.swift Skins/default
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

let size: CGFloat = 144 // 72pt at 2x
let outDir = URL(fileURLWithPath: CommandLine.arguments.dropFirst().first ?? "Skins/default")

func rgb(_ hex: UInt32, _ a: CGFloat = 1) -> CGColor {
    CGColor(red: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255, alpha: a)
}

let bodyColor = rgb(0xB9A7F2)
let bodyShade = rgb(0x9C88E0)
let ink = rgb(0x3E3266)
let leaf = rgb(0x7CC48A)
let cheek = rgb(0xF59FB8, 0.55)

enum Eyes { case open, half, blink, sleep, wide }
enum Mouth { case smile, open(CGFloat), oh, sleep }

struct Pose {
    var dy: CGFloat = 0
    var sx: CGFloat = 1
    var sy: CGFloat = 1
    var eyes = Eyes.open
    var mouth = Mouth.smile
    var zPhase: CGFloat? = nil   // 0...1, rising z's
    var swing: CGFloat? = nil    // -1...1, dangling feet while held
    var sway: CGFloat = 0        // sprout lean
}

func strokeLine(_ c: CGContext, _ pts: [CGPoint], width: CGFloat, color: CGColor) {
    c.saveGState()
    c.setStrokeColor(color); c.setLineWidth(width); c.setLineCap(.round); c.setLineJoin(.round)
    c.addLines(between: pts); c.strokePath()
    c.restoreGState()
}

func draw(_ c: CGContext, _ p: Pose) {
    let cx = size / 2
    let held = p.swing != nil
    let bw = 92 * p.sx, bh = 78 * p.sy
    let bottom: CGFloat = (held ? 28 : 22) + p.dy

    // Ground shadow (not while held up in the air)
    if !held {
        let sw = 74 - p.dy * 2
        c.setFillColor(rgb(0x000000, 0.16))
        c.fillEllipse(in: CGRect(x: cx - sw / 2, y: 10, width: sw, height: 10))
    }

    // Feet
    c.setFillColor(bodyShade); c.setStrokeColor(ink); c.setLineWidth(3)
    for side: CGFloat in [-1, 1] {
        var fx = cx + side * 22 - 11, fy = bottom - 6
        if let s = p.swing { fx += s * 5 * side; fy = bottom - 16 + abs(s) * 2 }
        let r = CGRect(x: fx, y: fy, width: 22, height: 13)
        c.addEllipse(in: r); c.drawPath(using: .fillStroke)
    }

    // Body
    let body = CGRect(x: cx - bw / 2, y: bottom, width: bw, height: bh)
    c.setFillColor(bodyColor); c.addEllipse(in: body); c.drawPath(using: .fillStroke)
    c.setFillColor(rgb(0xFFFFFF, 0.35))
    c.fillEllipse(in: CGRect(x: body.minX + bw * 0.18, y: body.minY + bh * 0.62, width: bw * 0.3, height: bh * 0.2))

    // Sprout
    let top = CGPoint(x: cx, y: body.maxY - 2)
    let tip = CGPoint(x: cx + p.sway * 4, y: top.y + 14)
    strokeLine(c, [top, CGPoint(x: cx + p.sway * 2, y: top.y + 7), tip], width: 3, color: ink)
    c.setFillColor(leaf)
    for side: CGFloat in [-1, 1] {
        c.saveGState()
        c.translateBy(x: tip.x, y: tip.y)
        c.rotate(by: side * (0.5 + p.sway * 0.15 * side))
        let r = CGRect(x: side > 0 ? 0 : -16, y: -4, width: 16, height: 9)
        c.addEllipse(in: r); c.drawPath(using: .fillStroke)
        c.restoreGState()
    }

    // Face
    let ey = body.minY + bh * 0.52
    let ex = 18 * p.sx
    c.setFillColor(cheek)
    for side: CGFloat in [-1, 1] {
        c.fillEllipse(in: CGRect(x: cx + side * 30 * p.sx - 7, y: ey - 13, width: 14, height: 8))
    }
    for side: CGFloat in [-1, 1] {
        let x = cx + side * ex
        switch p.eyes {
        case .open, .wide:
            let w: CGFloat = p.eyes == .wide ? 13 : 10, h: CGFloat = p.eyes == .wide ? 16 : 13
            c.setFillColor(ink); c.fillEllipse(in: CGRect(x: x - w / 2, y: ey - h / 2, width: w, height: h))
            c.setFillColor(rgb(0xFFFFFF))
            c.fillEllipse(in: CGRect(x: x + w * 0.05, y: ey + h * 0.12, width: w * 0.38, height: w * 0.38))
        case .half:
            c.setFillColor(ink); c.fillEllipse(in: CGRect(x: x - 5, y: ey - 3, width: 10, height: 6))
        case .blink:
            strokeLine(c, [CGPoint(x: x - 6, y: ey), CGPoint(x: x + 6, y: ey)], width: 3, color: ink)
        case .sleep:
            strokeLine(c, [CGPoint(x: x - 6, y: ey + 1), CGPoint(x: x, y: ey - 3), CGPoint(x: x + 6, y: ey + 1)],
                       width: 3, color: ink)
        }
    }
    let my = ey - 15
    switch p.mouth {
    case .smile:
        strokeLine(c, [CGPoint(x: cx - 6, y: my + 2), CGPoint(x: cx, y: my - 2), CGPoint(x: cx + 6, y: my + 2)],
                   width: 3, color: ink)
    case .open(let a):
        let h = 4 + 10 * a, w: CGFloat = 13
        c.setFillColor(ink); c.fillEllipse(in: CGRect(x: cx - w / 2, y: my - h / 2, width: w, height: h))
        if a > 0.4 {
            c.setFillColor(rgb(0xF07A9A))
            c.fillEllipse(in: CGRect(x: cx - 4, y: my - h / 2 + 1, width: 8, height: h * 0.4))
        }
    case .oh:
        c.setFillColor(ink); c.fillEllipse(in: CGRect(x: cx - 4, y: my - 5, width: 8, height: 10))
    case .sleep:
        c.setFillColor(ink); c.fillEllipse(in: CGRect(x: cx - 3, y: my - 2, width: 6, height: 5))
    }

    // Floating z's
    if let phase = p.zPhase {
        for (i, base) in [CGFloat(0), 0.5].enumerated() {
            let t = (phase + base).truncatingRemainder(dividingBy: 1)
            let s: CGFloat = 8 + CGFloat(i) * 3 + t * 4
            let o = CGPoint(x: cx + 30 + t * 14, y: body.maxY - 12 + t * 30)
            let alpha = t < 0.15 ? t / 0.15 : (1 - t)
            strokeLine(c, [CGPoint(x: o.x, y: o.y + s), CGPoint(x: o.x + s, y: o.y + s),
                           CGPoint(x: o.x, y: o.y), CGPoint(x: o.x + s, y: o.y)],
                       width: 2.5, color: rgb(0x3E3266, alpha))
        }
    }
}

func writeStrip(_ name: String, _ poses: [Pose]) throws {
    let w = Int(size) * poses.count, h = Int(size)
    let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                        space: CGColorSpace(name: CGColorSpace.sRGB)!,
                        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    for (i, pose) in poses.enumerated() {
        ctx.saveGState()
        ctx.translateBy(x: CGFloat(i) * size, y: 0)
        ctx.clip(to: CGRect(x: 0, y: 0, width: size, height: size))
        draw(ctx, pose)
        ctx.restoreGState()
    }
    let url = outDir.appendingPathComponent(name)
    let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)!
    CGImageDestinationAddImage(dest, ctx.makeImage()!, nil)
    guard CGImageDestinationFinalize(dest) else { throw NSError(domain: "png", code: 1) }
}

let tau = CGFloat.pi * 2

let idle: [Pose] = (0..<16).map { i in
    let t = CGFloat(i) / 16
    var p = Pose(dy: sin(t * tau) * 2.5, sx: 1 + sin(t * tau) * -0.015, sy: 1 + sin(t * tau) * 0.02,
                 sway: sin(t * tau + 1))
    if i == 12 { p.eyes = .half }
    if i == 13 { p.eyes = .blink }
    return p
}

let talking: [Pose] = (0..<8).map { i in
    let opens: [CGFloat] = [0.2, 0.7, 1, 0.5, 0.15, 0.8, 0.4, 0]
    let t = CGFloat(i) / 8
    return Pose(dy: abs(sin(t * tau)) * 3, sx: 1, sy: 1 + abs(sin(t * tau)) * 0.03,
                mouth: .open(opens[i]), sway: sin(t * tau * 2) * 1.5)
}

let sleeping: [Pose] = (0..<8).map { i in
    let t = CGFloat(i) / 8
    return Pose(dy: -2, sx: 1.04 + sin(t * tau) * 0.03, sy: 0.94 + sin(t * tau) * 0.035,
                eyes: .sleep, mouth: .sleep, zPhase: t, sway: -1.5)
}

let dragging: [Pose] = (0..<4).map { i in
    let swing: [CGFloat] = [-1, -0.3, 1, 0.3]
    return Pose(sx: 0.9, sy: 1.1, eyes: .wide, mouth: .oh, swing: swing[i], sway: -swing[i] * 2)
}

try FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)
try writeStrip("idle.png", idle)
try writeStrip("talking.png", talking)
try writeStrip("sleeping.png", sleeping)
try writeStrip("dragging.png", dragging)

let manifest = """
{
  "name": "Mochi",
  "frameWidth": 144,
  "frameHeight": 144,
  "scale": 2,
  "states": {
    "idle":     { "sheet": "idle.png",     "frames": \(idle.count),     "fps": 8 },
    "talking":  { "sheet": "talking.png",  "frames": \(talking.count),  "fps": 10 },
    "sleeping": { "sheet": "sleeping.png", "frames": \(sleeping.count), "fps": 4 },
    "dragging": { "sheet": "dragging.png", "frames": \(dragging.count), "fps": 10 }
  }
}

"""
try manifest.write(to: outDir.appendingPathComponent("manifest.json"), atomically: true, encoding: .utf8)
print("Wrote skin to \(outDir.path)")
