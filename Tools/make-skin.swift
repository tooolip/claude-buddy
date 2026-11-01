// Draws a built-in skin as sprite strips plus a manifest.
// Usage: swift Tools/make-skin.swift mochi Skins/default
//        swift Tools/make-skin.swift aftonsparv Skins/aftonsparv
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

let size: CGFloat = 144 // 72pt at 2x
let args = Array(CommandLine.arguments.dropFirst())
let character = args.count >= 2 ? args[0] : "mochi"
let outDir = URL(fileURLWithPath: args.last ?? "Skins/default")

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

func drawZs(_ c: CGContext, phase: CGFloat, at origin: CGPoint, color hex: UInt32) {
    for (i, base) in [CGFloat(0), 0.5].enumerated() {
        let t = (phase + base).truncatingRemainder(dividingBy: 1)
        let s: CGFloat = 8 + CGFloat(i) * 3 + t * 4
        let o = CGPoint(x: origin.x + t * 14, y: origin.y + t * 30)
        let alpha = t < 0.15 ? t / 0.15 : (1 - t)
        strokeLine(c, [CGPoint(x: o.x, y: o.y + s), CGPoint(x: o.x + s, y: o.y + s),
                       CGPoint(x: o.x, y: o.y), CGPoint(x: o.x + s, y: o.y)],
                   width: 2.5, color: rgb(hex, alpha))
    }
}

// MARK: - Mochi (default)

func drawMochi(_ c: CGContext, _ p: Pose) {
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

    if let phase = p.zPhase {
        drawZs(c, phase: phase, at: CGPoint(x: cx + 30, y: body.maxY - 12), color: 0x3E3266)
    }
}

// MARK: - Aftonsparv (cartoon take on IKEA's green alien soft toy)

let afBody = rgb(0x1FA06C)
let afShade = rgb(0x178858)
let afInk = rgb(0x0E3B28)
let afEye = rgb(0x2A1517)
let afPink = rgb(0xF4A3B8)
let afNavy = rgb(0x22357A)
let afYellow = rgb(0xF2C230)

func fillStroke(_ c: CGContext, _ path: CGPath, fill: CGColor, width: CGFloat = 2.5) {
    c.setFillColor(fill); c.setStrokeColor(afInk); c.setLineWidth(width)
    c.addPath(path); c.drawPath(using: .fillStroke)
}

/// Big slanted alien eye. `angle` tilts the outer corner up.
func alienEye(_ c: CGContext, at p: CGPoint, angle: CGFloat, eyes: Eyes, scale: CGFloat) {
    let w = 28 * scale, h = 19 * scale
    c.saveGState()
    c.translateBy(x: p.x, y: p.y)
    c.rotate(by: angle)
    c.setFillColor(afEye)
    switch eyes {
    case .open, .wide:
        c.fillEllipse(in: CGRect(x: -w / 2, y: -h / 2, width: w, height: h))
    case .half:
        c.fillEllipse(in: CGRect(x: -w / 2, y: -h / 4, width: w, height: h / 2))
    case .blink:
        c.fillEllipse(in: CGRect(x: -w / 2, y: -1.5, width: w, height: 3))
    case .sleep:
        let lid = CGMutablePath()
        lid.move(to: CGPoint(x: -w * 0.42, y: 1))
        lid.addQuadCurve(to: CGPoint(x: w * 0.42, y: 1), control: CGPoint(x: 0, y: -h * 0.45))
        c.setStrokeColor(afEye); c.setLineWidth(3); c.setLineCap(.round)
        c.addPath(lid); c.strokePath()
    }
    c.restoreGState()
    if eyes == .open || eyes == .wide {
        c.setFillColor(rgb(0xFFFFFF))
        let r = (eyes == .wide ? 3.8 : 3.2) * scale
        c.fillEllipse(in: CGRect(x: p.x + w * 0.12 - r, y: p.y + h * 0.12 - r, width: r * 2, height: r * 2))
        c.fillEllipse(in: CGRect(x: p.x + w * 0.3 - 1.6, y: p.y - h * 0.12 - 1.6, width: 3.2, height: 3.2))
    }
}

