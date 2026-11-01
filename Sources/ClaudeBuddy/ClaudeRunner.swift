import Foundation

/// Talks to the claude CLI. A claude process only exists while a reply is being generated.
final class ClaudeRunner {
    struct Reply {
        let sessionId: String?
        let text: String
        let isError: Bool
    }

    private var process: Process?
    var isRunning: Bool { process != nil }

    /// Our own environment minus anything a parent Claude Code session leaked into it
    /// (those vars switch the CLI into host-managed auth). CLAUDE_BUDDY_CHILD lets our
    /// hook command skip events from processes we started ourselves.
    static func environment() -> [String: String] {
        var env = ProcessInfo.processInfo.environment.filter { key, _ in
            !(key.hasPrefix("CLAUDE") || key == "ANTHROPIC_BASE_URL" || key == "AI_AGENT" || key == "BAGGAGE")
        }
        let path = env["PATH"] ?? "/usr/bin:/bin:/usr/sbin:/sbin"
        let extra = ["/opt/homebrew/bin", "/usr/local/bin", NSHomeDirectory() + "/.local/bin"]
            .filter { !path.split(separator: ":").contains(Substring($0)) }
        env["PATH"] = (extra + [path]).joined(separator: ":")
        env["CLAUDE_BUDDY_CHILD"] = "1"
        return env
    }

