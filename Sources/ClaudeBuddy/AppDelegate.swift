import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var pet: Pet!
    private let bubble = Bubble()
    private let input = InputBox()
    private let runner = ClaudeRunner()
    private let hooks = HookServer()
    private var settings: SettingsWindow?

    /// The buddy's own conversation (a CLI session id), continued with --resume.
    private var thread: (id: String, folder: String)?
    /// Once a thread has been opened in the desktop app, carry on there rather than from here.
    private var threadHandedOff = false
    /// Most recent conversation that got a reply, from us or any session via hooks.
    private var lastReplied: (id: String, folder: String?)?
    /// Sessions mid-turn, seen via UserPromptSubmit, with when we last heard from them.
    private var workingSessions: [String: Date] = [:]
    private var workingSweep: Timer?

    func applicationDidFinishLaunching(_ notification: Notification) {
        Skin.seedUserFolder()
        guard let skin = Skin.load(id: Prefs.skin) else {
            let alert = NSAlert()
            alert.messageText = "Claude Buddy couldn't find any skins."
            alert.runModal()
            NSApp.terminate(nil)
            return
        }
        pet = Pet(skin: skin)
        pet.view.onClick = { [weak self] in self?.petClicked() }
        pet.view.onRightClick = { [weak self] e in self?.showMenu(e) }
        pet.show()

        input.onSubmit = { [weak self] text, fresh in self?.send(text, newThread: fresh) }

        Hotkeys.shared.on(.talk) { [weak self] in self?.toggleInput() }
        Hotkeys.shared.on(.openLast) { [weak self] in self?.openLast() }
        Hotkeys.shared.on(.newChat) { [weak self] in
            self?.pet.poke()
            ChatLinks.openNewChat(folder: Prefs.workingFolder)
        }

        hooks.onEvent = { [weak self] e in self?.hookEvent(e) }
        do { try hooks.start() } catch { NSLog("Claude Buddy: hook server failed: \(error)") }
    }

    func applicationWillTerminate(_ notification: Notification) {
        runner.cancel()
        hooks.stop()
    }

    // MARK: - Talking to Claude

    private func petClicked() {
        if bubble.isShown { bubble.hide() } else { toggleInput() }
    }

    private func toggleInput() {
        pet.poke()
        if input.isShown { input.hide(); return }
        let continuing = thread != nil && !threadHandedOff
        input.show(pet: pet.panel, placeholder: continuing ? "Reply…   ⌘↩ new chat" : "Ask Claude…")
    }

    private func send(_ text: String, newThread: Bool) {
        guard !runner.isRunning else {
            say("Still working on the last one…", autoHide: 4)
            return
        }
        if newThread || threadHandedOff { thread = nil; threadHandedOff = false }
        let folder = thread?.folder ?? Prefs.workingFolder
        pet.setTalking(true, reason: "own")
        say("…", autoHide: nil)

        runner.send(text, resume: thread?.id, folder: folder, onSession: { [weak self] sid in
            self?.thread = (sid, folder)
        }, completion: { [weak self] reply in
            guard let self else { return }
            if let sid = reply.sessionId { thread = (sid, folder) }
            if reply.isError {
                pet.setTalking(false, reason: "own")
                showReply(Summary.firstSentence(Summary.clean(reply.text)), session: reply.sessionId, folder: folder,
                          autoHide: nil)
                return
            }
            ClaudeRunner.summarise(reply.text) { summary in
                self.pet.setTalking(false, reason: "own")
                self.showReply(summary, session: reply.sessionId, folder: folder, autoHide: nil)
            }
        })
    }

    private func showReply(_ text: String, session: String?, folder: String?, autoHide: TimeInterval?) {
        if let session { lastReplied = (session, folder) }
        pet.talkBurst()
        bubble.show(text.isEmpty ? "(no reply)" : text, pet: pet.panel, autoHide: autoHide, onClick: session.map { sid in
            { [weak self] in self?.open(session: sid, folder: folder) }
        })
    }

    private func say(_ text: String, autoHide: TimeInterval?) {
        bubble.show(text, pet: pet.panel, autoHide: autoHide, onClick: nil)
    }

    private func open(session: String, folder: String?) {
        if session == thread?.id { threadHandedOff = true }
        ChatLinks.openConversation(sessionId: session, folder: folder)
    }

    private func openLast() {
        pet.poke()
        if let last = lastReplied {
            bubble.hide()
            open(session: last.id, folder: last.folder)
        } else {
            ChatLinks.openMostRecent(folder: Prefs.workingFolder)
        }
    }

    // MARK: - Hook events from every Claude Code session

    private func hookEvent(_ e: [String: Any]) {
        if let cmd = e["debug"] as? String {
            if UserDefaults.standard.bool(forKey: "debug") { debug(cmd, e["arg"] as? String ?? "") }
            return
        }
        guard let name = e["hook_event_name"] as? String, let sid = e["session_id"] as? String else { return }
        let cwd = e["cwd"] as? String
        switch name {
        case "UserPromptSubmit":
            workingSessions[sid] = Date()
            pet.setTalking(true, reason: "hook:" + sid)
            sweepWorkingSessions()
        case "Stop":
            workingSessions[sid] = nil
            pet.setTalking(false, reason: "hook:" + sid)
            let text = (e["last_assistant_message"] as? String)
                ?? (e["transcript_path"] as? String).flatMap(Transcript.lastAssistantText(path:))
                ?? ""
            guard !text.isEmpty, !runner.isRunning else { lastReplied = (sid, cwd); return }
            let show: (String) -> Void = { [weak self] summary in
                self?.showReply(summary, session: sid, folder: cwd, autoHide: 30)
            }
            if Prefs.summariseOtherSessions {
                ClaudeRunner.summarise(text, completion: show)
            } else {
                show(Summary.firstSentence(Summary.clean(text)))
            }
        case "Notification":
            let message = e["message"] as? String ?? "Claude needs you"
            let type = e["notification_type"] as? String ?? ""
            // The "waiting for your input" nudge fires after every idle minute; skip it.
            if type == "idle_prompt" || message.localizedCaseInsensitiveContains("waiting for your input") { return }
            guard !runner.isRunning else { return }
            pet.poke()
            showReply(message, session: sid, folder: cwd, autoHide: 60)
        default:
            break
        }
    }

    /// A turn that's interrupted never sends Stop, so forget sessions we haven't heard from in a while.
    private func sweepWorkingSessions() {
        workingSweep?.invalidate()
        guard !workingSessions.isEmpty else { return }
        workingSweep = Timer.scheduledTimer(withTimeInterval: 60, repeats: false) { [weak self] _ in
            guard let self else { return }
            let cutoff = Date().addingTimeInterval(-20 * 60)
            for (sid, seen) in workingSessions where seen < cutoff {
                workingSessions[sid] = nil
                pet.setTalking(false, reason: "hook:" + sid)
            }
            sweepWorkingSessions()
        }
        workingSweep?.tolerance = 20
    }

    // MARK: - Menu

    private func showMenu(_ event: NSEvent) {
        pet.poke()
        let menu = NSMenu()
        func item(_ title: String, _ hotkey: HotkeyAction? = nil, _ action: @escaping () -> Void) {
            let i = ClosureMenuItem(title: title, action: action)
            if let hotkey, let s = Hotkeys.shared.shortcut(for: hotkey), !s.char.isEmpty {
                i.keyEquivalent = s.char.lowercased()
                i.keyEquivalentModifierMask = s.flags
            }
            menu.addItem(i)
        }
        item("Talk to Claude", .talk) { [weak self] in self?.toggleInput() }
        item("Open Last Reply", .openLast) { [weak self] in self?.openLast() }
        item("New Chat in Claude", .newChat) { ChatLinks.openNewChat(folder: Prefs.workingFolder) }
        menu.addItem(.separator())
        if runner.isRunning {
            item("Stop Reply") { [weak self] in self?.runner.cancel() }
        }
        if thread != nil {
            item("Start Fresh Thread") { [weak self] in self?.thread = nil; self?.threadHandedOff = false }
        }
        item(pet.state == .sleeping ? "Wake Up" : "Nap") { [weak self] in
            guard let self else { return }
            pet.state == .sleeping ? pet.poke() : pet.sleepNow()
        }
        menu.addItem(.separator())
        item("Settings…") { [weak self] in self?.showSettings() }
        item("Quit Claude Buddy") { NSApp.terminate(nil) }
        NSMenu.popUpContextMenu(menu, with: event, for: pet.view)
    }

    private func showSettings() {
        if settings == nil {
            settings = SettingsWindow(onSkinChange: { [weak self] id in
                guard let self, let skin = Skin.load(id: id) else { return }
                pet.setSkin(skin)
            }, onClose: { [weak self] in self?.settings = nil })
        }
        NSApp.activate(ignoringOtherApps: true)
        settings?.window.makeKeyAndOrderFront(nil)
    }
}

