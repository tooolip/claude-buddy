// Renders the "Plush alien" skin: an original fleece plush toy, ray-marched from signed distance
// fields with soft shadows, ambient occlusion, fabric sheen, fuzzy silhouettes and glossy eyes.
// Usage: make plush
//   (swiftc -O Tools/render-plush.swift -o build/render-plush && build/render-plush Skins/plush-alien [hero.png])
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers
import simd

typealias V3 = SIMD3<Float>

@inline(__always) func clamp01(_ x: Float) -> Float { min(max(x, 0), 1) }
@inline(__always) func mixf(_ a: Float, _ b: Float, _ t: Float) -> Float { a + (b - a) * t }
@inline(__always) func mix3(_ a: V3, _ b: V3, _ t: Float) -> V3 { a + (b - a) * t }
@inline(__always) func smooth(_ a: Float, _ b: Float, _ x: Float) -> Float {
    let t = clamp01((x - a) / (b - a)); return t * t * (3 - 2 * t)
}
@inline(__always) func norm(_ v: V3) -> V3 { simd_normalize(v) }
@inline(__always) func dot(_ a: V3, _ b: V3) -> Float { simd_dot(a, b) }

func linear(_ hex: UInt32) -> V3 {
    func c(_ v: UInt32) -> Float {
        let s = Float(v) / 255
        return s <= 0.04045 ? s / 12.92 : pow((s + 0.055) / 1.055, 2.4)
    }
    return V3(c((hex >> 16) & 0xFF), c((hex >> 8) & 0xFF), c(hex & 0xFF))
}

// MARK: - Noise

@inline(__always) func hash(_ x: Int32, _ y: Int32, _ z: Int32) -> Float {
    var h = UInt32(bitPattern: x &* 73856093) ^ UInt32(bitPattern: y &* 19349663) ^ UInt32(bitPattern: z &* 83492791)
    h = (h ^ (h >> 16)) &* 0x7feb352d
    h = (h ^ (h >> 15)) &* 0x846ca68b
    h ^= h >> 16
    return Float(h & 0xFFFFFF) * (1 / 16777215)
}

func noise(_ p: V3) -> Float {
    let fl = floor(p), f = p - fl
    let u = f * f * (3 - 2 * f)
    let x = Int32(fl.x), y = Int32(fl.y), z = Int32(fl.z)
    let k0 = mixf(mixf(hash(x, y, z), hash(x + 1, y, z), u.x), mixf(hash(x, y + 1, z), hash(x + 1, y + 1, z), u.x), u.y)
    let k1 = mixf(mixf(hash(x, y, z + 1), hash(x + 1, y, z + 1), u.x),
                  mixf(hash(x, y + 1, z + 1), hash(x + 1, y + 1, z + 1), u.x), u.y)
    return mixf(k0, k1, u.z)
}

func fbm(_ p: V3, _ octaves: Int) -> Float {
    var s: Float = 0, a: Float = 0.5, total: Float = 0, q = p
    for _ in 0..<octaves {
        s += a * noise(q); total += a
        q = q * 2.03 + V3(1.7, 9.2, 3.1); a *= 0.5
    }
    return s / total
}

/// Random direction-ish vector in [-0.5, 0.5]^3, for bumping normals.
@inline(__always) func noiseVec(_ p: V3) -> V3 {
    V3(noise(p) - 0.5, noise(p + V3(31.7, 7.3, 11.1)) - 0.5, noise(p + V3(5.9, 63.1, 27.4)) - 0.5)
}

// MARK: - Distance functions

@inline(__always) func sdEllipsoid(_ p: V3, _ r: V3) -> Float {
    let k0 = simd_length(p / r), k1 = simd_length(p / (r * r))
    return k0 * (k0 - 1) / k1
}

@inline(__always) func sdCapsule(_ p: V3, _ a: V3, _ b: V3, _ r: Float) -> Float {
    let pa = p - a, ba = b - a
    let h = clamp01(dot(pa, ba) / dot(ba, ba))
    return simd_length(pa - ba * h) - r
}

@inline(__always) func smin(_ a: Float, _ b: Float, _ k: Float) -> Float {
    let h = max(k - abs(a - b), 0) / k
    return min(a, b) - h * h * k * 0.25
}

// MARK: - Character

/// One animation frame's pose. Units are centimetres; the plush sits on the floor at y = 0.
struct Pose {
    var dy: Float = 0          // hop
    var breathe: Float = 0     // squash, + flattens the body
    var tilt: Float = 0        // head tilt, radians
    var sway: Float = 0        // antenna lean
    var lid: Float = 0         // 0 open, 1 shut
    var mouth: Float = 0       // 0 stitched smile, 1 wide open
    var lift: Float = 0        // held up off the floor
    var swing: Float = 0       // dangling legs while held
}

