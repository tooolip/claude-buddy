import AppKit

/// A panel that can take typing without activating the app, so whatever you were in stays frontmost.
private final class InputPanel: NSPanel {
    var onCommandReturn: (() -> Void)?

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if event.type == .keyDown, event.keyCode == 36 || event.keyCode == 76,
           event.modifierFlags.contains(.command) {
            onCommandReturn?()
            return true
        }
        return super.performKeyEquivalent(with: event)
    }
}

/// The little text box that pops up next to the pet.
final class InputBox: NSObject, NSTextFieldDelegate, NSWindowDelegate {
    private var panel: InputPanel?
    private var field: NSTextField?

    /// (text, startNewThread)
    var onSubmit: ((String, Bool) -> Void)?

    var isShown: Bool { panel != nil }
    var window: NSWindow? { panel }

    func show(pet: NSWindow, placeholder: String) {
        if let panel {
            panel.makeKeyAndOrderFront(nil)
            return
        }
        let size = NSSize(width: 330, height: 38)
        let screen = (pet.screen ?? NSScreen.main ?? NSScreen.screens[0]).visibleFrame
        let pf = pet.frame
        var x = pf.maxX + 4
        if x + size.width > screen.maxX { x = pf.minX - size.width - 4 }
        let y = min(max(pf.midY - size.height / 2, screen.minY + 4), screen.maxY - size.height - 4)

        let p = InputPanel(contentRect: NSRect(origin: NSPoint(x: x, y: y), size: size),
                           styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        p.isOpaque = false
        p.backgroundColor = .clear
        p.hasShadow = true
        p.level = .floating
        p.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary]
        p.isReleasedWhenClosed = false
        p.hidesOnDeactivate = false
        p.delegate = self
        p.onCommandReturn = { [weak self] in self?.submit(newThread: true) }

        let bg = NSVisualEffectView(frame: NSRect(origin: .zero, size: size))
        bg.material = .popover
        bg.state = .active
        bg.blendingMode = .behindWindow
        bg.maskImage = Self.roundedMask(radius: 10)

        let f = NSTextField(frame: NSRect(x: 12, y: 9, width: size.width - 24, height: 20))
        f.isBordered = false
        f.drawsBackground = false
        f.focusRingType = .none
        f.font = .systemFont(ofSize: 14)
        f.placeholderString = placeholder
        f.delegate = self
        f.cell?.isScrollable = true
        f.cell?.wraps = false
        bg.addSubview(f)
        p.contentView = bg

        pet.addChildWindow(p, ordered: .above)
        p.orderFrontRegardless()
        p.makeKey()
        p.makeFirstResponder(f)
        panel = p
        field = f
    }

    func hide() {
        guard let p = panel else { return }
        panel = nil
        field = nil
        p.delegate = nil
        p.parent?.removeChildWindow(p)
        p.orderOut(nil)
    }

    private func submit(newThread: Bool) {
        let text = field?.stringValue.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !text.isEmpty else { return }
        // Tear down after the current event finishes; the field editor is still mid-call.
        DispatchQueue.main.async { [weak self] in
            self?.hide()
            self?.onSubmit?(text, newThread)
        }
    }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy sel: Selector) -> Bool {
        switch sel {
        case #selector(NSResponder.insertNewline(_:)):
            submit(newThread: NSApp.currentEvent?.modifierFlags.contains(.command) ?? false)
            return true
        case #selector(NSResponder.cancelOperation(_:)):
            DispatchQueue.main.async { [weak self] in self?.hide() }
            return true
        default:
            return false
        }
    }

    func windowDidResignKey(_ notification: Notification) {
        // Clicked away with nothing typed: get out of the way.
        if field?.stringValue.isEmpty ?? true {
            DispatchQueue.main.async { [weak self] in self?.hide() }
        }
    }

    private static func roundedMask(radius: CGFloat) -> NSImage {
        let d = radius * 2 + 1
        let img = NSImage(size: NSSize(width: d, height: d), flipped: false) { r in
            NSColor.black.setFill()
            NSBezierPath(roundedRect: r, xRadius: radius, yRadius: radius).fill()
            return true
        }
        img.capInsets = NSEdgeInsets(top: radius, left: radius, bottom: radius, right: radius)
        img.resizingMode = .stretch
        return img
    }
}