// MARK: - Debug

/// Lets scripts drive the app through the hook socket (scripts/debug.sh). Ignored unless
/// `defaults write io.github.tooolip.claude-buddy debug -bool true`.
extension AppDelegate {
    fileprivate func debug(_ cmd: String, _ arg: String) {
        switch cmd {
        case "state": pet.debugForcedState = PetState(rawValue: arg)
        case "input": toggleInput()
        case "say": showReply(arg, session: nil, folder: nil, autoHide: nil)
        case "send": send(arg, newThread: false)
        case "hotkey": HotkeyAction(rawValue: arg).map { Hotkeys.shared.trigger($0) }
        case "click-bubble": bubble.click()
        case "settings": showSettings()
        case "snapshot": snapshot(to: URL(fileURLWithPath: arg))
        default: NSLog("Claude Buddy: unknown debug command \(cmd)")
        }
    }

    private func snapshot(to dir: URL) {
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        var info: [String: Any] = ["state": pet.state.rawValue, "frame": pet.debugFrameIndex,
                                   "thread": thread?.id ?? "", "lastReplied": lastReplied?.id ?? "",
                                   "hasAnimation": pet.view.sprite.animation(forKey: "frames") != nil]
        for (name, win) in [("pet", pet.panel as NSWindow?), ("bubble", bubble.window), ("input", input.window),
                            ("settings", settings?.window)] {
            guard let win else { continue }
            info[name] = NSStringFromRect(win.frame)
            if name == "pet", let img = pet.debugCurrentImage {
                write(NSBitmapImageRep(cgImage: img), to: dir.appendingPathComponent("pet.png"))
            } else if let v = win.contentView, let img = render(v) {
                write(NSBitmapImageRep(cgImage: img), to: dir.appendingPathComponent("\(name).png"))
            }
        }
        if let data = try? JSONSerialization.data(withJSONObject: info, options: [.prettyPrinted, .sortedKeys]) {
            try? data.write(to: dir.appendingPathComponent("state.json"))
        }
    }

