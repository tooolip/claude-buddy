// Style mockups for the Aftonsparv pet. swiftc -O styles.swift -o styles && ./styles <out.png>
import CoreGraphics
import CoreText
import Foundation
import ImageIO
import UniformTypeIdentifiers

func rgb(_ hex: UInt32, _ a: CGFloat = 1) -> CGColor {
    CGColor(red: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255, alpha: a)
}

struct RNG {
    var s: UInt64
    mutating func next() -> CGFloat {
        s = s &* 6364136223846793005 &+ 1442695040888963407
        return CGFloat((s >> 33) & 0xFFFFFF) / CGFloat(0xFFFFFF)
    }
    mutating func r(_ a: CGFloat, _ b: CGFloat) -> CGFloat { a + (b - a) * next() }
}

// MARK: - Shared geometry (144 x 144 units, y up)

enum Role { case body, shade, eye, eyeDot, dot, navy, seam, sheen }

struct Part {
    var role: Role
    var pts: [CGPoint]
    var closed = true
    var tag = ""
    var angle: CGFloat = 0
}

func ellipsePts(_ r: CGRect, n: Int = 56, angle: CGFloat = 0) -> [CGPoint] {
    let c = CGPoint(x: r.midX, y: r.midY)
    return (0..<n).map { i in
        let t = CGFloat(i) / CGFloat(n) * 2 * .pi
        let x = cos(t) * r.width / 2, y = sin(t) * r.height / 2
        return CGPoint(x: c.x + x * cos(angle) - y * sin(angle), y: c.y + x * sin(angle) + y * cos(angle))
    }
}

func circle(_ c: CGPoint, _ r: CGFloat) -> CGRect { CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2) }

func capsulePts(_ a: CGPoint, _ b: CGPoint, r: CGFloat, n: Int = 14) -> [CGPoint] {
    let ang = atan2(b.y - a.y, b.x - a.x)
    var pts: [CGPoint] = []
    for i in 0...n {
        let t = ang - .pi / 2 + CGFloat(i) / CGFloat(n) * .pi
        pts.append(CGPoint(x: b.x + cos(t) * r, y: b.y + sin(t) * r))
    }
    for i in 0...n {
        let t = ang + .pi / 2 + CGFloat(i) / CGFloat(n) * .pi
        pts.append(CGPoint(x: a.x + cos(t) * r, y: a.y + sin(t) * r))
    }
    return pts
}

func path(_ pts: [CGPoint], closed: Bool = true) -> CGPath {
    let p = CGMutablePath()
    p.addLines(between: pts)
    if closed { p.closeSubpath() }
    return p
}

func bbox(_ pts: [CGPoint]) -> CGRect {
    let xs = pts.map(\.x), ys = pts.map(\.y)
    return CGRect(x: xs.min()!, y: ys.min()!, width: xs.max()! - xs.min()!, height: ys.max()! - ys.min()!)
}

struct Shape {
    var head = CGSize(width: 62, height: 52)
    var torso = CGSize(width: 34, height: 34)
    var legs = CGSize(width: 12, height: 32)
    var legGap: CGFloat = 7
    var handX: CGFloat = 31, handY: CGFloat = 4, handR: CGFloat = 5.5, armW: CGFloat = 7.5
    var eye = CGSize(width: 27, height: 18)
    var eyeX: CGFloat = 16, eyeAngle: CGFloat = 0.5, eyeYFrac: CGFloat = 0.5
    var antRootX: CGFloat = 9, antTipX: CGFloat = 19, antRise: CGFloat = 15, tipR: CGFloat = 6.5, stalkW: CGFloat = 3
    var mouth = CGSize(width: 4.5, height: 4)
    var mouthYFrac: CGFloat = 0.16
    var hlR: CGFloat = 3.3
    var seam = true
    var sheen = true
}

struct Layout { var head: CGRect; var eyeY: CGFloat }

