import AppKit

private let ink = NSColor(srgbRed: 0.24, green: 0.2, blue: 0.4, alpha: 1)

private final class BubbleView: NSView {
    static let font = NSFont.systemFont(ofSize: 13)
    static let maxTextWidth: CGFloat = 250
    static let maxLines = 4
    static let pad = NSSize(width: 12, height: 8)
    static let tail: CGFloat = 9

    var text = ""
    var tailX: CGFloat = 0
    var tailUp = false
    var clickable = true
    var onClick: (() -> Void)?
    var onDismiss: (() -> Void)?
    var onHover: ((Bool) -> Void)?

    static var attrs: [NSAttributedString.Key: Any] {
        let p = NSMutableParagraphStyle()
        p.lineBreakMode = .byWordWrapping
        return [.font: font, .foregroundColor: ink, .paragraphStyle: p]
    }

    static func size(for text: String) -> NSSize {
        let lineH = ceil(font.ascender - font.descender + font.leading)
        let r = (text as NSString).boundingRect(with: NSSize(width: maxTextWidth, height: 1000),
                                                options: [.usesLineFragmentOrigin], attributes: attrs)
        let h = min(ceil(r.height), lineH * CGFloat(maxLines))
        return NSSize(width: ceil(r.width) + pad.width * 2 + 2, height: h + pad.height * 2 + tail + 2)
    }

    override func updateTrackingAreas() {
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeAlways], owner: self))
    }

    override func mouseEntered(with event: NSEvent) { onHover?(true) }
    override func mouseExited(with event: NSEvent) { onHover?(false) }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func mouseUp(with event: NSEvent) { activate() }
    func activate() { clickable ? onClick?() : onDismiss?() }
    override func rightMouseDown(with event: NSEvent) { onDismiss?() }
    override func resetCursorRects() { if clickable { addCursorRect(bounds, cursor: .pointingHand) } }

    override func draw(_ dirtyRect: NSRect) {
        let t = Self.tail
        var body = bounds.insetBy(dx: 1, dy: 1)
        body.size.height -= t
        if !tailUp { body.origin.y += t }

        let path = NSBezierPath(roundedRect: body, xRadius: 12, yRadius: 12)
        let tx = min(max(tailX, body.minX + 16), body.maxX - 16)
        let tailPath = NSBezierPath()
        if tailUp {
            tailPath.move(to: NSPoint(x: tx - 7, y: body.maxY - 1))
            tailPath.line(to: NSPoint(x: tx + 2, y: bounds.maxY - 1))
            tailPath.line(to: NSPoint(x: tx + 7, y: body.maxY - 1))
        } else {
            tailPath.move(to: NSPoint(x: tx - 7, y: body.minY + 1))
            tailPath.line(to: NSPoint(x: tx + 2, y: bounds.minY + 1))
            tailPath.line(to: NSPoint(x: tx + 7, y: body.minY + 1))
        }
        path.append(tailPath)

        NSColor(white: 1, alpha: 0.97).setFill()
        path.fill()
        ink.setStroke()
        path.lineWidth = 2
        path.stroke()
        // Paint over the seam where the tail meets the body.
        NSColor.white.setFill()
        NSRect(x: tx - 5.5, y: tailUp ? body.maxY - 2 : body.minY - 1, width: 11, height: 3).fill()

        let textRect = body.insetBy(dx: Self.pad.width, dy: Self.pad.height)
        (text as NSString).draw(with: textRect, options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine],
                                attributes: Self.attrs)
    }
}

/// The speech blob. Lives as a child window of the pet so it follows drags.
final class Bubble {
    private var panel: NSPanel?
    private var hideTimer: Timer?
    private var hideAfter: TimeInterval?

    var isShown: Bool { panel != nil }
    var window: NSWindow? { panel }

    /// Same as clicking it.
    func click() { (panel?.contentView as? BubbleView)?.activate() }

    /// `autoHide` nil keeps it up until clicked or dismissed. `onClick` nil makes a click just dismiss.
    func show(_ text: String, pet: NSWindow, autoHide: TimeInterval?, onClick: (() -> Void)?) {
        hide()
        let size = BubbleView.size(for: text)
        let screen = (pet.screen ?? NSScreen.main ?? NSScreen.screens[0]).visibleFrame
        let petFrame = pet.frame

        var x = petFrame.midX - size.width / 2
        x = min(max(x, screen.minX + 4), screen.maxX - size.width - 4)
        var y = petFrame.maxY - 6
        let tailUp = y + size.height > screen.maxY
        if tailUp { y = petFrame.minY - size.height + 4 }

        let p = NSPanel(contentRect: NSRect(x: x, y: y, width: size.width, height: size.height),
                        styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        p.isOpaque = false
        p.backgroundColor = .clear
        p.hasShadow = true
        p.level = .floating
        p.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary]
        p.isReleasedWhenClosed = false
        p.hidesOnDeactivate = false

        let v = BubbleView(frame: NSRect(origin: .zero, size: size))
        v.text = text
        v.tailX = petFrame.midX - x
        v.tailUp = tailUp
        v.clickable = onClick != nil
        v.onClick = { [weak self] in
            self?.hide()
            onClick?()
        }
        v.onDismiss = { [weak self] in self?.hide() }
        v.onHover = { [weak self] inside in
            guard let self else { return }
            if inside { hideTimer?.invalidate() } else { scheduleHide() }
        }
        p.contentView = v
        pet.addChildWindow(p, ordered: .above)
        p.orderFrontRegardless()
        panel = p
        hideAfter = autoHide
        scheduleHide()
    }

    func hide() {
        hideTimer?.invalidate()
        guard let p = panel else { return }
        panel = nil
        p.parent?.removeChildWindow(p)
        p.orderOut(nil)
    }

    private func scheduleHide() {
        hideTimer?.invalidate()
        guard let after = hideAfter else { return }
        hideTimer = Timer.scheduledTimer(withTimeInterval: after, repeats: false) { [weak self] _ in self?.hide() }
    }
}