let green = linear(0x5B984D)
let cream = linear(0xDCCFB0)
let pomColor = linear(0xF3CD62)
let blush = linear(0xE7909E)
let thread = linear(0x3A2420)
let mouthInside = linear(0x4A1C22)
let tongue = linear(0xD66E7E)

enum Material { case fleece, eye, lid, pom, tag }

@inline(__always) func sdBox(_ p: V3, _ b: V3, _ r: Float) -> Float {
    let q = abs(p) - b
    return simd_length(simd_max(q, V3(repeating: 0))) + min(max(q.x, max(q.y, q.z)), 0) - r
}

struct Scene {
    let base: V3
    let body: V3, bodyR: V3
    let head: V3, headR: V3
    let pivot: V3, tilt: Float, cosT: Float, sinT: Float
    let hip: (V3, V3), foot: (V3, V3), shoulder: (V3, V3), hand: (V3, V3)
    let stalkA: (V3, V3), stalkB: (V3, V3), pom: (V3, V3), eye: (V3, V3)
    let lidCut: Float, mouth: Float, sitting: Bool
    let tag: V3
    let eyeR: Float = 1.5, pomR: Float = 1.15, legR: Float = 1.5, armR: Float = 1.15, stalkR: Float = 0.36
    let bound: (c: V3, r: Float)

    init(_ p: Pose) {
        base = V3(0, p.lift + p.dy, 0)
        sitting = p.lift == 0
        bodyR = V3(4.6 * (1 + p.breathe * 0.5), 5.0 * (1 - p.breathe), 4.2 * (1 + p.breathe * 0.5))
        body = base + V3(0, bodyR.y, 0)
        tilt = p.tilt; cosT = cos(p.tilt); sinT = sin(p.tilt)
        let pivot = base + V3(0, bodyR.y * 1.62, 0)
        self.pivot = pivot
        let c = cosT, s = sinT
        func rot(_ v: V3) -> V3 {
            let q = v - pivot
            return pivot + V3(q.x * c - q.y * s, q.x * s + q.y * c, q.z)
        }
        let headC = base + V3(0, bodyR.y * 2 + 2.3, 0.3)
        head = rot(headC)
        headR = V3(6.2, 5.3, 5.4)
        eye = (rot(headC + V3(-2.25, 0.4, 4.55)), rot(headC + V3(2.25, 0.4, 4.55)))
        stalkA = (rot(headC + V3(-1.7, 4.6, -0.3)), rot(headC + V3(-2.8 + p.sway, 7.1, -0.1)))
        stalkB = (rot(headC + V3(1.7, 4.6, -0.3)), rot(headC + V3(2.8 + p.sway, 7.1, -0.1)))
        pom = (rot(headC + V3(-3.05 + p.sway * 1.3, 7.85, -0.05)), rot(headC + V3(3.05 + p.sway * 1.3, 7.85, -0.05)))
        hip = (base + V3(-2.3, 1.5, 1.2), base + V3(2.3, 1.5, 1.2))
        if sitting {
            foot = (base + V3(-2.9, 1.45, 4.9), base + V3(2.9, 1.45, 4.9))
        } else {
            foot = (hip.0 + V3(-1.0 + p.swing * 0.3, -1.5 + p.swing * 0.35, 3.3 + p.swing * 0.7),
                    hip.1 + V3(1.0 + p.swing * 0.3, -1.5 - p.swing * 0.35, 3.3 - p.swing * 0.7))
        }
        shoulder = (base + V3(-3.9, bodyR.y * 1.52, 0.8), base + V3(3.9, bodyR.y * 1.52, 0.8))
        if sitting {
            hand = (base + V3(-5.3, 4.6, 2.6), base + V3(5.3, 4.6, 2.6))
        } else {
            hand = (shoulder.0 + V3(-2.2, 2.4, 1.0), shoulder.1 + V3(2.2, 2.4, 1.0))
        }
        tag = base + V3(4.25, 1.55, 1.1)
        lidCut = mixf(eyeR + 0.2, -eyeR - 0.2, p.lid)
        mouth = p.mouth
        bound = (base + V3(0, 10.5, 0.5), 15)
    }

    /// Head-local coordinates (undoing the tilt).
    @inline(__always) func headLocal(_ p: V3) -> V3 {
        let q = p - head
        return V3(q.x * cosT + q.y * sinT, -q.x * sinT + q.y * cosT, q.z)
    }