func alienParts(_ s: Shape) -> ([Part], Layout) {
    let cx: CGFloat = 72, base: CGFloat = 12
    var parts: [Part] = []
    for side: CGFloat in [-1, 1] {
        let x = cx + side * s.legGap
        parts.append(Part(role: .shade, pts: capsulePts(CGPoint(x: x, y: base + s.legs.width / 2),
                                                         CGPoint(x: x, y: base + s.legs.height - s.legs.width / 2),
                                                         r: s.legs.width / 2)))
    }
    let torso = CGRect(x: cx - s.torso.width / 2, y: base + s.legs.height - 8, width: s.torso.width, height: s.torso.height)
    for side: CGFloat in [-1, 1] {
        let shoulder = CGPoint(x: cx + side * s.torso.width * 0.32, y: torso.maxY - 7)
        let hand = CGPoint(x: cx + side * s.handX, y: torso.minY + s.handY)
        parts.append(Part(role: .body, pts: capsulePts(shoulder, hand, r: s.armW / 2), tag: "arm"))
        parts.append(Part(role: .body, pts: ellipsePts(circle(hand, s.handR)), tag: "hand"))
        parts.append(Part(role: .dot, pts: ellipsePts(circle(CGPoint(x: hand.x + side * 1.5, y: hand.y - 1.4), 1.6), n: 16)))
        parts.append(Part(role: .navy, pts: ellipsePts(circle(CGPoint(x: hand.x - side * 2, y: hand.y + 0.8), 1.3), n: 16)))
    }
    parts.append(Part(role: .body, pts: ellipsePts(torso), tag: "torso"))
    let head = CGRect(x: cx - s.head.width / 2, y: torso.maxY - 7, width: s.head.width, height: s.head.height)
    for side: CGFloat in [-1, 1] {
        let root = CGPoint(x: cx + side * s.antRootX, y: head.maxY - 6)
        let tip = CGPoint(x: cx + side * s.antTipX, y: head.maxY + s.antRise)
        parts.append(Part(role: .body, pts: capsulePts(root, tip, r: s.stalkW / 2), tag: "stalk"))
        parts.append(Part(role: .body, pts: ellipsePts(circle(tip, s.tipR)), tag: "tip"))
        parts.append(Part(role: side < 0 ? .dot : .navy, pts: ellipsePts(circle(tip, s.tipR * 0.43), n: 20)))
    }
    parts.append(Part(role: .body, pts: ellipsePts(head, n: 80), tag: "head"))
    if s.sheen {
        parts.append(Part(role: .sheen, pts: ellipsePts(CGRect(x: head.minX + head.width * 0.18, y: head.minY + head.height * 0.66,
                                                                width: head.width * 0.28, height: head.height * 0.18))))
    }
    if s.seam {
        parts.append(Part(role: .seam, pts: [CGPoint(x: cx, y: head.maxY - 1), CGPoint(x: cx, y: head.minY + head.height * 0.3)],
                          closed: false))
    }
    let ey = head.minY + head.height * s.eyeYFrac
    for side: CGFloat in [-1, 1] {
        let c = CGPoint(x: cx + side * s.eyeX, y: ey)
        let a = side * s.eyeAngle
        parts.append(Part(role: .eye, pts: ellipsePts(CGRect(x: c.x - s.eye.width / 2, y: c.y - s.eye.height / 2,
                                                              width: s.eye.width, height: s.eye.height), n: 64, angle: a),
                          tag: "eye", angle: a))
        func local(_ p: CGPoint) -> CGPoint {
            CGPoint(x: c.x + p.x * cos(a) - p.y * sin(a), y: c.y + p.x * sin(a) + p.y * cos(a))
        }
        parts.append(Part(role: .eyeDot, pts: ellipsePts(circle(local(CGPoint(x: side * s.eye.width * 0.26, y: s.eye.height * 0.1)), s.hlR), n: 24), angle: a))
        parts.append(Part(role: .eyeDot, pts: ellipsePts(circle(local(CGPoint(x: side * s.eye.width * 0.2, y: -s.eye.height * 0.24)), s.hlR * 0.55), n: 16), angle: a))
    }
    let my = head.minY + head.height * s.mouthYFrac
    parts.append(Part(role: .eye, pts: ellipsePts(CGRect(x: cx - s.mouth.width / 2, y: my - s.mouth.height / 2,
                                                          width: s.mouth.width, height: s.mouth.height), n: 24), tag: "mouth"))
    return (parts, Layout(head: head, eyeY: ey))
}

struct Palette {
    var body: CGColor, shade: CGColor, eye: CGColor, eyeDot: CGColor, dot: CGColor, navy: CGColor, ink: CGColor
    func color(_ r: Role) -> CGColor {
        switch r {
        case .body: body
        case .shade: shade
        case .eye: eye
        case .eyeDot: eyeDot
        case .dot: dot
        case .navy: navy
        case .seam, .sheen: ink
        }
    }
}

let flatPalette = Palette(body: rgb(0x36A852), shade: rgb(0x2C8F45), eye: rgb(0x111214), eyeDot: rgb(0xE4E6E8),
                          dot: rgb(0xE4E6E8), navy: rgb(0x1F2A5C), ink: rgb(0x15472B))

func strokeOpen(_ c: CGContext, _ pts: [CGPoint], width: CGFloat, color: CGColor) {
    c.saveGState()
    c.setStrokeColor(color); c.setLineWidth(width); c.setLineCap(.round); c.setLineJoin(.round)
    c.addLines(between: pts); c.strokePath()
    c.restoreGState()
}

// MARK: - Styles

func renderFlat(_ c: CGContext, _ parts: [Part], _ pal: Palette, line: CGFloat = 2.5) {
    c.setLineJoin(.round)
    for p in parts {
        switch p.role {
        case .seam: strokeOpen(c, p.pts, width: 1.4, color: pal.ink.copy(alpha: 0.32)!)
        case .sheen: c.setFillColor(rgb(0xFFFFFF, 0.15)); c.addPath(path(p.pts)); c.fillPath()
        case .eye, .eyeDot, .dot, .navy: c.setFillColor(pal.color(p.role)); c.addPath(path(p.pts)); c.fillPath()
        case .body, .shade:
            c.setFillColor(pal.color(p.role)); c.setStrokeColor(pal.ink); c.setLineWidth(line)
            c.addPath(path(p.pts)); c.drawPath(using: .fillStroke)
        }
    }
}

