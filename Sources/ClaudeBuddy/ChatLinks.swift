import AppKit

/// The only place that knows how to open chats in the Claude desktop app.
///
/// These claude:// links aren't documented. They were found in the desktop app's bundle
/// (v4.4212) and tested on 2026-11-01:
///   claude://resume?session=<cli-session-uuid>  imports a CLI session into the Code tab and opens it;
///                                              for a session that started in the app, it opens that one
///   claude://code/new?folder=<path>             new Code session in a folder
///   claude://code/continue?session=last         most recently active Code session
/// If the app ever drops them, swap the bodies here. The Terminal fallback is already in place.
enum ChatLinks {
    static var desktopAppInstalled: Bool {
        NSWorkspace.shared.urlForApplication(toOpen: URL(string: "claude://")!) != nil
    }

    /// Opens one specific conversation, by the CLI's session id.
    static func openConversation(sessionId: String, folder: String?) {
        if desktopAppInstalled, let url = url("claude://resume", ["session": sessionId]) {
            NSWorkspace.shared.open(url)
        } else {
            openInTerminal("claude --resume \(shellQuote(sessionId))", folder: folder)
        }
    }

    static func openNewChat(folder: String) {
        if desktopAppInstalled, let url = url("claude://code/new", ["folder": folder]) {
            NSWorkspace.shared.open(url)
        } else {
            openInTerminal("claude", folder: folder)
        }
    }

    static func openMostRecent(folder: String) {
        if desktopAppInstalled, let url = url("claude://code/continue", ["session": "last"]) {
            NSWorkspace.shared.open(url)
        } else {
            openInTerminal("claude --continue", folder: folder)
        }
    }

    private static func url(_ base: String, _ query: [String: String]) -> URL? {
        var c = URLComponents(string: base)
        c?.queryItems = query.map { URLQueryItem(name: $0.key, value: $0.value) }
        return c?.url
    }

    private static func shellQuote(_ s: String) -> String {
        "'" + s.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    /// Opens Terminal running a command, via a throwaway .command file (no Automation permission needed).
    private static func openInTerminal(_ command: String, folder: String?) {
        let dir = folder ?? NSHomeDirectory()
        let script = "#!/bin/zsh -l\ncd \(shellQuote(dir)) && \(command)\n"
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("claude-buddy-\(UUID().uuidString.prefix(8)).command")
        do {
            try script.write(to: url, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: url.path)
            NSWorkspace.shared.open(url)
        } catch {
            NSSound.beep()
        }
    }
}
