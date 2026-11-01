import AppKit

/// User settings, stored in UserDefaults (domain io.github.tooolip.claude-buddy).
enum Prefs {
    private static let d = UserDefaults.standard

    static var workingFolder: String {
        get { d.string(forKey: "workingFolder") ?? NSHomeDirectory() + "/Code/projects" }
        set { d.set(newValue, forKey: "workingFolder") }
    }

    /// Path to the claude CLI. Empty means "find it".
    static var claudePath: String {
        if let p = d.string(forKey: "claudePath"), !p.isEmpty { return p }
        let candidates = ["/opt/homebrew/bin/claude", "/usr/local/bin/claude", NSHomeDirectory() + "/.local/bin/claude",
                          NSHomeDirectory() + "/.claude/local/claude"]
        return candidates.first { FileManager.default.isExecutableFile(atPath: $0) } ?? "/opt/homebrew/bin/claude"
    }

    /// Passed as --permission-mode. Empty means the CLI's own default.
    static var permissionMode: String {
        get { d.string(forKey: "permissionMode") ?? "" }
        set { d.set(newValue, forKey: "permissionMode") }
    }

    static var skin: String {
        get { d.string(forKey: "skin") ?? "default" }
        set { d.set(newValue, forKey: "skin") }
    }

    static var sleepMinutes: Double {
        get { d.object(forKey: "sleepMinutes") as? Double ?? 5 }
        set { d.set(newValue, forKey: "sleepMinutes") }
    }

    /// Use Haiku to summarise replies from other Claude Code sessions (seen via hooks).
    static var summariseOtherSessions: Bool {
        get { d.object(forKey: "summariseOtherSessions") as? Bool ?? true }
        set { d.set(newValue, forKey: "summariseOtherSessions") }
    }

    static var petOrigin: NSPoint? {
        get { d.string(forKey: "petOrigin").map { NSPointFromString($0) } }
        set { d.set(newValue.map { NSStringFromPoint($0) }, forKey: "petOrigin") }
    }

    static var supportDir: URL {
        let url = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("ClaudeBuddy", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}