func offscreen(px: Int, _ draw: (CGContext) -> Void) -> CGImage {
    let ctx = CGContext(data: nil, width: px, height: px, bitsPerComponent: 8, bytesPerRow: 0,
                        space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.scaleBy(x: CGFloat(px) / 144, y: CGFloat(px) / 144)
    draw(ctx)
    return ctx.makeImage()!
}

/// Every style draws the same 144-unit square into `rect` (pixels).
typealias Style = (CGContext, CGRect) -> Void

func unitSpace(_ c: CGContext, _ rect: CGRect, _ draw: (CGContext) -> Void) {
    c.saveGState()
    c.translateBy(x: rect.minX, y: rect.minY)
    c.scaleBy(x: rect.width / 144, y: rect.height / 144)
    draw(c)
    c.restoreGState()
}

func groundShadow(_ c: CGContext, width: CGFloat = 46, alpha: CGFloat = 0.16) {
    c.setFillColor(rgb(0x000000, alpha))
    c.fillEllipse(in: CGRect(x: 72 - width / 2, y: 7, width: width, height: 8))
}

let currentStyle: Style = { c, rect in
    unitSpace(c, rect) { c in
        groundShadow(c)
        renderFlat(c, alienParts(Shape()).0, flatPalette)
    }
}

let stickerStyle: Style = { c, rect in
    let px = Int(rect.width)
    let art = offscreen(px: px) { c in renderFlat(c, alienParts(Shape()).0, flatPalette, line: 2.8) }
    // White die-cut border: stamp the silhouette in a ring around itself.
    let border = offscreen(px: px) { c in
        let r: CGFloat = 5
        for i in 0..<28 {
            let a = CGFloat(i) / 28 * 2 * .pi
            c.saveGState()
            c.clip(to: CGRect(x: cos(a) * r, y: sin(a) * r, width: 144, height: 144), mask: art)
            c.setFillColor(rgb(0xFFFFFF)); c.fill(CGRect(x: -10, y: -10, width: 164, height: 164))
            c.restoreGState()
        }
    }
    c.saveGState()
    c.setShadow(offset: CGSize(width: 0, height: -rect.width * 0.02), blur: rect.width * 0.04, color: rgb(0x000000, 0.35))
    c.draw(border, in: rect)
    c.restoreGState()
    c.draw(art, in: rect)
}

let kawaiiShape = Shape(head: CGSize(width: 90, height: 74), torso: CGSize(width: 28, height: 22),
                        legs: CGSize(width: 11, height: 15), legGap: 6, handX: 21, handY: 7, handR: 5, armW: 7,
                        eye: CGSize(width: 27, height: 25), eyeX: 20, eyeAngle: 0.22, eyeYFrac: 0.47,
                        antRootX: 12, antTipX: 22, antRise: 12, tipR: 6.5, stalkW: 3.2,
                        mouth: .zero, mouthYFrac: 0.2, hlR: 5, seam: false, sheen: true)

func sparkle(_ c: CGContext, at p: CGPoint, r: CGFloat, color: CGColor) {
    let s = CGMutablePath()
    s.move(to: CGPoint(x: p.x, y: p.y + r))
    s.addQuadCurve(to: CGPoint(x: p.x + r, y: p.y), control: p)
    s.addQuadCurve(to: CGPoint(x: p.x, y: p.y - r), control: p)
    s.addQuadCurve(to: CGPoint(x: p.x - r, y: p.y), control: p)
    s.addQuadCurve(to: CGPoint(x: p.x, y: p.y + r), control: p)
    c.setFillColor(color); c.addPath(s); c.fillPath()
}

let kawaiiStyle: Style = { c, rect in
    unitSpace(c, rect) { c in
        groundShadow(c, width: 40, alpha: 0.12)
        let (parts, l) = alienParts(kawaiiShape)
        let pal = Palette(body: rgb(0x8FE3AF), shade: rgb(0x77D19A), eye: rgb(0x2B2440), eyeDot: rgb(0xFFFFFF),
                          dot: rgb(0xFFFFFF), navy: rgb(0x6C7BD9), ink: rgb(0x3F8D6B))
        renderFlat(c, parts.filter { $0.tag != "mouth" }, pal, line: 2.2)
        // blush, cat mouth, sparkles in the eyes and around the head
        c.setFillColor(rgb(0xFF9EBB, 0.55))
        for side: CGFloat in [-1, 1] { c.fillEllipse(in: CGRect(x: 72 + side * 31 - 6, y: l.eyeY - 17, width: 12, height: 6.5)) }
        let my = l.head.minY + l.head.height * 0.22
        let mouth = CGMutablePath()
        mouth.move(to: CGPoint(x: 66, y: my + 2))
        mouth.addQuadCurve(to: CGPoint(x: 72, y: my + 1), control: CGPoint(x: 68.5, y: my - 3))
        mouth.addQuadCurve(to: CGPoint(x: 78, y: my + 2), control: CGPoint(x: 75.5, y: my - 3))
        c.setStrokeColor(rgb(0x2B2440)); c.setLineWidth(1.8); c.setLineCap(.round); c.addPath(mouth); c.strokePath()
        for side: CGFloat in [-1, 1] {
            sparkle(c, at: CGPoint(x: 72 + side * 20 - side * 6, y: l.eyeY - 5), r: 2.6, color: rgb(0xFFFFFF))
        }
        sparkle(c, at: CGPoint(x: 26, y: l.head.maxY - 2), r: 6, color: rgb(0xFFD66B))
        sparkle(c, at: CGPoint(x: 121, y: l.head.maxY - 18), r: 4.5, color: rgb(0xFFB3CF))
        sparkle(c, at: CGPoint(x: 116, y: 30), r: 3.5, color: rgb(0xB9C4FF))
    }
}

// Hand-placed 24x24 sprite: 3 screen pixels per sprite pixel at pet size on a 1x screen.
let pixelGrid = [
    "....KKK..........KKK....",
    "...KGWGK........KGNGK...",
    "....KKK..........KKK....",
    ".......K........K.......",
    "........K......K........",
    "........KKKKKKKK........",
    "......KKGGGGGGGGKK......",
    ".....KGGLLGGGGGGGGK.....",
    "....KGEEEGGGGGGEEEGK....",
    "....KEWEEEGGGGEEEWEK....",
    "....KGEEEEEGGEEEEEGK....",
    "....KGGGEEEGGEEEGGGK....",
    ".....KGGGGGEEGGGGGK.....",
    "......KKGGGGGGGGKK......",
    "......KGKGGGGGGKGK......",
    ".....KGKGGGGGGGGKGK.....",
    "....KGKKGGGGGGGGKKGK....",
    "...KGGK.KGGGGGGK.KGGK...",
    "...KWNK..KGGGGK..KNWK...",
    "....KK..KDDKKDDK..KK....",
    "........KDDKKDDK........",
    "........KDDKKDDK........",
    "........KDDKKDDK........",
    "........KKKKKKKK........",
]
let pixelColors: [Character: CGColor] = [
    "K": rgb(0x0E2E1A), "G": rgb(0x3CC05C), "D": rgb(0x2A9645), "L": rgb(0x8EF0A2),
    "E": rgb(0x0E0E14), "W": rgb(0xFFFFFF), "N": rgb(0x2A3A8F),
]

let pixelStyle: Style = { c, rect in
    unitSpace(c, rect) { c in
        c.setShouldAntialias(false)
        let cell: CGFloat = 6
        for (r, row) in pixelGrid.enumerated() {
            for (col, ch) in row.enumerated() {
                guard let color = pixelColors[ch] else { continue }
                c.setFillColor(color)
                c.fill(CGRect(x: CGFloat(col) * cell, y: 144 - CGFloat(r + 1) * cell, width: cell, height: cell))
            }
        }
    }
}

func noodle(_ c: CGContext, _ a: CGPoint, _ ctrl: CGPoint, _ b: CGPoint, w: CGFloat, fill: CGColor, ink: CGColor) {
    let p = CGMutablePath()
    p.move(to: a); p.addQuadCurve(to: b, control: ctrl)
    c.setLineCap(.round)
    c.setStrokeColor(ink); c.setLineWidth(w + 3.4); c.addPath(p); c.strokePath()
    c.setStrokeColor(fill); c.setLineWidth(w); c.addPath(p); c.strokePath()
}

func glove(_ c: CGContext, at p: CGPoint, r: CGFloat, ink: CGColor) {
    c.setFillColor(rgb(0xFFFFFF)); c.setStrokeColor(ink); c.setLineWidth(2.2)
    c.addEllipse(in: circle(p, r)); c.drawPath(using: .fillStroke)
    for dx: CGFloat in [-2.6, 0, 2.6] {
        strokeOpen(c, [CGPoint(x: p.x + dx, y: p.y + r * 0.8), CGPoint(x: p.x + dx, y: p.y + r * 0.15)], width: 1.4, color: ink)
    }
}

let rubberHoseStyle: Style = { c, rect in
    unitSpace(c, rect) { c in
        let ink = rgb(0x121212), green = rgb(0x67B36A), light = rgb(0xA9DDA6)
        groundShadow(c, width: 54, alpha: 0.18)
        c.setLineJoin(.round)
        // legs and big shoes
        for side: CGFloat in [-1, 1] {
            noodle(c, CGPoint(x: 72 + side * 6, y: 42), CGPoint(x: 72 + side * 17, y: 30), CGPoint(x: 72 + side * 11, y: 18),
                   w: 5.5, fill: green, ink: ink)
            let shoe = CGRect(x: 72 + side * 15 - 10, y: 9, width: 20, height: 11)
            c.setFillColor(ink); c.fillEllipse(in: shoe)
            c.setFillColor(rgb(0xFFFFFF, 0.85)); c.fillEllipse(in: CGRect(x: shoe.minX + 4, y: shoe.maxY - 5, width: 6, height: 2.6))
        }
        // arms: one on the hip, one waving
        noodle(c, CGPoint(x: 61, y: 57), CGPoint(x: 42, y: 62), CGPoint(x: 40, y: 44), w: 5, fill: green, ink: ink)
        noodle(c, CGPoint(x: 83, y: 57), CGPoint(x: 104, y: 52), CGPoint(x: 106, y: 72), w: 5, fill: green, ink: ink)
        glove(c, at: CGPoint(x: 40, y: 42), r: 7, ink: ink)
        glove(c, at: CGPoint(x: 106, y: 75), r: 7, ink: ink)
        // pear torso with a light belly
        c.setFillColor(green); c.setStrokeColor(ink); c.setLineWidth(2.8)
        c.addEllipse(in: CGRect(x: 57, y: 37, width: 30, height: 28)); c.drawPath(using: .fillStroke)
        c.setFillColor(light); c.fillEllipse(in: CGRect(x: 64, y: 40, width: 16, height: 15))
        // springy antennae
        for (side, dot) in [(CGFloat(-1), rgb(0xFFFFFF)), (1, rgb(0x22357A))] {
            let a = CGPoint(x: 72 + side * 9, y: 110), b = CGPoint(x: 72 + side * 22, y: 131)
            let len = hypot(b.x - a.x, b.y - a.y), nx = -(b.y - a.y) / len, ny = (b.x - a.x) / len
            let pts = (0...60).map { i -> CGPoint in
                let t = CGFloat(i) / 60, w = sin(t * .pi * 6) * 2.6
                return CGPoint(x: a.x + (b.x - a.x) * t + nx * w, y: a.y + (b.y - a.y) * t + ny * w)
            }
            strokeOpen(c, pts, width: 2.2, color: ink)
            c.setFillColor(green); c.setStrokeColor(ink); c.setLineWidth(2.4)
            c.addEllipse(in: circle(b, 6)); c.drawPath(using: .fillStroke)
            c.setFillColor(dot); c.fillEllipse(in: circle(b, 2.6))
        }
        // head
        c.setFillColor(green); c.setStrokeColor(ink); c.setLineWidth(3)
        c.addEllipse(in: circle(CGPoint(x: 72, y: 86), 30)); c.drawPath(using: .fillStroke)
        // pie-cut eyes
        for side: CGFloat in [-1, 1] {
            let e = CGPoint(x: 72 + side * 9.5, y: 93)
            c.saveGState()
            c.translateBy(x: e.x, y: e.y); c.rotate(by: side * 0.12)
            c.setFillColor(rgb(0xFFFFFF)); c.setStrokeColor(ink); c.setLineWidth(2.2)
            c.addEllipse(in: CGRect(x: -8, y: -11, width: 16, height: 22)); c.drawPath(using: .fillStroke)
            let pupil = CGMutablePath()
            pupil.move(to: CGPoint(x: side * 1.5, y: -2))
            pupil.addArc(center: CGPoint(x: side * 1.5, y: -2), radius: 5.2, startAngle: 1.25, endAngle: 1.25 + 2 * .pi - 0.75, clockwise: false)
            pupil.closeSubpath()
            c.setFillColor(ink); c.addPath(pupil); c.fillPath()
            c.restoreGState()
        }
        // big grin with a tongue
        let grin = CGMutablePath()
        grin.move(to: CGPoint(x: 57, y: 76))
        grin.addQuadCurve(to: CGPoint(x: 87, y: 76), control: CGPoint(x: 72, y: 58))
        grin.addQuadCurve(to: CGPoint(x: 57, y: 76), control: CGPoint(x: 72, y: 71))
        c.setFillColor(ink); c.addPath(grin); c.fillPath()
        c.saveGState(); c.addPath(grin); c.clip()
        c.setFillColor(rgb(0xE5546B)); c.fillEllipse(in: CGRect(x: 65, y: 63, width: 14, height: 8))
        c.restoreGState()
        for side: CGFloat in [-1, 1] {
            strokeOpen(c, [CGPoint(x: 72 + side * 16.5, y: 78), CGPoint(x: 72 + side * 14, y: 75.5)], width: 1.8, color: ink)
        }
    }
}

func jitter(_ pts: [CGPoint], amp: CGFloat, rng: inout RNG) -> [CGPoint] {
    let ph1 = rng.r(0, 6.28), ph2 = rng.r(0, 6.28)
    return pts.enumerated().map { i, p in
        let t = CGFloat(i)
        return CGPoint(x: p.x + amp * (sin(t * 0.31 + ph1) * 0.7 + rng.r(-0.3, 0.3)),
                       y: p.y + amp * (sin(t * 0.27 + ph2) * 0.7 + rng.r(-0.3, 0.3)))
    }
}

let doodleStyle: Style = { c, rect in
    unitSpace(c, rect) { c in
        var rng = RNG(s: 42)
        let graphite = rgb(0x2A2A2E)
        let pal = Palette(body: rgb(0x58C477), shade: rgb(0x46AE65), eye: rgb(0x232326), eyeDot: rgb(0xFFFFFF),
                          dot: rgb(0xF4F4F4), navy: rgb(0x34489E), ink: graphite)
        // pencil scribble shadow
        for i in 0..<9 {
            let y = 9 + CGFloat(i) * 0.7
            strokeOpen(c, [CGPoint(x: 52 + rng.r(-2, 2), y: y), CGPoint(x: 92 + rng.r(-2, 2), y: y + rng.r(-0.6, 0.6))],
                       width: 0.6, color: graphite.copy(alpha: 0.3)!)
        }
        for p in alienParts(Shape(sheen: false)).0 {
            if p.role == .seam {
                strokeOpen(c, jitter(p.pts + [CGPoint(x: 72, y: (p.pts[0].y + p.pts[1].y) / 2)].sorted { $0.y > $1.y },
                                     amp: 0.5, rng: &rng), width: 0.9, color: graphite.copy(alpha: 0.45)!)
                continue
            }
            guard p.closed, p.role != .sheen else { continue }
            // marker fill, a little off-register
            let fill = jitter(p.pts, amp: 0.5, rng: &rng).map { CGPoint(x: $0.x + 1.1, y: $0.y - 1.1) }
            c.setFillColor(pal.color(p.role).copy(alpha: p.role == .eyeDot ? 1 : 0.93)!)
            c.addPath(path(fill)); c.fillPath()
            // hatching on the shadow side of the bigger shapes
            let b = bbox(p.pts)
            if (p.role == .body || p.role == .shade), b.width > 10 {
                c.saveGState()
                c.addPath(path(p.pts)); c.clip()
                let shifted = p.pts.map { CGPoint(x: $0.x - b.width * 0.18, y: $0.y + b.height * 0.18) }
                c.addRect(b.insetBy(dx: -20, dy: -20)); c.addPath(path(shifted)); c.clip(using: .evenOdd)
                var x = b.minX - b.height
                while x < b.maxX {
                    strokeOpen(c, [CGPoint(x: x + rng.r(-0.4, 0.4), y: b.minY), CGPoint(x: x + b.height + rng.r(-0.4, 0.4), y: b.maxY)],
                               width: 0.55, color: graphite.copy(alpha: 0.4)!)
                    x += 2.6
                }
                c.restoreGState()
            }
            // two loose pencil passes, overshooting the start
            if p.role == .body || p.role == .shade || p.role == .eye {
                for pass in 0..<2 {
                    let loop = p.pts + p.pts.prefix(5)
                    strokeOpen(c, jitter(loop, amp: 0.65, rng: &rng), width: pass == 0 ? 1.25 : 0.8,
                               color: graphite.copy(alpha: pass == 0 ? 0.9 : 0.45)!)
                }
            }
        }
    }
}

func inset(_ pts: [CGPoint], by d: CGFloat) -> [CGPoint] {
    let cx = pts.map(\.x).reduce(0, +) / CGFloat(pts.count), cy = pts.map(\.y).reduce(0, +) / CGFloat(pts.count)
    return pts.map { p in
        let vx = p.x - cx, vy = p.y - cy, len = max(hypot(vx, vy), 0.001)
        let k = max(0, (len - d) / len)
        return CGPoint(x: cx + vx * k, y: cy + vy * k)
    }
}

let feltStyle: Style = { c, rect in
    unitSpace(c, rect) { c in
        var rng = RNG(s: 9)
        let pal = Palette(body: rgb(0x52B266), shade: rgb(0x43995A), eye: rgb(0x1C1C1F), eyeDot: rgb(0xF3F3F3),
                          dot: rgb(0xF6F6F6), navy: rgb(0x26408F), ink: rgb(0x1C1C1F))
        groundShadow(c, width: 46, alpha: 0.12)
        for p in alienParts(Shape(sheen: false)).0 {
            if p.role == .seam {
                c.saveGState()
                c.setLineDash(phase: 0, lengths: [1.8, 1.5])
                strokeOpen(c, p.pts, width: 0.8, color: rgb(0xD6F5DD, 0.9))
                c.restoreGState()
                continue
            }
            guard p.closed, p.role != .sheen else { continue }
            let cp = path(p.pts)
            c.saveGState()
            c.setShadow(offset: CGSize(width: 0.6, height: -1.1), blur: 1.8, color: rgb(0x000000, 0.38))
            c.setFillColor(pal.color(p.role)); c.addPath(cp); c.fillPath()
            c.restoreGState()
            // felt fibres
            let b = bbox(p.pts)
            c.saveGState(); c.addPath(cp); c.clip()
            for _ in 0..<Int(b.width * b.height * 0.9) {
                let pt = CGPoint(x: rng.r(b.minX, b.maxX), y: rng.r(b.minY, b.maxY))
                c.setFillColor(rng.next() < 0.5 ? rgb(0xFFFFFF, 0.09) : rgb(0x000000, 0.08))
                c.fillEllipse(in: CGRect(x: pt.x, y: pt.y, width: rng.r(0.4, 1.1), height: rng.r(0.4, 1.1)))
            }
            c.restoreGState()
            // running stitch around the bigger pieces
            if b.width > 8 && b.height > 8 {
                let thread = p.role == .eye ? rgb(0xFFFFFF, 0.75) : rgb(0xD6F5DD, 0.95)
                c.saveGState()
                c.setLineDash(phase: 0, lengths: [1.8, 1.4])
                c.setStrokeColor(thread); c.setLineWidth(0.75)
                c.addPath(path(inset(p.pts, by: 2.2))); c.strokePath()
                c.restoreGState()
            }
        }
    }
}

func satin(_ c: CGContext, _ p: Part, angle: CGFloat, spacing: CGFloat, color: CGColor, width: CGFloat) {
    let b = bbox(p.pts)
    c.saveGState()
    c.addPath(path(p.pts)); c.clip()
    let cx = b.midX, cy = b.midY, r = max(b.width, b.height)
    let dir = angle + .pi / 2, ux = cos(dir), uy = sin(dir), nx = cos(angle), ny = sin(angle)
    var t = -r
    while t < r {
        let ox = cx + nx * t, oy = cy + ny * t
        strokeOpen(c, [CGPoint(x: ox - ux * r, y: oy - uy * r), CGPoint(x: ox + ux * r, y: oy + uy * r)], width: width, color: color)
        t += spacing
    }
    c.restoreGState()
}

let realisticStyle: Style = { c, rect in
    unitSpace(c, rect) { c in
        var rng = RNG(s: 3)
        let light = rgb(0x7CDB90), mid = rgb(0x35A651), dark = rgb(0x17602C)
        let fabric = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB)!, colors: [light, mid, dark] as CFArray,
                                locations: [0, 0.55, 1])!
        // soft contact shadow
        c.saveGState()
        c.setShadow(offset: .zero, blur: 7, color: rgb(0x000000, 0.55))
        c.setFillColor(rgb(0x000000, 0.28)); c.fillEllipse(in: CGRect(x: 50, y: 9, width: 44, height: 5))
        c.restoreGState()
        for p in alienParts(Shape(sheen: false)).0 {
            let cp = path(p.pts, closed: p.closed)
            let b = p.closed ? bbox(p.pts) : .zero
            switch p.role {
            case .body, .shade:
                c.saveGState()
                c.setShadow(offset: CGSize(width: 0.4, height: -1.8), blur: 4.5, color: rgb(0x000000, 0.35))
                c.setFillColor(mid); c.addPath(cp); c.fillPath()
                c.restoreGState()
                c.saveGState(); c.addPath(cp); c.clip()
                let r = max(b.width, b.height)
                c.drawRadialGradient(fabric, startCenter: CGPoint(x: b.minX + b.width * 0.36, y: b.minY + b.height * 0.7), startRadius: 0,
                                     endCenter: CGPoint(x: b.midX, y: b.midY), endRadius: r * 0.78,
                                     options: [.drawsAfterEndLocation])
                // short plush fibres
                for _ in 0..<Int(b.width * b.height * 1.1) {
                    let pt = CGPoint(x: rng.r(b.minX, b.maxX), y: rng.r(b.minY, b.maxY))
                    let a = -CGFloat.pi / 2 + rng.r(-0.9, 0.9), len = rng.r(0.7, 1.9)
                    strokeOpen(c, [pt, CGPoint(x: pt.x + cos(a) * len, y: pt.y + sin(a) * len)], width: 0.35,
                               color: rng.next() < 0.5 ? rgb(0xFFFFFF, 0.06) : rgb(0x000000, 0.055))
                }
                // darker rim where the fabric turns away, and a velvet sheen on the lit edge
                c.setStrokeColor(rgb(0x0B3A1A, 0.3)); c.setLineWidth(2.4); c.addPath(cp); c.strokePath()
                c.saveGState()
                c.translateBy(x: 1.2, y: -1.2)
                c.setStrokeColor(rgb(0xC9F5D3, 0.22)); c.setLineWidth(1.6); c.addPath(cp); c.strokePath()
                c.restoreGState()
                if p.tag == "head" || p.tag == "torso" {
                    let glow = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB)!,
                                          colors: [rgb(0xFFFFFF, 0.22), rgb(0xFFFFFF, 0)] as CFArray, locations: [0, 1])!
                    let gc = CGPoint(x: b.minX + b.width * 0.34, y: b.minY + b.height * 0.74)
                    c.drawRadialGradient(glow, startCenter: gc, startRadius: 0, endCenter: gc, endRadius: b.width * 0.3, options: [])
                }
                c.restoreGState()
                // fuzzy silhouette
                for (i, pt) in p.pts.enumerated() where i % 2 == 0 {
                    let vx = pt.x - b.midX, vy = pt.y - b.midY, len = max(hypot(vx, vy), 0.01)
                    strokeOpen(c, [pt, CGPoint(x: pt.x + vx / len * 0.9 + rng.r(-0.3, 0.3), y: pt.y + vy / len * 0.9)],
                               width: 0.45, color: rgb(0x2C8A45, 0.6))
                }
            case .eye:
                c.saveGState()
                c.setShadow(offset: CGSize(width: 0, height: -0.4), blur: 0.8, color: rgb(0x000000, 0.5))
                c.setFillColor(rgb(0x141414)); c.addPath(cp); c.fillPath()
                c.restoreGState()
                satin(c, p, angle: p.angle, spacing: 0.55, color: rgb(0x3A3A3E, 0.55), width: 0.3)
                c.saveGState(); c.addPath(cp); c.clip()
                let sheen = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB)!,
                                       colors: [rgb(0xFFFFFF, 0.16), rgb(0xFFFFFF, 0)] as CFArray, locations: [0, 1])!
                c.drawLinearGradient(sheen, start: CGPoint(x: b.midX, y: b.maxY), end: CGPoint(x: b.midX, y: b.midY), options: [])
                c.restoreGState()
            case .eyeDot, .dot, .navy:
                let base = p.role == .navy ? rgb(0x1F2A5C) : rgb(0xDADCE0)
                c.setFillColor(base); c.addPath(cp); c.fillPath()
                satin(c, p, angle: p.angle + 0.3, spacing: 0.45, color: rgb(0xFFFFFF, p.role == .navy ? 0.18 : 0.5), width: 0.25)
            case .seam:
                c.saveGState()
                c.setShadow(offset: .zero, blur: 1.4, color: rgb(0x000000, 0.5))
                strokeOpen(c, p.pts, width: 1.1, color: rgb(0x0B3A1A, 0.35))
                c.restoreGState()
                strokeOpen(c, p.pts.map { CGPoint(x: $0.x + 0.9, y: $0.y) }, width: 0.6, color: rgb(0xFFFFFF, 0.12))
            case .sheen:
                break
            }
        }
    }
}