    /// Sends a message. The prompt goes in on stdin so text starting with "-" can't be read as a flag.
    func send(_ message: String, resume: String?, folder: String,
              onSession: @escaping (String) -> Void,
              completion: @escaping (Reply) -> Void) {
        var args = ["-p", "--output-format", "stream-json", "--verbose"]
        if let resume { args += ["--resume", resume] }
        if !Prefs.permissionMode.isEmpty { args += ["--permission-mode", Prefs.permissionMode] }

        let p = Process()
        p.executableURL = URL(fileURLWithPath: Prefs.claudePath)
        p.arguments = args
        p.currentDirectoryURL = URL(fileURLWithPath: folder)
        p.environment = Self.environment()

        let parser = StreamParser { sid in DispatchQueue.main.async { onSession(sid) } }
        let stdin = Pipe(), stdout = Pipe(), stderr = Pipe()
        p.standardInput = stdin
        p.standardOutput = stdout
        p.standardError = stderr

        let group = DispatchGroup()
        group.enter(); group.enter(); group.enter()
        let errBuf = LockedData()
        stdout.fileHandleForReading.readabilityHandler = { h in
            let chunk = h.availableData
            if chunk.isEmpty { h.readabilityHandler = nil; group.leave() } else { parser.feed(chunk) }
        }
        stderr.fileHandleForReading.readabilityHandler = { h in
            let chunk = h.availableData
            if chunk.isEmpty { h.readabilityHandler = nil; group.leave() } else { errBuf.append(chunk) }
        }
        p.terminationHandler = { _ in group.leave() }

        do {
            try p.run()
        } catch {
            stdout.fileHandleForReading.readabilityHandler = nil
            stderr.fileHandleForReading.readabilityHandler = nil
            completion(Reply(sessionId: resume, text: "Couldn't start claude: \(error.localizedDescription)", isError: true))
            return
        }
        process = p
        let input = stdin.fileHandleForWriting
        DispatchQueue.global(qos: .userInitiated).async {
            try? input.write(contentsOf: Data(message.utf8))
            try? input.close()
        }

        group.notify(queue: .main) { [weak self] in
            self?.process = nil
            parser.finish()
            var text = parser.result ?? parser.lastAssistantText
            var isError = parser.isError
            if text.isEmpty {
                isError = true
                let err = String(decoding: errBuf.data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
                text = err.isEmpty ? "Claude exited with status \(p.terminationStatus)." : err
            }
            completion(Reply(sessionId: parser.sessionId ?? resume, text: text, isError: isError))
        }
    }

    func cancel() {
        process?.terminate()
    }

    // MARK: - Summaries

    /// Shrinks a reply to a line or two with Haiku. Falls back to the first sentence.
    static func summarise(_ text: String, completion: @escaping (String) -> Void) {
        let plain = Summary.clean(text)
        if plain.count <= 140, !plain.contains("\n") {
            completion(plain)
            return
        }
        let fallback = Summary.firstSentence(plain)
        let prompt = """
            You write the speech bubble for a small desktop pet that relays replies from Claude. \
            Given Claude's reply, write one or two short plain-text lines, 140 characters at most, \
            saying the key answer or outcome in Claude's own voice (e.g. "Fixed the login bug and opened a PR."). \
            No markdown, no quotes, no preamble.
            """
        let p = Process()
        p.executableURL = URL(fileURLWithPath: Prefs.claudePath)
        p.arguments = ["-p", "--model", "haiku", "--output-format", "text", "--no-session-persistence",
                       "--tools", "", "--strict-mcp-config", "--disable-slash-commands",
                       "--settings", #"{"disableAllHooks":true}"#, "--system-prompt", prompt]
        p.currentDirectoryURL = Prefs.supportDir
        p.environment = environment()
        let stdin = Pipe(), stdout = Pipe()
        p.standardInput = stdin
        p.standardOutput = stdout
        p.standardError = FileHandle.nullDevice

        let out = LockedData()
        let group = DispatchGroup()
        group.enter(); group.enter()
        stdout.fileHandleForReading.readabilityHandler = { h in
            let chunk = h.availableData
            if chunk.isEmpty { h.readabilityHandler = nil; group.leave() } else { out.append(chunk) }
        }
        p.terminationHandler = { _ in group.leave() }
        do { try p.run() } catch {
            stdout.fileHandleForReading.readabilityHandler = nil
            completion(fallback)
            return
        }
        let input = stdin.fileHandleForWriting
        DispatchQueue.global(qos: .userInitiated).async {
            try? input.write(contentsOf: Data(String(text.prefix(8000)).utf8))
            try? input.close()
        }
        let timeout = DispatchWorkItem { if p.isRunning { p.terminate() } }
        DispatchQueue.main.asyncAfter(deadline: .now() + 30, execute: timeout)

        group.notify(queue: .main) {
            timeout.cancel()
            let s = Summary.clean(String(decoding: out.data, as: UTF8.self))
            let ok = p.terminationReason == .exit && p.terminationStatus == 0 && !s.isEmpty && s.count < 300
            completion(ok ? s : fallback)
        }
    }
}

/// Parses claude's stream-json output (one JSON object per line).
private final class StreamParser {
    private let lock = NSLock()
    private var buffer = Data()
    private let onSession: (String) -> Void
    private(set) var sessionId: String?
    private(set) var result: String?
    private(set) var isError = false
    private(set) var lastAssistantText = ""

    init(onSession: @escaping (String) -> Void) { self.onSession = onSession }

    func feed(_ chunk: Data) {
        lock.lock(); defer { lock.unlock() }
        buffer.append(chunk)
        var lines = buffer.split(separator: 0x0A, omittingEmptySubsequences: false)
        buffer = Data(lines.removeLast())
        for line in lines where !line.isEmpty { handle(Data(line)) }
    }

    func finish() {
        lock.lock(); defer { lock.unlock() }
        if !buffer.isEmpty { handle(buffer); buffer = Data() }
    }

    private func handle(_ line: Data) {
        guard let obj = try? JSONSerialization.jsonObject(with: line) as? [String: Any],
              let type = obj["type"] as? String else { return }
        if sessionId == nil, let sid = obj["session_id"] as? String {
            sessionId = sid
            onSession(sid)
        }
        switch type {
        case "assistant":
            let content = (obj["message"] as? [String: Any])?["content"] as? [[String: Any]] ?? []
            let text = content.compactMap { $0["type"] as? String == "text" ? $0["text"] as? String : nil }
                .joined(separator: "\n")
            if !text.isEmpty { lastAssistantText = text }
        case "result":
            result = obj["result"] as? String
            isError = (obj["is_error"] as? Bool ?? false) || (obj["subtype"] as? String ?? "success") != "success"
        default:
            break
        }
    }
}

private final class LockedData {
    private let lock = NSLock()
    private var storage = Data()
    func append(_ d: Data) { lock.lock(); storage.append(d); lock.unlock() }
    var data: Data { lock.lock(); defer { lock.unlock() }; return storage }
}

enum Summary {
    /// Strips the markdown that would look odd in a speech bubble.
    static func clean(_ s: String) -> String {
        var t = s.replacingOccurrences(of: "```[\\s\\S]*?```", with: " ", options: .regularExpression)
        t = t.replacingOccurrences(of: "\\[([^\\]]+)\\]\\([^)]*\\)", with: "$1", options: .regularExpression)
        t = t.replacingOccurrences(of: "(?m)^\\s{0,3}(#{1,6}|[-*+]|\\d+\\.|>)\\s+", with: "", options: .regularExpression)
        t = t.replacingOccurrences(of: "[*_`]{1,3}", with: "", options: .regularExpression)
        t = t.replacingOccurrences(of: "[ \\t]+", with: " ", options: .regularExpression)
        t = t.replacingOccurrences(of: "\\n{2,}", with: "\n", options: .regularExpression)
        return t.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func firstSentence(_ s: String) -> String {
        // Skip short heading-ish lines like "Done" when there's a real sentence after them.
        let lines = s.split(separator: "\n").map(String.init)
        let firstLine = lines.first { $0.count >= 25 } ?? lines.first ?? s
        var sentence = firstLine
        if let r = firstLine.range(of: "[.!?](\\s|$)", options: .regularExpression),
           firstLine.distance(from: firstLine.startIndex, to: r.lowerBound) >= 10 {
            sentence = String(firstLine[..<r.upperBound])
        }
        sentence = sentence.trimmingCharacters(in: .whitespaces)
        return sentence.count > 140 ? String(sentence.prefix(139)) + "…" : sentence
    }
}