    @inline(__always) func eyeLocal(_ p: V3, _ e: V3) -> V3 {
        let q = p - e
        return V3(q.x * cosT + q.y * sinT, -q.x * sinT + q.y * cosT, q.z)
    }

    @inline(__always) func fleece(_ p: V3) -> Float {
        var d = sdEllipsoid(p - body, bodyR)
        if sitting { d = max(d, base.y + 0.05 - p.y) }
        d = smin(d, sdEllipsoid(headLocal(p), headR), 1.6)
        d = smin(d, sdCapsule(p, hip.0, foot.0, legR), 0.8)
        d = smin(d, sdCapsule(p, hip.1, foot.1, legR), 0.8)
        d = smin(d, sdCapsule(p, shoulder.0, hand.0, armR), 0.7)
        d = smin(d, sdCapsule(p, shoulder.1, hand.1, armR), 0.7)
        d = smin(d, sdCapsule(p, stalkA.0, stalkA.1, stalkR), 0.5)
        d = smin(d, sdCapsule(p, stalkB.0, stalkB.1, stalkR), 0.5)
        // sewn seams pull the fabric in around the eyes and over the head (the belly seam is shading only:
        // a groove there made the marcher overshoot)
        for e in [eye.0, eye.1] {
            d += 0.09 * (1 - smooth(0, 0.3, abs(simd_length(p - e) - eyeR - 0.05)))
        }
        let hq = headLocal(p)
        d += 0.035 * (1 - smooth(0, 0.1, abs(hq.x))) * max(smooth(2.6, 3.4, hq.y), smooth(0.3, -0.5, hq.z))
        return d
    }

    @inline(__always) func lidDist(_ p: V3, _ e: V3) -> Float {
        let q = eyeLocal(p, e)
        return max(simd_length(q) - (eyeR + 0.1), lidCut - q.y)
    }

    @inline(__always) func sdf(_ p: V3) -> Float {
        var d = fleece(p)
        d = min(d, simd_length(p - eye.0) - eyeR)
        d = min(d, simd_length(p - eye.1) - eyeR)
        if lidCut < eyeR + 0.1 { d = min(d, min(lidDist(p, eye.0), lidDist(p, eye.1))) }
        d = min(d, simd_length(p - pom.0) - pomR)
        d = min(d, simd_length(p - pom.1) - pomR)
        d = min(d, tagDist(p))
        return d
    }

    /// A little satin care tag sewn into the side seam, hanging out and down.
    @inline(__always) func tagDist(_ p: V3) -> Float {
        var q = p - tag
        let a: Float = 0.5, c = cos(a), s = sin(a)
        q = V3(q.x * c + q.y * s, -q.x * s + q.y * c, q.z)
        q.z -= 0.12 * q.x * q.x
        return sdBox(q - V3(0.45, 0, 0), V3(0.45, 0.34, 0.012), 0.02)
    }

    func material(_ p: V3) -> (Material, Int) {
        var best = fleece(p), m = Material.fleece, side = 0
        for (i, e) in [eye.0, eye.1].enumerated() {
            let d = simd_length(p - e) - eyeR
            if d < best { best = d; m = .eye; side = i }
        }
        if lidCut < eyeR + 0.1 {
            for (i, e) in [eye.0, eye.1].enumerated() {
                let d = lidDist(p, e)
                if d < best + 0.01 { best = d; m = .lid; side = i }
            }
        }
        for (i, c) in [pom.0, pom.1].enumerated() {
            let d = simd_length(p - c) - pomR
            if d < best { best = d; m = .pom; side = i }
        }
        if tagDist(p) < best { m = .tag }
        return (m, side)
    }

    func normal(_ p: V3) -> V3 {
        let e: Float = 0.006
        let a = V3(1, -1, -1), b = V3(-1, -1, 1), c = V3(-1, 1, -1), d = V3(1, 1, 1)
        return norm(a * sdf(p + a * e) + b * sdf(p + b * e) + c * sdf(p + c * e) + d * sdf(p + d * e))
    }

    func softShadow(_ ro: V3, _ rd: V3, k: Float) -> Float {
        var res: Float = 1, t: Float = 0.04, ph: Float = 1e10
        for _ in 0..<64 {
            let h = sdf(ro + rd * t)
            if h < 0.0005 { return 0 }
            let y = h * h / (2 * ph)
            let d = sqrt(max(h * h - y * y, 0))
            res = min(res, k * d / max(0.0001, t - y))
            ph = h
            t += min(max(h, 0.02), 0.8)
            if t > 30 { break }
        }
        return smooth(0, 1, res)
    }