// MARK: - Sheet

func text(_ c: CGContext, _ s: String, at p: CGPoint, size: CGFloat, bold: Bool = false, color: CGColor) {
    let font = CTFontCreateWithName((bold ? "HelveticaNeue-Bold" : "HelveticaNeue") as CFString, size, nil)
    let attrs: [NSAttributedString.Key: Any] = [NSAttributedString.Key(kCTFontAttributeName as String): font,
                                                NSAttributedString.Key(kCTForegroundColorAttributeName as String): color]
    let line = CTLineCreateWithAttributedString(NSAttributedString(string: s, attributes: attrs))
    c.textPosition = p
    CTLineDraw(line, c)
}

let styles: [(String, String, Style)] = [
    ("Current", "flat vector, what you have now", currentStyle),
    ("Sticker", "die-cut with a white border", stickerStyle),
    ("Kawaii", "chibi, pastel, sparkly", kawaiiStyle),
    ("Pixel art", "24×24 hand-placed sprite", pixelStyle),
    ("Rubber hose", "1930s cartoon", rubberHoseStyle),
    ("Doodle", "pencil and marker", doodleStyle),
    ("Felt", "cut-out craft pieces", feltStyle),
    ("Realistic", "plush with fur and embroidery", realisticStyle),
]

let cols = 4, tileW: CGFloat = 330, tileH: CGFloat = 400, gap: CGFloat = 18, top: CGFloat = 70
let W = Int(CGFloat(cols) * tileW + CGFloat(cols + 1) * gap)
let rows = (styles.count + cols - 1) / cols
let H = Int(top + CGFloat(rows) * tileH + CGFloat(rows + 1) * gap)
let c = CGContext(data: nil, width: W, height: H, bitsPerComponent: 8, bytesPerRow: 0,
                  space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
c.setFillColor(rgb(0xF4F2EE)); c.fill(CGRect(x: 0, y: 0, width: W, height: H))
text(c, "Aftonsparv pet: style mockups", at: CGPoint(x: gap + 4, y: CGFloat(H) - 46), size: 26, bold: true, color: rgb(0x222222))
text(c, "Big render on top, actual pet size bottom right", at: CGPoint(x: gap + 4, y: CGFloat(H) - 68), size: 14,
     color: rgb(0x777777))

let desk = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB)!, colors: [rgb(0xDCE6F2), rgb(0xB9C9DD)] as CFArray,
                      locations: [0, 1])!