func drawAftonsparv(_ c: CGContext, _ p: Pose) {
    let cx = size / 2
    let held = p.swing != nil
    let base: CGFloat = (held ? 11 : 14) + p.dy
    var gesture: CGFloat = 0
    if case .open(let a) = p.mouth { gesture = a }

    if !held {
        let sw = 52 - p.dy * 2
        c.setFillColor(rgb(0x000000, 0.16))
        c.fillEllipse(in: CGRect(x: cx - sw / 2, y: 8, width: sw, height: 9))
    }

    // Legs
    for side: CGFloat in [-1, 1] {
        var r = CGRect(x: cx + side * 8 - 7, y: base, width: 14, height: 22)
        if let s = p.swing { r.origin.x += s * 3 * side; r.origin.y -= 4 }
        fillStroke(c, CGPath(roundedRect: r, cornerWidth: 7, cornerHeight: 7, transform: nil), fill: afShade)
    }

    let bw = 40 * p.sx, bh = 34 * p.sy
    let body = CGRect(x: cx - bw / 2, y: base + 12, width: bw, height: bh)

    // Arms sit behind the body, hands out to the sides (up by the head while held)
    let shoulderY = body.maxY - 9
    for side: CGFloat in [-1, 1] {
        let shoulder = CGPoint(x: cx + side * (bw / 2 - 6), y: shoulderY)
        var hand = CGPoint(x: cx + side * 31, y: shoulderY - 9)
        if held { hand = CGPoint(x: cx + side * 43, y: shoulderY + 10) }
        if side > 0 { hand.y += gesture * 7 }
        strokeLine(c, [shoulder, hand], width: 13, color: afInk)
        strokeLine(c, [shoulder, hand], width: 8, color: afBody)
        let palm = CGRect(x: hand.x - 7, y: hand.y - 7, width: 14, height: 14)
        fillStroke(c, CGPath(ellipseIn: palm, transform: nil), fill: afBody)
        // the little printed pattern on its hands
        let tri = CGMutablePath()
        tri.move(to: CGPoint(x: hand.x - 3.5, y: hand.y + 2.5))
        tri.addLine(to: CGPoint(x: hand.x + 3.5, y: hand.y + 2.5))
        tri.addLine(to: CGPoint(x: hand.x, y: hand.y - 3))
        tri.closeSubpath()
        c.setFillColor(afYellow); c.addPath(tri); c.fillPath()
        c.setFillColor(afNavy); c.fillEllipse(in: CGRect(x: hand.x - side * 4.5 - 1.5, y: hand.y - 4, width: 3, height: 3))
        c.setFillColor(afPink); c.fillEllipse(in: CGRect(x: hand.x + side * 3.5 - 1.3, y: hand.y - 5, width: 2.6, height: 2.6))
    }

    // Body, with the ribbed fabric
    fillStroke(c, CGPath(ellipseIn: body, transform: nil), fill: afBody)
    c.saveGState()
    c.addEllipse(in: body.insetBy(dx: 2, dy: 2)); c.clip()
    for i in -2...2 {
        let x = cx + CGFloat(i) * 6
        strokeLine(c, [CGPoint(x: x, y: body.minY), CGPoint(x: x, y: body.maxY)], width: 1, color: rgb(0x0E3B28, 0.18))
    }
    c.restoreGState()

    // Head
    let hw = 74 * p.sx, hh = 58 * p.sy
    let head = CGRect(x: cx - hw / 2, y: body.maxY - 8, width: hw, height: hh)

    // Antennae (behind the head): pink tip on the left, navy on the right
    for (side, dot) in [(CGFloat(-1), afPink), (1, afNavy)] {
        let root = CGPoint(x: cx + side * 13, y: head.maxY - 8)
        let tip = CGPoint(x: cx + side * 26 + p.sway * 3, y: head.maxY + 14)
        strokeLine(c, [root, tip], width: 8, color: afInk)
        strokeLine(c, [root, tip], width: 3.5, color: afBody)
        fillStroke(c, CGPath(ellipseIn: CGRect(x: tip.x - 7, y: tip.y - 7, width: 14, height: 14), transform: nil),
                   fill: afBody)
        c.setFillColor(dot); c.fillEllipse(in: CGRect(x: tip.x - 3.3, y: tip.y - 3.3, width: 6.6, height: 6.6))
    }

    fillStroke(c, CGPath(ellipseIn: head, transform: nil), fill: afBody)
    c.setFillColor(rgb(0xFFFFFF, 0.16))
    c.fillEllipse(in: CGRect(x: head.minX + hw * 0.16, y: head.minY + hh * 0.6, width: hw * 0.3, height: hh * 0.24))
    // seam down the top of the head
    strokeLine(c, [CGPoint(x: cx, y: head.maxY - 1), CGPoint(x: cx, y: head.maxY - 13)], width: 1.5, color: rgb(0x0E3B28, 0.4))

    // Face: big slanted eyes, tiny nose, a mouth only when it talks
    let ey = head.minY + hh * 0.46
    let eyeScale: CGFloat = p.eyes == .wide ? 1.12 : 1
    alienEye(c, at: CGPoint(x: cx - 17 * max(p.sx, 1), y: ey), angle: -0.42, eyes: p.eyes, scale: eyeScale)
    alienEye(c, at: CGPoint(x: cx + 17 * max(p.sx, 1), y: ey), angle: 0.42, eyes: p.eyes, scale: eyeScale)
    c.setFillColor(afEye)
    c.fillEllipse(in: CGRect(x: cx - 2, y: ey - 12, width: 4, height: 3))
    let my = ey - 19
    switch p.mouth {
    case .open(let a) where a > 0.05:
        let h = 2 + 7 * a
        c.fillEllipse(in: CGRect(x: cx - 5, y: my - h / 2, width: 10, height: h))
        if a > 0.5 {
            c.setFillColor(afPink); c.fillEllipse(in: CGRect(x: cx - 3, y: my - h / 2 + 0.5, width: 6, height: h * 0.4))
        }
    case .oh:
        c.fillEllipse(in: CGRect(x: cx - 3, y: my - 3.5, width: 6, height: 7))
    default:
        break
    }

    if let phase = p.zPhase {
        drawZs(c, phase: phase, at: CGPoint(x: cx + 33, y: head.maxY - 22), color: 0x0E3B28)
    }
}

func drawCharacter(_ c: CGContext, _ p: Pose) {
    character == "aftonsparv" ? drawAftonsparv(c, p) : drawMochi(c, p)
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
        drawCharacter(ctx, pose)
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
  "name": "\(character == "aftonsparv" ? "Aftonsparv" : "Mochi")",
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