    func occlusion(_ p: V3, _ n: V3) -> Float {
        var occ: Float = 0, sca: Float = 1
        for i in 0..<6 {
            let h: Float = 0.03 + 0.42 * Float(i) / 5
            occ += (h - sdf(p + n * h)) * sca
            sca *= 0.8
        }
        return clamp01(1 - 1.2 * occ)
    }
}

// MARK: - Lighting

struct Light { let dir: V3; let color: V3; let k: Float }

let key = Light(dir: norm(V3(-0.55, 0.72, 0.55)), color: V3(1.0, 0.95, 0.88) * 2.0, k: 7)
let fill = Light(dir: norm(V3(0.8, 0.22, 0.55)), color: V3(0.72, 0.8, 1.0) * 0.62, k: 4)
let rim = Light(dir: norm(V3(0.45, 0.55, -0.7)), color: V3(1.0, 0.96, 0.9) * 1.3, k: 6)
let sky = V3(0.62, 0.68, 0.8) * 0.3
let bounce = V3(0.42, 0.38, 0.34) * 0.22

func environment(_ r: V3, keyShadow: Float) -> V3 {
    var c = mix3(V3(0.16, 0.15, 0.14), V3(0.55, 0.6, 0.7), smooth(-0.25, 0.7, r.y))
    c += V3(1.0, 0.96, 0.9) * 9 * smooth(0.955, 0.985, dot(r, key.dir)) * keyShadow
    c += V3(0.8, 0.88, 1.0) * 2.5 * smooth(0.95, 0.99, dot(r, fill.dir))
    return c
}

@inline(__always) func aces(_ x: V3) -> V3 {
    let a: Float = 2.51, b: Float = 0.03, c: Float = 2.43, d: Float = 0.59, e: Float = 0.14
    return simd_clamp((x * (a * x + b)) / (x * (c * x + d) + e), V3(repeating: 0), V3(repeating: 1))
}

@inline(__always) func toSRGB(_ c: Float) -> Float {
    c <= 0.0031308 ? c * 12.92 : 1.055 * pow(c, 1 / 2.4) - 0.055
}

extension Scene {
    /// Albedo of the fleece at p, with the belly patch, foot pads, seams and face details.
    func fleeceAlbedo(_ p: V3) -> (V3, groove: Float) {
        var alb = green
        var groove: Float = 0
        // belly patch, with a seam around it
        let bq = p - body
        let be = sqrt(pow(bq.x / (bodyR.x * 0.6), 2) + pow((bq.y + 0.25) / (bodyR.y * 0.64), 2))
        let onBody = (1 - smooth(0.15, 0.35, abs(sdEllipsoid(bq, bodyR)))) * smooth(0.5, 1.5, bq.z)
        if onBody > 0 {
            alb = mix3(alb, cream, (1 - smooth(0.97, 1.0, be)) * onBody)
            groove = max(groove, (1 - smooth(0.0, 0.05, abs(be - 1))) * onBody * 0.8)
        }
        // foot pads on the soles
        for (h, f) in [(hip.0, foot.0), (hip.1, foot.1)] {
            let axis = norm(f - h)
            let q = p - f
            let along = dot(q, axis)
            if along > 0.6 {
                let side = q - axis * along
                let r = simd_length(side) / (legR * 0.78)
                alb = mix3(alb, cream, 1 - smooth(0.9, 1.0, r))
                groove = max(groove, (1 - smooth(0.0, 0.08, abs(r - 1))) * 0.8)
            }
        }
        // face
        let hq = headLocal(p)
        if hq.z > 0 {
            for side: Float in [-1, 1] {
                let d = simd_length(SIMD2<Float>(hq.x - side * 3.6, hq.y + 1.0)) / 0.82
                var felt = blush * (0.88 + 0.24 * noise(p * 31))
                let rim = smooth(0.78, 0.97, d) * (1 - smooth(0.97, 1.0, d))
                felt *= 1 + rim * 0.35 * (hq.y + 1.0) / 0.82
                alb = mix3(alb, felt, 1 - smooth(0.93, 1.0, d))
                groove = max(groove, (1 - smooth(0.0, 0.07, abs(d - 1))) * 0.6)
            }
            let mx = hq.x, my = hq.y + 2.15
            if mouth < 0.05 {
                // stitched smile
                let curve = 0.22 * (mx * mx) / 0.81 - 0.12
                if abs(mx) < 1.0 {
                    let dist = abs(my - curve)
                    let seg = (mx + 1) * 3.2
                    let gap = smooth(0.82, 0.92, seg - floor(seg))
                    let twist = 0.7 + 0.3 * sin((mx * 3 + my) * 55)
                    let a = (1 - smooth(0.09, 0.13, dist)) * (1 - gap * 0.55)
                    alb = mix3(alb, thread * twist, a)
                    groove = max(groove, (1 - smooth(0.06, 0.16, dist)) * 0.55)
                }
            } else {
                let w = 0.72 + 0.28 * mouth, h = 0.2 + 0.75 * mouth
                let e = sqrt(pow(mx / w, 2) + pow((my + 0.12 * mouth) / h, 2))
                if e < 1.06 {
                    var inside = mouthInside * (0.55 + 0.45 * smooth(1.0, 0.2, e))
                    if (my + 0.12 * mouth) < -h * 0.25 { inside = mix3(inside, tongue * 0.8, smooth(-h * 0.25, -h * 0.6, my + 0.12 * mouth)) }
                    alb = mix3(alb, inside, 1 - smooth(0.96, 1.04, e))
                    groove = max(groove, 1 - smooth(0.0, 0.08, abs(e - 1)))
                }
            }
            // eyelid crease when closed
        }
        // centre seam over the top and back of the head
        if (hq.y > 2.8 || hq.z < 0) && simd_length(p - head) < 7 {
            groove = max(groove, (1 - smooth(0.0, 0.06, abs(hq.x))) * 0.35)
        }
        // pile: clumps, then fibres combed downwards
        alb *= 0.86 + 0.28 * fbm(p * 2.2, 2)
        let comb = V3(p.x * 34, p.y * 7, p.z * 34)
        alb *= 0.86 + 0.26 * noise(comb) + 0.06 * noise(p * 70)
        // a little hue drift between yellower and bluer tufts
        let drift = noise(p * 1.3 + 4) - 0.5
        alb *= V3(1 + drift * 0.12, 1, 1 - drift * 0.18)
        return (alb, groove)
    }

