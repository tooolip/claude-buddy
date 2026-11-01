import AppKit
import Carbon.HIToolbox

/// A key combo. `char` is what the key types (used for display and menu key equivalents).
struct Shortcut: Codable, Equatable {
    var keyCode: UInt32
    var modifiers: UInt // NSEvent.ModifierFlags raw value
    var char: String

    var flags: NSEvent.ModifierFlags { NSEvent.ModifierFlags(rawValue: modifiers) }

    var carbonModifiers: UInt32 {
        var m: UInt32 = 0
        if flags.contains(.command) { m |= UInt32(cmdKey) }
        if flags.contains(.option) { m |= UInt32(optionKey) }
        if flags.contains(.control) { m |= UInt32(controlKey) }
        if flags.contains(.shift) { m |= UInt32(shiftKey) }
        return m
    }

    var description: String {
        var s = ""
        if flags.contains(.control) { s += "⌃" }
        if flags.contains(.option) { s += "⌥" }
        if flags.contains(.shift) { s += "⇧" }
        if flags.contains(.command) { s += "⌘" }
        return s + Self.keyName(keyCode: keyCode, char: char)
    }

    private static func keyName(keyCode: UInt32, char: String) -> String {
        switch Int(keyCode) {
        case kVK_Space: return "Space"
        case kVK_Return: return "↩"
        case kVK_Tab: return "⇥"
        case kVK_Escape: return "⎋"
        case kVK_Delete: return "⌫"
        case kVK_LeftArrow: return "←"
        case kVK_RightArrow: return "→"
        case kVK_UpArrow: return "↑"
        case kVK_DownArrow: return "↓"
        default: return fKeys[Int(keyCode)] ?? char.uppercased()
        }
    }

    static let fKeys: [Int: String] = [
        kVK_F1: "F1", kVK_F2: "F2", kVK_F3: "F3", kVK_F4: "F4", kVK_F5: "F5", kVK_F6: "F6", kVK_F7: "F7",
        kVK_F8: "F8", kVK_F9: "F9", kVK_F10: "F10", kVK_F11: "F11", kVK_F12: "F12", kVK_F13: "F13",
        kVK_F14: "F14", kVK_F15: "F15", kVK_F16: "F16", kVK_F17: "F17", kVK_F18: "F18", kVK_F19: "F19", kVK_F20: "F20",
    ]

    init(keyCode: Int, modifiers: NSEvent.ModifierFlags, char: String) {
        self.keyCode = UInt32(keyCode)
        self.modifiers = modifiers.intersection([.command, .option, .control, .shift]).rawValue
        self.char = char
    }
}

enum HotkeyAction: String, CaseIterable {
    case talk, openLast, newChat

    var defaultShortcut: Shortcut {
        switch self {
        case .talk: Shortcut(keyCode: kVK_Space, modifiers: [.control, .option], char: " ")
        case .openLast: Shortcut(keyCode: kVK_ANSI_L, modifiers: [.control, .option], char: "l")
        case .newChat: Shortcut(keyCode: kVK_ANSI_N, modifiers: [.control, .option], char: "n")
        }
    }
}

/// Global hotkeys via Carbon's RegisterEventHotKey, which needs no Accessibility permission.
final class Hotkeys {
    static let shared = Hotkeys()

    private var refs: [HotkeyAction: EventHotKeyRef] = [:]
    private var handlers: [HotkeyAction: () -> Void] = [:]
    private var handlerRef: EventHandlerRef?
    private var paused = false
    private static let signature = OSType(0x43426479) // 'CBdy'

    func shortcut(for action: HotkeyAction) -> Shortcut? {
        let key = "hotkey." + action.rawValue
        guard let data = UserDefaults.standard.data(forKey: key) else {
            return UserDefaults.standard.object(forKey: key) == nil ? action.defaultShortcut : nil
        }
        return try? JSONDecoder().decode(Shortcut.self, from: data)
    }