    /// Renders a view's layer tree (cacheDisplay misses most modern controls).
    private func render(_ v: NSView) -> CGImage? {
        guard let layer = v.layer else { return nil }
        let scale = v.window?.backingScaleFactor ?? 2
        guard let ctx = CGContext(data: nil, width: Int(v.bounds.width * scale), height: Int(v.bounds.height * scale),
                                  bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        if v.window?.isOpaque ?? false {
            var bg = CGColor(gray: 0.5, alpha: 1)
            v.effectiveAppearance.performAsCurrentDrawingAppearance { bg = NSColor.windowBackgroundColor.cgColor }
            ctx.setFillColor(bg)
            ctx.fill(CGRect(x: 0, y: 0, width: ctx.width, height: ctx.height))
        }
        ctx.scaleBy(x: scale, y: scale)
        if !layer.isGeometryFlipped, v.isFlipped {
            ctx.translateBy(x: 0, y: v.bounds.height)
            ctx.scaleBy(x: 1, y: -1)
        }
        layer.render(in: ctx)
        return ctx.makeImage()
    }

    private func write(_ rep: NSBitmapImageRep, to url: URL) {
        try? rep.representation(using: .png, properties: [:])?.write(to: url)
    }
}

final class ClosureMenuItem: NSMenuItem {
    private let handler: () -> Void

    init(title: String, action handler: @escaping () -> Void) {
        self.handler = handler
        super.init(title: title, action: #selector(fire), keyEquivalent: "")
        target = self
    }

    required init(coder: NSCoder) { fatalError() }

    @objc private func fire() { handler() }
}