    func shadeFleece(_ p: V3, n: V3, v: V3, albedo: V3, groove: Float, fuzzy: Bool) -> V3 {
        var ns = norm(n + noiseVec(p * 13) * 0.5 + noiseVec(V3(p.x * 40, p.y * 9, p.z * 40)) * 0.45)
        if groove > 0 { ns = norm(ns - n * groove * 0.4) }
        let ao = occlusion(p, n) * (1 - groove * 0.55)
        var col = albedo * (sky * (0.5 + 0.5 * n.y) + bounce * (0.5 - 0.5 * n.y)) * ao
        let ndv = max(dot(n, v), 0)
        let sheenTint = mix3(albedo, V3(1, 1, 1), 0.45)
        for l in [key, fill, rim] {
            let sh = softShadow(p + n * 0.03, l.dir, k: l.k)
            let wrap: Float = 0.45
            let diff = max(0, (dot(ns, l.dir) + wrap) / (1 + wrap))
            let sheen = pow(1 - ndv, fuzzy ? 2 : 4) * smooth(-0.35, 0.6, dot(n, l.dir)) * (fuzzy ? 0.22 : 0.3)
            col += l.color * sh * (albedo * diff * (1 - groove * 0.35) + sheenTint * sheen)
        }
        return col
    }

    func shadeEye(_ p: V3, n: V3, v: V3, rd: V3, side: Int) -> V3 {
        let e = side == 0 ? eye.0 : eye.1
        let s: Float = side == 0 ? -1 : 1
        let q = norm(eyeLocal(p, e))
        let front = norm(V3(s * 0.16, 0.06, 1))
        let ang = acos(min(max(dot(q, front), -1), 1))
        var base = V3(0.006, 0.005, 0.005)
        if ang < 0.62 {
            let r = ang / 0.62
            let around = atan2(q.y, q.x)
            let streak = noise(V3(around * 9, r * 4, Float(side) * 7))
            base = V3(0.06, 0.028, 0.012) * (0.45 + 0.9 * streak) * (1 - smooth(0.75, 1.0, r))
            if r < 0.42 { base = V3(0.003, 0.003, 0.003) }
        }
        let keySh = softShadow(p + n * 0.03, key.dir, k: key.k)
        var col = base * (sky + key.color * max(dot(n, key.dir), 0) * keySh + fill.color * max(dot(n, fill.dir), 0))
        let r = rd - 2 * dot(rd, n) * n
        let fres = 0.04 + 0.96 * pow(1 - max(dot(n, v), 0), 5)
        col += environment(r, keyShadow: keySh) * mixf(0.05, 1, fres) * occlusion(p, n)
        return col
    }

