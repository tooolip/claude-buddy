import AppKit
import ImageIO

enum PetState: String, CaseIterable {
    case idle, talking, sleeping, dragging
}

/// A skin is a folder with manifest.json plus one horizontal sprite strip per state.
/// See Skins/default/manifest.json for the format.
final class Skin {
    struct Manifest: Decodable {
        struct State: Decodable {
            let sheet: String
            let frames: Int
            let fps: Double
        }
        let name: String
        let frameWidth: Int
        let frameHeight: Int
        let scale: Double?
        let states: [String: State]
    }

    struct Animation {
        let frames: [CGImage]
        let fps: Double
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
        for (key, spec) in m.states {
            guard let state = PetState(rawValue: key) else { continue }
            let url = directory.appendingPathComponent(spec.sheet) as CFURL
            guard let src = CGImageSourceCreateWithURL(url, nil),
                  let sheet = CGImageSourceCreateImageAtIndex(src, 0, nil) else {
                throw NSError(domain: "Skin", code: 1, userInfo: [NSLocalizedDescriptionKey: "Can't read \(spec.sheet)"])
            }
            let frames = (0..<spec.frames).compactMap { i -> CGImage? in
                let rect = CGRect(x: i * m.frameWidth, y: 0, width: m.frameWidth, height: m.frameHeight)
                return sheet.cropping(to: rect).flatMap { Self.resample($0, to: target) }
            }
            if !frames.isEmpty { anims[state] = Animation(frames: frames, fps: max(spec.fps, 0.5)) }
        }
        guard anims[.idle] != nil else {
            throw NSError(domain: "Skin", code: 2, userInfo: [NSLocalizedDescriptionKey: "Skin has no idle state"])
        }
        animations = anims
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

    /// Missing states fall back to idle, so a skin can start with just one strip.
    func animation(for state: PetState) -> Animation {
        animations[state] ?? animations[.idle]!
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
