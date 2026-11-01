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
    let pointSize: NSSize
    let scale: CGFloat
    private let animations: [PetState: Animation]

    init(directory: URL) throws {
        let data = try Data(contentsOf: directory.appendingPathComponent("manifest.json"))
        let m = try JSONDecoder().decode(Manifest.self, from: data)
        name = m.name
        scale = CGFloat(m.scale ?? 2)
        pointSize = NSSize(width: CGFloat(m.frameWidth) / scale, height: CGFloat(m.frameHeight) / scale)

        var anims: [PetState: Animation] = [:]
        for (key, spec) in m.states {
            guard let state = PetState(rawValue: key) else { continue }
            let url = directory.appendingPathComponent(spec.sheet) as CFURL
            let opts = [kCGImageSourceShouldCacheImmediately: true] as CFDictionary
            guard let src = CGImageSourceCreateWithURL(url, nil),
                  let sheet = CGImageSourceCreateImageAtIndex(src, 0, opts) else {
                throw NSError(domain: "Skin", code: 1, userInfo: [NSLocalizedDescriptionKey: "Can't read \(spec.sheet)"])
            }
            let frames = (0..<spec.frames).compactMap { i in
                sheet.cropping(to: CGRect(x: i * m.frameWidth, y: 0, width: m.frameWidth, height: m.frameHeight))
            }
            if !frames.isEmpty { anims[state] = Animation(frames: frames, fps: max(spec.fps, 0.5)) }
        }
        guard anims[.idle] != nil else {
            throw NSError(domain: "Skin", code: 2, userInfo: [NSLocalizedDescriptionKey: "Skin has no idle state"])
        }
        animations = anims
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

    static func load(id: String) -> Skin? {
        let all = available()
        let url = all.first { $0.id == id }?.url ?? all.first { $0.id == "default" }?.url
        return url.flatMap { try? Skin(directory: $0) }
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