    func shadePom(_ p: V3, n: V3, v: V3) -> V3 {
        let alb = pomColor * (0.62 + 0.55 * fbm(p * 5, 3)) * (0.8 + 0.25 * noise(p * 19))
        let ns = norm(n + noiseVec(p * 8) * 1.1 + noiseVec(p * 23) * 0.5)
        let ao = pow(occlusion(p, n), 1.3) * (0.7 + 0.3 * noise(p * 11))
        var col = alb * (sky * (0.5 + 0.5 * n.y) + bounce) * ao
        let ndv = max(dot(n, v), 0)
        for l in [key, fill, rim] {
            let sh = softShadow(p + n * 0.04, l.dir, k: l.k)
            let diff = max(0, (dot(ns, l.dir) + 0.6) / 1.6)
            col += l.color * sh * (alb * diff * (0.75 + 0.25 * ao) + mix3(alb, V3(1, 1, 1), 0.5) * pow(1 - ndv, 2.5) * 0.35)
        }
        return col
    }
}

// MARK: - Rendering

struct Camera {
    let eye: V3, fwd: V3, right: V3, up: V3, half: Float
    init(eye: V3, target: V3, fovDegrees: Float) {
        self.eye = eye
        fwd = norm(target - eye)
        right = norm(simd_cross(fwd, V3(0, 1, 0)))
        up = simd_cross(right, fwd)
        half = tan(fovDegrees * .pi / 360)
    }
    func ray(_ u: Float, _ v: Float) -> V3 { norm(fwd + right * (u * half) + up * (v * half)) }
}

func camera(lift: Float) -> Camera {
    Camera(eye: V3(0, 14.5 + lift, 62), target: V3(0, 10.4 + lift, 0), fovDegrees: 24.5)
}

/// One sample: premultiplied display-space RGBA.
func sample(_ s: Scene, _ ro: V3, _ rd: V3) -> SIMD4<Float> {
    // ground (shadow catcher)
    let tGround: Float = rd.y < 0 ? -ro.y / rd.y : .infinity
    // bounding sphere
    let oc = ro - s.bound.c
    let b = dot(oc, rd), c = dot(oc, oc) - s.bound.r * s.bound.r
    let disc = b * b - c
    var hitT: Float = -1
    var dMin: Float = .infinity, tAtMin: Float = 0
    if disc > 0 {
        var t = max(-b - sqrt(disc), 0)
        let tEnd = min(-b + sqrt(disc), tGround)
        for _ in 0..<220 {
            let d = s.sdf(ro + rd * t)
            if d < dMin { dMin = d; tAtMin = t }
            if d < 0.002 { hitT = t; break }
            t += d * 0.85
            if t > tEnd { break }
        }
    }
    let v = -rd
    if hitT > 0 {
        let p = ro + rd * hitT
        let n = s.normal(p)
        let (m, side) = s.material(p)
        var col: V3
        switch m {
        case .eye: col = s.shadeEye(p, n: n, v: v, rd: rd, side: side)
        case .pom: col = s.shadePom(p, n: n, v: v)
        case .lid:
            let q = s.eyeLocal(p, side == 0 ? s.eye.0 : s.eye.1)
            var (alb, groove) = s.fleeceAlbedo(p)
            // the lids close onto a crease
            groove = max(groove, 1 - smooth(0.0, 0.1, abs(q.y - (s.lidCut + 0.02))))
            if s.lidCut < -s.eyeR { groove = max(groove, (1 - smooth(0.0, 0.09, abs(q.y + 0.25))) * (q.z > 0 ? 1 : 0)) }
            alb *= 1 - 0.18 * smooth(0.2, -1.2, q.y)
            col = s.shadeFleece(p, n: n, v: v, albedo: alb, groove: groove, fuzzy: false)
        case .fleece:
            let (alb, groove) = s.fleeceAlbedo(p)
            col = s.shadeFleece(p, n: n, v: v, albedo: alb, groove: groove, fuzzy: false)
        case .tag:
            // white satin with a faint printed line or two
            let q = p - s.tag
            var alb = V3(0.88, 0.87, 0.84) * (0.94 + 0.06 * noise(V3(q.x * 90, q.y * 4, 0)))
            if abs(sin(q.y * 16)) > 0.94 && q.x > 0.3 && q.x < 0.75 { alb *= 0.6 }
            let ao = s.occlusion(p, n)
            col = alb * sky * ao
            for l in [key, fill, rim] {
                let sh = s.softShadow(p + n * 0.02, l.dir, k: l.k)
                let ndl = abs(dot(n, l.dir))
                let h = norm(l.dir + v)
                col += l.color * sh * (alb * ndl * 0.85 + V3(1, 1, 1) * 0.35 * pow(max(abs(dot(n, h)), 0), 40))
            }
        }
        let t = aces(col)
        return SIMD4(toSRGB(t.x), toSRGB(t.y), toSRGB(t.z), 1)
    }
    // background: shadow on the floor
    var out = SIMD4<Float>(0, 0, 0, 0)
    if tGround.isFinite {
        let g = ro + rd * tGround
        let sh = s.softShadow(g + V3(0, 0.02, 0), key.dir, k: 3.5)
        let ao = s.occlusion(g, V3(0, 1, 0))
        let near = 1 - smooth(9, 18, simd_length(SIMD2<Float>(g.x, g.z - 1)))
        let a = clamp01((1 - sh) * 0.42 + pow(1 - ao, 0.8) * 1.0) * near
        out = SIMD4(0, 0, 0, a)
    }
    // fuzz: fibres sticking out past the silhouette
    if dMin.isFinite {
        let q = ro + rd * tAtMin
        let (m, _) = s.material(q)
        let width: Float = m == .pom ? 0.45 : (m == .eye ? 0 : 0.2)
        if width > 0 && dMin < width && dMin > 0 {
            let fibres = smooth(0.3, 0.8, noise(q * (m == .pom ? 18 : 30)) * 0.6 + noise(q * 61) * 0.4)
            let cov = pow(1 - dMin / width, 1.8) * (0.15 + 0.7 * fibres)
            let n = s.normal(q)
            var col: V3
            if m == .pom {
                col = s.shadePom(q, n: n, v: v)
            } else {
                col = s.shadeFleece(q, n: n, v: v, albedo: s.fleeceAlbedo(q).0, groove: 0, fuzzy: true)
            }
            let t = aces(col)
            let fc = SIMD4<Float>(toSRGB(t.x), toSRGB(t.y), toSRGB(t.z), 1) * cov
            out = fc + out * (1 - cov)
        }
    }
    return out
}

