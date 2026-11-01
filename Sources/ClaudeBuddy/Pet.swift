import AppKit
import QuartzCore

/// Borderless, transparent, never takes focus, floats on every Space.
final class PetPanel: NSPanel {
    init(size: NSSize) {
        super.init(contentRect: NSRect(origin: .zero, size: size),
                   styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary]
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

final class PetView: NSView {
    let sprite = CALayer()
    var onClick: (() -> Void)?
    var onRightClick: ((NSEvent) -> Void)?
    var onDragChanged: ((Bool) -> Void)?

    private var dragStartMouse = NSPoint.zero
    private var dragStartOrigin = NSPoint.zero
    private var dragging = false

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer = CALayer()
        sprite.frame = bounds
        sprite.contentsGravity = .resizeAspect
        sprite.actions = ["contents": NSNull(), "bounds": NSNull(), "position": NSNull()]
        layer?.addSublayer(sprite)
    }

    required init?(coder: NSCoder) { fatalError() }

    override func layout() {
        super.layout()
        sprite.frame = bounds
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func mouseDown(with event: NSEvent) {
        dragStartMouse = NSEvent.mouseLocation
        dragStartOrigin = window?.frame.origin ?? .zero
        dragging = false
    }

    override func mouseDragged(with event: NSEvent) {
        let p = NSEvent.mouseLocation
        let dx = p.x - dragStartMouse.x, dy = p.y - dragStartMouse.y
        if !dragging {
            guard hypot(dx, dy) > 3 else { return }
            dragging = true
            onDragChanged?(true)
        }
        window?.setFrameOrigin(NSPoint(x: dragStartOrigin.x + dx, y: dragStartOrigin.y + dy))
    }

    override func mouseUp(with event: NSEvent) {
        if dragging {
            dragging = false
            onDragChanged?(false)
        } else {
            onClick?()
        }
    }

    override func rightMouseDown(with event: NSEvent) { onRightClick?(event) }
}

/// Owns the pet window and decides which animation plays.
///
/// Frames are swapped by a discrete CAKeyframeAnimation on the sprite layer's contents, so the
/// render server does the ticking and this process isn't woken per frame. The animation is
/// removed entirely while the window is occluded.
final class Pet: NSObject {
    let panel: PetPanel
    let view: PetView
    private(set) var skin: Skin
    private(set) var state: PetState = .idle

    private var isDragging = false
    private var isAsleep = false
    private var talkingReasons = Set<String>()
    private var sleepTimer: Timer?
    private var burstTimer: Timer?

    var onMoved: (() -> Void)?

    init(skin: Skin) {
        self.skin = skin
        panel = PetPanel(size: skin.pointSize)
        view = PetView(frame: NSRect(origin: .zero, size: skin.pointSize))
        super.init()
        panel.contentView = view
        view.sprite.contentsScale = skin.scale
        view.onDragChanged = { [weak self] dragging in
            guard let self else { return }
            isDragging = dragging
            if !dragging {
                Prefs.petOrigin = panel.frame.origin
                onMoved?()
            }
            poke()
        }
        NotificationCenter.default.addObserver(self, selector: #selector(occlusionChanged),
                                               name: NSWindow.didChangeOcclusionStateNotification, object: panel)
        placeInitially()
        refresh(force: true)
        scheduleSleep()
    }

    func show() { panel.orderFrontRegardless() }

    func setSkin(_ newSkin: Skin) {
        skin = newSkin
        let origin = panel.frame.origin
        panel.setFrame(NSRect(origin: origin, size: newSkin.pointSize), display: true)
        view.sprite.contentsScale = newSkin.scale
        refresh(force: true)
    }

    /// Any activity: wakes the pet and restarts the sleep countdown.
    func poke() {
        if isAsleep { isAsleep = false }
        scheduleSleep()
        refresh()
    }

    func sleepNow() {
        sleepTimer?.invalidate()
        isAsleep = true
        refresh()
    }

    /// Talking plays while any reason is active (our own reply generating, other sessions working).
    func setTalking(_ on: Bool, reason: String) {
        if on { talkingReasons.insert(reason) } else { talkingReasons.remove(reason) }
        poke()
    }

    /// Talk for a moment, e.g. when a reply bubble pops up.
    func talkBurst(_ seconds: TimeInterval = 2.5) {
        burstTimer?.invalidate()
        setTalking(true, reason: "burst")
        burstTimer = Timer.scheduledTimer(withTimeInterval: seconds, repeats: false) { [weak self] _ in
            self?.setTalking(false, reason: "burst")
        }
    }

    func clearTalking(prefix: String) {
        talkingReasons = talkingReasons.filter { !$0.hasPrefix(prefix) }
        refresh()
    }

    var anchor: NSRect { panel.frame }

    // MARK: - Private

    // Debug helpers (see AppDelegate.debug).
    var debugForcedState: PetState? { didSet { refresh() } }

    var debugCurrentImage: CGImage? {
        let c = view.sprite.presentation()?.contents ?? view.sprite.contents
        return c.map { $0 as! CGImage }
    }

    var debugFrameIndex: Int {
        guard let img = debugCurrentImage else { return -1 }
        return skin.animation(for: state).frames.firstIndex { $0 === img } ?? -1
    }

    private var desiredState: PetState {
        if let debugForcedState { return debugForcedState }
        if isDragging { return .dragging }
        if !talkingReasons.isEmpty { return .talking }
        if isAsleep { return .sleeping }
        return .idle
    }

    private func refresh(force: Bool = false) {
        let next = desiredState
        guard force || next != state else { return }
        state = next
        play()
    }

    private func play() {
        let anim = skin.animation(for: state)
        let sprite = view.sprite
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        sprite.removeAnimation(forKey: "frames")
        sprite.contents = anim.frames.first
        if anim.frames.count > 1, panel.occlusionState.contains(.visible) {
            let a = CAKeyframeAnimation(keyPath: "contents")
            a.values = anim.frames
            a.calculationMode = .discrete
            a.duration = Double(anim.frames.count) / anim.fps
            a.repeatCount = .infinity
            a.isRemovedOnCompletion = false
            sprite.add(a, forKey: "frames")
        }
        CATransaction.commit()
    }

    @objc private func occlusionChanged() {
        if panel.occlusionState.contains(.visible) {
            play()
        } else {
            view.sprite.removeAnimation(forKey: "frames")
        }
    }

    private func scheduleSleep() {
        sleepTimer?.invalidate()
        sleepTimer = Timer.scheduledTimer(withTimeInterval: Prefs.sleepMinutes * 60, repeats: false) { [weak self] _ in
            guard let self, talkingReasons.isEmpty, !isDragging else { self?.scheduleSleep(); return }
            isAsleep = true
            refresh()
        }
        sleepTimer?.tolerance = 10
    }

    private func placeInitially() {
        let size = skin.pointSize
        if let saved = Prefs.petOrigin,
           NSScreen.screens.contains(where: { $0.visibleFrame.intersects(NSRect(origin: saved, size: size)) }) {
            panel.setFrameOrigin(saved)
            return
        }
        let vf = (NSScreen.main ?? NSScreen.screens[0]).visibleFrame
        panel.setFrameOrigin(NSPoint(x: vf.maxX - size.width - 40, y: vf.minY + 20))
    }
}