    /// nil clears the shortcut (stored, so the default doesn't come back).
    func setShortcut(_ shortcut: Shortcut?, for action: HotkeyAction) {
        let key = "hotkey." + action.rawValue
        if let shortcut, let data = try? JSONEncoder().encode(shortcut) {
            UserDefaults.standard.set(data, forKey: key)
        } else {
            UserDefaults.standard.set(false, forKey: key)
        }
        register(action)
    }

    func on(_ action: HotkeyAction, _ handler: @escaping () -> Void) {
        installHandlerIfNeeded()
        handlers[action] = handler
        register(action)
    }

    func trigger(_ action: HotkeyAction) { handlers[action]?() }

    /// While recording a new shortcut, the old ones shouldn't fire.
    func setPaused(_ p: Bool) {
        paused = p
        HotkeyAction.allCases.forEach(register)
    }

    private func register(_ action: HotkeyAction) {
        if let ref = refs.removeValue(forKey: action) { UnregisterEventHotKey(ref) }
        guard !paused, handlers[action] != nil, let s = shortcut(for: action) else { return }
        let id = EventHotKeyID(signature: Self.signature, id: UInt32(HotkeyAction.allCases.firstIndex(of: action)!))
        var ref: EventHotKeyRef?
        let status = RegisterEventHotKey(s.keyCode, s.carbonModifiers, id, GetApplicationEventTarget(), 0, &ref)
        if status == noErr, let ref { refs[action] = ref } else { NSLog("Claude Buddy: couldn't register \(s.description) (\(status))") }
    }

    private func installHandlerIfNeeded() {
        guard handlerRef == nil else { return }
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, event, _ -> OSStatus in
            var hk = EventHotKeyID()
            GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                              nil, MemoryLayout<EventHotKeyID>.size, nil, &hk)
            guard hk.signature == Hotkeys.signature, Int(hk.id) < HotkeyAction.allCases.count else { return noErr }
            let action = HotkeyAction.allCases[Int(hk.id)]
            DispatchQueue.main.async { Hotkeys.shared.handlers[action]?() }
            return noErr
        }, 1, &spec, nil, &handlerRef)
    }
}

/// Click, then press a combo. Esc cancels, Delete clears.
final class ShortcutRecorder: NSButton {
    private let action_: HotkeyAction
    private var monitor: Any?

    init(_ hotkey: HotkeyAction) {
        action_ = hotkey
        super.init(frame: .zero)
        bezelStyle = .rounded
        target = self
        action = #selector(toggleRecording)
        widthAnchor.constraint(greaterThanOrEqualToConstant: 150).isActive = true
        updateTitle()
    }

    required init?(coder: NSCoder) { fatalError() }

    private func updateTitle() {
        title = monitor != nil ? "Type shortcut…" : (Hotkeys.shared.shortcut(for: action_)?.description ?? "None")
    }

    @objc private func toggleRecording() {
        monitor == nil ? start() : stop()
    }

    private func start() {
        Hotkeys.shared.setPaused(true)
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] e in
            self?.record(e)
            return nil
        }
        updateTitle()
    }

    func stop() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        Hotkeys.shared.setPaused(false)
        updateTitle()
    }

    private func record(_ e: NSEvent) {
        let mods = e.modifierFlags.intersection([.command, .option, .control, .shift])
        switch Int(e.keyCode) {
        case kVK_Escape where mods.isEmpty:
            stop()
        case kVK_Delete where mods.isEmpty, kVK_ForwardDelete where mods.isEmpty:
            Hotkeys.shared.setShortcut(nil, for: action_)
            stop()
        default:
            let isFKey = Shortcut.fKeys[Int(e.keyCode)] != nil
            guard isFKey || !mods.intersection([.command, .option, .control]).isEmpty else { NSSound.beep(); return }
            let char = e.charactersIgnoringModifiers ?? ""
            Hotkeys.shared.setShortcut(Shortcut(keyCode: Int(e.keyCode), modifiers: mods, char: char), for: action_)
            stop()
        }
    }

    override func viewWillMove(toWindow newWindow: NSWindow?) {
        if newWindow == nil, monitor != nil { stop() }
        super.viewWillMove(toWindow: newWindow)
    }
}