func render(_ pose: Pose, size: Int, spp: Int) -> CGImage {
    let scene = Scene(pose)
    let cam = camera(lift: pose.lift)
    var buf = [UInt8](repeating: 0, count: size * size * 4)
    let grid = Int(Float(spp).squareRoot().rounded())
    buf.withUnsafeMutableBufferPointer { out in
        let ptr = out.baseAddress!
        DispatchQueue.concurrentPerform(iterations: size) { y in
            for x in 0..<size {
                var acc = SIMD4<Float>(0, 0, 0, 0)
                for sy in 0..<grid {
                    for sx in 0..<grid {
                        let jx = (Float(sx) + 0.5) / Float(grid) + (hash(Int32(x), Int32(y), Int32(sx * 7 + sy)) - 0.5) / Float(grid) * 0.6
                        let jy = (Float(sy) + 0.5) / Float(grid) + (hash(Int32(y), Int32(x), Int32(sy * 5 + sx + 99)) - 0.5) / Float(grid) * 0.6
                        let u = ((Float(x) + jx) / Float(size)) * 2 - 1
                        let v = 1 - ((Float(y) + jy) / Float(size)) * 2
                        acc += sample(scene, cam.eye, cam.ray(u, v))
                    }
                }
                acc /= Float(grid * grid)
                let i = (y * size + x) * 4
                ptr[i] = UInt8(clamp01(acc.x) * 255 + 0.5)
                ptr[i + 1] = UInt8(clamp01(acc.y) * 255 + 0.5)
                ptr[i + 2] = UInt8(clamp01(acc.z) * 255 + 0.5)
                ptr[i + 3] = UInt8(clamp01(acc.w) * 255 + 0.5)
            }
        }
    }
    let ctx = CGContext(data: &buf, width: size, height: size, bitsPerComponent: 8, bytesPerRow: size * 4,
                        space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    return ctx.makeImage()!
}

func writePNG(_ image: CGImage, to url: URL) {
    let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)!
    CGImageDestinationAddImage(dest, image, nil)
    CGImageDestinationFinalize(dest)
}