for (i, s) in styles.enumerated() {
    let col = i % cols, row = i / cols
    let x = gap + CGFloat(col) * (tileW + gap)
    let y = CGFloat(H) - top - gap - CGFloat(row + 1) * tileH - CGFloat(row) * gap
    let tile = CGRect(x: x, y: y, width: tileW, height: tileH)
    c.saveGState()
    c.addPath(CGPath(roundedRect: tile, cornerWidth: 16, cornerHeight: 16, transform: nil)); c.clip()
    c.setFillColor(rgb(0xFFFFFF)); c.fill(tile)
    let stage = CGRect(x: x, y: y + 72, width: tileW, height: tileH - 72)
    c.drawLinearGradient(desk, start: CGPoint(x: stage.midX, y: stage.maxY), end: CGPoint(x: stage.midX, y: stage.minY), options: [])
    s.2(c, CGRect(x: stage.midX - 144, y: stage.minY + 12, width: 288, height: 288))
    s.2(c, CGRect(x: stage.maxX - 82, y: stage.minY + 6, width: 72, height: 72))
    c.restoreGState()
    text(c, s.0, at: CGPoint(x: x + 16, y: y + 42), size: 20, bold: true, color: rgb(0x222222))
    text(c, s.1, at: CGPoint(x: x + 16, y: y + 20), size: 14, color: rgb(0x6B6B6B))
}

let out = URL(fileURLWithPath: CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "styles.png")
let dest = CGImageDestinationCreateWithURL(out as CFURL, UTType.png.identifier as CFString, 1, nil)!
CGImageDestinationAddImage(dest, c.makeImage()!, nil)
CGImageDestinationFinalize(dest)
print("wrote \(out.path) \(W)x\(H)")
