import AppKit
import ImageIO

enum PetState: String, CaseIterable {
    case idle, talking, sleeping, dragging
    // Optional: skins without these fall back (see `fallback`).
    case draggingLeft, draggingRight, waving, failed, waiting

    var fallback: PetState? {
        switch self {
        case .draggingLeft, .draggingRight: return .dragging
        case .waving: return .talking
        case .failed, .waiting: return .idle
        default: return nil
        }
    }
}

/// A skin is a folder with manifest.json plus one horizontal sprite strip per state.
/// See Skins/default/manifest.json for the format.
final class Skin {
    struct Manifest: Decodable {
        struct State: Decodable {
            let sheet: String
            let frames: Int?
            let fps: Double?
            /// Grid sheets (like Codex pets): which row, and optionally which columns in order.
            let row: Int?
            let cells: [Int]?
            /// Per-frame milliseconds; overrides fps.
            let durations: [Double]?
        }
        let name: String
        let frameWidth: Int
        let frameHeight: Int
        let scale: Double?
        let states: [String: State]
    }

    struct Animation {
        let frames: [CGImage]
        /// Seconds per frame.
        let durations: [Double]
    }

    let name: String
    /// On-screen size, after the user's size setting.
    let pointSize: NSSize
    /// Pixels per point of the frames (the screen's backing scale).
    let scale: CGFloat
    private let animations: [PetState: Animation]

    /// Reads just the name, without decoding any images.
    static func name(at directory: URL) -> String? {
        guard let data = try? Data(contentsOf: directory.appendingPathComponent("manifest.json")) else { return nil }
        return (try? JSONDecoder().decode(Manifest.self, from: data))?.name
    }

    /// Frames are resampled to exactly the pixels they'll be shown at, so a small pet or a 1x
    /// screen costs less memory, and the full-size sheets are dropped once loaded.
    init(directory: URL, sizeScale: CGFloat = 1, backingScale: CGFloat = 2) throws {
        let data = try Data(contentsOf: directory.appendingPathComponent("manifest.json"))
        let m = try JSONDecoder().decode(Manifest.self, from: data)
        name = m.name
        let sourceScale = CGFloat(m.scale ?? 2)
        pointSize = NSSize(width: (CGFloat(m.frameWidth) / sourceScale * sizeScale).rounded(),
                           height: (CGFloat(m.frameHeight) / sourceScale * sizeScale).rounded())
        scale = backingScale
        let target = CGSize(width: pointSize.width * backingScale, height: pointSize.height * backingScale)

        var anims: [PetState: Animation] = [:]
        var sheets: [String: CGImage] = [:]
        for (key, spec) in m.states {
            guard let state = PetState(rawValue: key) else { continue }
            guard let sheet = sheets[spec.sheet] ?? Self.readImage(directory.appendingPathComponent(spec.sheet)) else {
                throw NSError(domain: "Skin", code: 1, userInfo: [NSLocalizedDescriptionKey: "Can't read \(spec.sheet)"])
            }
            sheets[spec.sheet] = sheet
            let columns = spec.cells ?? Array(0..<(spec.frames ?? spec.durations?.count ?? 1))
            let y = (spec.row ?? 0) * m.frameHeight
            let frames = columns.compactMap { i -> CGImage? in
                let rect = CGRect(x: i * m.frameWidth, y: y, width: m.frameWidth, height: m.frameHeight)
                return sheet.cropping(to: rect).flatMap { Self.resample($0, to: target) }
            }
            guard !frames.isEmpty else { continue }
            let perFrame = 1 / max(spec.fps ?? 8, 0.5)
            let durations = frames.indices.map { i in
                spec.durations.flatMap { i < $0.count ? max($0[i], 20) / 1000 : nil } ?? perFrame
            }
            anims[state] = Animation(frames: frames, durations: durations)
        }
        guard anims[.idle] != nil else {
            throw NSError(domain: "Skin", code: 2, userInfo: [NSLocalizedDescriptionKey: "Skin has no idle state"])
        }
        animations = anims
    }

    private static func readImage(_ url: URL) -> CGImage? {
        CGImageSourceCreateWithURL(url as CFURL, nil).flatMap { CGImageSourceCreateImageAtIndex($0, 0, nil) }
    }

    private static func resample(_ image: CGImage, to size: CGSize) -> CGImage? {
        let w = max(Int(size.width.rounded()), 1), h = max(Int(size.height.rounded()), 1)
        guard let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        ctx.interpolationQuality = .high
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        return ctx.makeImage()
    }

    /// Missing states fall back (eventually to idle), so a skin can start with just one strip.
    func animation(for state: PetState) -> Animation {
        var s: PetState? = state
        while let cur = s {
            if let a = animations[cur] { return a }
            s = cur.fallback
        }
        return animations[.idle]!
    }

    // MARK: - Finding skins

    static var userSkinsDir: URL {
        let url = Prefs.supportDir.appendingPathComponent("Skins", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private static var builtInDirs: [URL] {
        var dirs: [URL] = []
        if let res = Bundle.main.resourceURL { dirs.append(res.appendingPathComponent("Skins")) }
        dirs.append(URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent("Skins"))
        return dirs
    }

    /// Skin id -> folder. User skins override built-in ones with the same folder name.
    static func available() -> [(id: String, url: URL)] {
        var found: [String: URL] = [:]
        for dir in builtInDirs + [userSkinsDir] {
            let items = (try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)) ?? []
            for item in items where FileManager.default.fileExists(atPath: item.appendingPathComponent("manifest.json").path) {
                found[item.lastPathComponent] = item
            }
        }
        return found.keys.sorted().map { ($0, found[$0]!) }
    }

    static func load(id: String, sizeScale: CGFloat, backingScale: CGFloat) -> Skin? {
        let all = available()
        let url = all.first { $0.id == id }?.url ?? all.first { $0.id == "default" }?.url
        return url.flatMap { try? Skin(directory: $0, sizeScale: sizeScale, backingScale: backingScale) }
    }

    /// Copies the default skin into the user folder once, as a starting point for modding.
    static func seedUserFolder() {
        let target = userSkinsDir.appendingPathComponent("my-skin")
        guard !FileManager.default.fileExists(atPath: target.path),
              let src = available().first(where: { $0.id == "default" })?.url,
              src.deletingLastPathComponent().standardizedFileURL != userSkinsDir.standardizedFileURL else { return }
        try? FileManager.default.copyItem(at: src, to: target)
        // Give the copy its own name so it shows up separately in Settings.
        let manifest = target.appendingPathComponent("manifest.json")
        if let text = try? String(contentsOf: manifest, encoding: .utf8) {
            try? text.replacingOccurrences(of: "\"Mochi\"", with: "\"My skin (copy of Mochi)\"")
                .write(to: manifest, atomically: true, encoding: .utf8)
        }
    }
}