func strip(_ frames: [CGImage]) -> CGImage {
    let s = frames[0].width
    let ctx = CGContext(data: nil, width: s * frames.count, height: s, bitsPerComponent: 8, bytesPerRow: 0,
                        space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    for (i, f) in frames.enumerated() { ctx.draw(f, in: CGRect(x: i * s, y: 0, width: s, height: s)) }
    return ctx.makeImage()!
}

// MARK: - Poses

let tau = Float.pi * 2

let idle: [Pose] = (0..<16).map { i in
    let t = Float(i) / 16
    var p = Pose(breathe: 0.018 * sin(t * tau), tilt: 0.035 * sin(t * tau + 0.6), sway: 0.25 * sin(t * tau + 1.2))
    if i == 12 { p.lid = 0.55 }
    if i == 13 { p.lid = 1 }
    return p
}

let talking: [Pose] = (0..<8).map { i in
    let opens: [Float] = [0.25, 0.7, 1, 0.55, 0.2, 0.85, 0.45, 0.1]
    let t = Float(i) / 8
    return Pose(dy: 0.35 * abs(sin(t * tau)), breathe: -0.01 * abs(sin(t * tau)), tilt: 0.06 * sin(t * tau),
                sway: 0.6 * sin(t * tau * 2), mouth: opens[i])
}

let sleeping: [Pose] = (0..<8).map { i in
    let t = Float(i) / 8
    return Pose(breathe: 0.035 + 0.03 * sin(t * tau), tilt: 0.14 + 0.02 * sin(t * tau), sway: -0.6, lid: 1)
}

let dragging: [Pose] = (0..<4).map { i in
    let swing: [Float] = [-1, -0.3, 1, 0.3]
    return Pose(breathe: -0.04, tilt: -0.04 * swing[i], sway: -0.5 * swing[i], mouth: 0.35, lift: 4, swing: swing[i])
}

// MARK: - Main

let args = Array(CommandLine.arguments.dropFirst())
let outDir = URL(fileURLWithPath: args.first ?? "Skins/plush-alien")
let frameSize = Int(ProcessInfo.processInfo.environment["FRAME"] ?? "288")!
let spp = Int(ProcessInfo.processInfo.environment["SPP"] ?? "4")!

if args.count > 1 {
    // hero render only: build/render-plush <dir> <hero.png> [state] [index]
    let state = args.count > 2 ? args[2] : "idle"
    let index = args.count > 3 ? Int(args[3])! : 0
    let poses = ["idle": idle, "talking": talking, "sleeping": sleeping, "dragging": dragging][state]!
    let start = Date()
    let size = Int(ProcessInfo.processInfo.environment["HERO"] ?? "1024")!
    var image = render(poses[index], size: size, spp: Int(ProcessInfo.processInfo.environment["SPP"] ?? "9")!)
    if ProcessInfo.processInfo.environment["BACKDROP"] != nil {
        // seamless studio paper behind it, for looking at rather than for the skin
        let ctx = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0,
                            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        let paper = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB)!,
                               colors: [CGColor(red: 0.93, green: 0.92, blue: 0.9, alpha: 1),
                                        CGColor(red: 0.84, green: 0.83, blue: 0.81, alpha: 1)] as CFArray, locations: [0, 1])!
        ctx.drawLinearGradient(paper, start: CGPoint(x: 0, y: size), end: CGPoint(x: 0, y: 0), options: [])
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: size, height: size))
        image = ctx.makeImage()!
    }
    writePNG(image, to: URL(fileURLWithPath: args[1]))
    print("hero \(state)[\(index)] in \(String(format: "%.1f", Date().timeIntervalSince(start)))s")
    exit(0)
}

try FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)
for (name, poses) in [("idle", idle), ("talking", talking), ("sleeping", sleeping), ("dragging", dragging)] {
    let start = Date()
    let frames = poses.map { render($0, size: frameSize, spp: spp) }
    writePNG(strip(frames), to: outDir.appendingPathComponent("\(name).png"))
    if name == "idle" { writePNG(frames[0], to: outDir.appendingPathComponent("preview.png")) }
    print("\(name): \(frames.count) frames in \(String(format: "%.1f", Date().timeIntervalSince(start)))s")
}
let manifest = """
{
  "name": "Plush alien",
  "frameWidth": \(frameSize),
  "frameHeight": \(frameSize),
  "scale": \(frameSize / 72),
  "states": {
    "idle":     { "sheet": "idle.png",     "frames": \(idle.count),     "fps": 8 },
    "talking":  { "sheet": "talking.png",  "frames": \(talking.count),  "fps": 10 },
    "sleeping": { "sheet": "sleeping.png", "frames": \(sleeping.count), "fps": 4 },
    "dragging": { "sheet": "dragging.png", "frames": \(dragging.count), "fps": 10 }
  }
}

"""
try manifest.write(to: outDir.appendingPathComponent("manifest.json"), atomically: true, encoding: .utf8)
print("Wrote \(outDir.path)")
