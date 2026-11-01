import Foundation

/// Listens on a unix socket for Claude Code hook events.
///
/// The hook command (see scripts/hooks.py) pipes the hook's JSON to
/// `curl --unix-socket <socket> --data-binary @- http://localhost/hook`, so this speaks
/// just enough HTTP to read one POST body and answer 204.
final class HookServer {
    static var socketPath: String { Prefs.supportDir.appendingPathComponent("hook.sock").path }

    var onEvent: (([String: Any]) -> Void)?
    private var fd: Int32 = -1
    private var source: DispatchSourceRead?
    private let queue = DispatchQueue(label: "hook-server")

    func start() throws {
        let path = Self.socketPath
        unlink(path)
        fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { throw posixError("socket") }

        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        let capacity = MemoryLayout.size(ofValue: addr.sun_path)
        guard path.utf8.count < capacity else { throw posixError("socket path too long") }
        withUnsafeMutableBytes(of: &addr.sun_path) { raw in
            raw.copyBytes(from: path.utf8)
            raw[path.utf8.count] = 0
        }
        let bound = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                bind(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        guard bound == 0 else { throw posixError("bind") }
        chmod(path, 0o600)
        guard listen(fd, 16) == 0 else { throw posixError("listen") }
        _ = fcntl(fd, F_SETFL, fcntl(fd, F_GETFL) | O_NONBLOCK)

        let src = DispatchSource.makeReadSource(fileDescriptor: fd, queue: queue)
        src.setEventHandler { [weak self] in self?.acceptAll() }
        src.resume()
        source = src
    }

    func stop() {
        source?.cancel()
        if fd >= 0 { close(fd) }
        unlink(Self.socketPath)
    }

    private func acceptAll() {
        while true {
            let client = accept(fd, nil, nil)
            guard client >= 0 else { return }
            handle(client)
        }
    }

    private func handle(_ client: Int32) {
        defer { close(client) }
        _ = fcntl(client, F_SETFL, fcntl(client, F_GETFL) & ~O_NONBLOCK)
        var tv = timeval(tv_sec: 2, tv_usec: 0)
        setsockopt(client, SOL_SOCKET, SO_RCVTIMEO, &tv, socklen_t(MemoryLayout<timeval>.size))
        var nosig: Int32 = 1
        setsockopt(client, SOL_SOCKET, SO_NOSIGPIPE, &nosig, socklen_t(MemoryLayout<Int32>.size))

        var data = Data()
        var buf = [UInt8](repeating: 0, count: 16384)
        var bodyStart: Int?
        var contentLength: Int?
        while data.count < 8_000_000 {
            let n = read(client, &buf, buf.count)
            if n <= 0 { break }
            data.append(buf, count: n)
            if bodyStart == nil, let r = data.range(of: Data("\r\n\r\n".utf8)) {
                bodyStart = r.upperBound
                let head = String(decoding: data[..<r.lowerBound], as: UTF8.self).lowercased()
                if let line = head.split(separator: "\r\n").first(where: { $0.hasPrefix("content-length:") }) {
                    contentLength = Int(line.dropFirst("content-length:".count).trimmingCharacters(in: .whitespaces))
                }
            }
            if let s = bodyStart, let len = contentLength, data.count - s >= len { break }
        }
        let reply = "HTTP/1.1 204 No Content\r\nContent-Length: 0\r\nConnection: close\r\n\r\n"
        _ = reply.withCString { write(client, $0, strlen($0)) }

        guard let s = bodyStart,
              let obj = try? JSONSerialization.jsonObject(with: data[s...]) as? [String: Any] else { return }
        DispatchQueue.main.async { [weak self] in self?.onEvent?(obj) }
    }

    private func posixError(_ what: String) -> NSError {
        NSError(domain: NSPOSIXErrorDomain, code: Int(errno), userInfo: [NSLocalizedDescriptionKey: "\(what): \(String(cString: strerror(errno)))"])
    }
}

enum Transcript {
    /// The last thing Claude said in a session, read from the tail of its JSONL transcript.
    static func lastAssistantText(path: String) -> String? {
        guard let h = FileHandle(forReadingAtPath: path) else { return nil }
        defer { try? h.close() }
        let end = (try? h.seekToEnd()) ?? 0
        let start = end > 512_000 ? end - 512_000 : 0
        try? h.seek(toOffset: start)
        guard let data = try? h.readToEnd() else { return nil }
        for line in data.split(separator: 0x0A).reversed() {
            guard let obj = try? JSONSerialization.jsonObject(with: Data(line)) as? [String: Any],
                  obj["type"] as? String == "assistant",
                  let content = (obj["message"] as? [String: Any])?["content"] as? [[String: Any]] else { continue }
            let text = content.compactMap { $0["type"] as? String == "text" ? $0["text"] as? String : nil }
                .joined(separator: "\n")
            if !text.isEmpty { return text }
        }
        return nil
    }
}
