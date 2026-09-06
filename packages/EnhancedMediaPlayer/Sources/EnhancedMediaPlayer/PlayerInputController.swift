#if canImport(AppKit)
import AppKit

public struct PlayerSnapshot {
    public var position: Double
    public var duration: Double
    public var volume: Double
    public var rate: Double
    public var playing: Bool
    public var seekGeneration: Int
    public init(position: Double, duration: Double, volume: Double, rate: Double, playing: Bool, seekGeneration: Int = 0) {
        self.position = position; self.duration = duration; self.volume = volume
        self.rate = rate; self.playing = playing; self.seekGeneration = seekGeneration
    }
}

public protocol PlayerCommandTarget: AnyObject {
    var playerView: NSView { get }
    var playerSnapshot: PlayerSnapshot { get }
    var playerPresentation: PlayerPresentation { get }
    var playerInputAllowed: Bool { get }
    var playerKeyboardAllowed: Bool { get }
    func playerPerform(_ action: PlayerAction)
    func playerPreviewSeek(to timestamp: Double)
    func playerSeek(to timestamp: Double)
    func playerSetVolume(_ volume: Double)
    func playerSetRate(_ rate: Double, persist: Bool)
    func playerCanHandleMouse(at point: NSPoint) -> Bool
    func playerShowControls(_ show: Bool)
}

public extension PlayerCommandTarget {
    var playerKeyboardAllowed: Bool { playerInputAllowed }
    func playerPreviewSeek(to timestamp: Double) {}
}

/// A window-local controller; it never installs a global keyboard monitor or
/// requests Accessibility/Input Monitoring permissions. Consumed events cannot
/// also reach Telegram's gallery navigation handlers.
public final class PlayerInputController: NSObject {
    private(set) var isActive = false
    private weak var target: PlayerCommandTarget?
    private let store: PlayerSettingsStore
    private var monitor: Any?
    private var observers: [NSObjectProtocol] = []
    private var hud: PlayerHUD?
    private var seek = PlayerSeekPipeline()
    private var seekWork: DispatchWorkItem?
    private var hideWork: DispatchWorkItem?
    private var originalRate: Double?
    private var heldKey: UInt16?
    private var rememberedVolume: Double = 0.8
    private var wheelRemainder: CGFloat = 0
    private var lastWheelTime: TimeInterval = 0
    private var wheelMode: PlayerScrollAction?

    public init(target: PlayerCommandTarget, store: PlayerSettingsStore = .shared) {
        self.target = target; self.store = store
        super.init()
        observers.append(NotificationCenter.default.addObserver(forName: NSApplication.didResignActiveNotification,
            object: nil, queue: .main) { [weak self] _ in self?.endTemporarySpeed() })
        observers.append(NotificationCenter.default.addObserver(forName: NSWindow.didResignKeyNotification,
            object: nil, queue: .main) { [weak self] notification in
                if let window = notification.object as? NSWindow, window === self?.target?.playerView.window {
                    self?.endTemporarySpeed()
                }
            })
        observers.append(NotificationCenter.default.addObserver(forName: PlayerSettingsStore.didChange,
            object: store, queue: .main) { [weak self] _ in
                self?.endTemporarySpeed()
                self?.seekWork?.cancel(); self?.seekWork = nil; self?.seek.reset()
            })
    }
    deinit {
        if let monitor = monitor { NSEvent.removeMonitor(monitor) }
        observers.forEach { NotificationCenter.default.removeObserver($0) }
        seekWork?.cancel(); hideWork?.cancel()
        // The owning adapter explicitly deactivates before releasing the player.
    }
    public func activate() {
        isActive = true
        if monitor == nil {
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .keyUp, .flagsChanged,
                                                              .scrollWheel, .leftMouseUp, .mouseMoved]) { [weak self] event in
            guard let self = self else { return event }
            return self.handle(event)
        }
        }
    }
    public func deactivate() {
        isActive = false
        if let monitor = monitor { NSEvent.removeMonitor(monitor); self.monitor = nil }
        endTemporarySpeed()
        seekWork?.cancel(); seekWork = nil; seek.reset()
        hideWork?.cancel(); hideWork = nil
        hud?.hide()
    }
    public var pendingSeekPosition: Double? { seek.target }
    public func observe(position: Double, generation: Int = 0, buffering: Bool = false) {
        if let next = seek.observe(position: position, generation: generation, buffering: buffering,
                                   now: ProcessInfo.processInfo.systemUptime) {
            target?.playerSeek(to: next)
        }
        if !seek.hasQueuedTarget { seekWork?.cancel(); seekWork = nil }
    }
    /// Call when the timeline itself is dragged, so pending keyboard seeks cannot
    /// overwrite a subsequent direct user scrub.
    public func cancelPendingSeek() {
        seekWork?.cancel(); seekWork = nil; seek.reset()
    }
    public func show(_ title: String, detail: String = "") {
        guard store.preferences.showOSD, let view = target?.playerView else { return }
        if hud == nil { hud = PlayerHUD(in: view) }
        hud?.show(title, detail: detail)
    }
    public func perform(_ action: PlayerAction) {
        guard let target = target else { return }
        if action == .settings {
            endTemporarySpeed()
            target.playerPerform(.settings)
            return
        }
        guard target.playerInputAllowed else { return }
        let p = store.preferences
        let state = target.playerSnapshot
        switch action {
        case .seekBackward: requestSeek(-p.seekStep)
        case .seekForward: requestSeek(p.seekStep)
        case .fineBackward: requestSeek(-p.fineSeekStep)
        case .fineForward: requestSeek(p.fineSeekStep)
        case .largeBackward: requestSeek(-p.largeSeekStep)
        case .largeForward: requestSeek(p.largeSeekStep)
        case .volumeDown: changeVolume(state.volume - p.volumeStep / 100)
        case .volumeUp: changeVolume(state.volume + p.volumeStep / 100)
        case .mute:
            if state.volume > 0 { rememberedVolume = state.volume; changeVolume(0) }
            else { changeVolume(rememberedVolume) }
        case .speedDown: setSpeed(state.rate - p.speedStep)
        case .speedUp: setSpeed(state.rate + p.speedStep)
        case .resetSpeed: setSpeed(1)
        case .temporarySpeed:
            if originalRate == nil {
                originalRate = state.rate
                target.playerSetRate(p.temporarySpeed, persist: false)
                show(String(format: "%.2g×", p.temporarySpeed), detail: playerText("松开恢复原速", "Release to restore speed"))
            }
        case .playPause:
            target.playerPerform(action)
            show(state.playing ? playerText("暂停", "Paused") : playerText("播放", "Playing"))
        default:
            endTemporarySpeed()
            target.playerPerform(action)
        }
    }
    private func setSpeed(_ rate: Double) {
        guard rate.isFinite else { return }
        endTemporarySpeed()
        let value = min(2.5, max(0.25, (rate * 100).rounded() / 100))
        target?.playerSetRate(value, persist: true)
        show(String(format: "%.2g×", value))
    }
    private func changeVolume(_ volume: Double) {
        guard volume.isFinite else { return }
        let value = min(1, max(0, volume))
        target?.playerSetVolume(value)
        show(value == 0 ? playerText("静音", "Muted") : String(format: "%.0f%%", value * 100),
             detail: playerText("音量", "Volume"))
    }
    public func endTemporarySpeed() {
        if let rate = originalRate { target?.playerSetRate(rate, persist: false) }
        originalRate = nil; heldKey = nil
    }
    private func requestSeek(_ delta: Double) {
        guard let target = target else { return }
        let state = target.playerSnapshot
        let next = seek.request(delta: delta, position: state.position, duration: state.duration,
                                generation: state.seekGeneration, now: ProcessInfo.processInfo.systemUptime)
        updateSeekFeedback(state: state)
        // Do not queue the first input behind a timer.
        if let next = next { target.playerSeek(to: next) }
        scheduleSeekWatchdog()
    }
    public func seek(to position: Double) {
        guard let target = target, target.playerInputAllowed else { return }
        let state = target.playerSnapshot
        let next = seek.request(to: position, position: state.position, duration: state.duration,
                                generation: state.seekGeneration, now: ProcessInfo.processInfo.systemUptime)
        updateSeekFeedback(state: state)
        if let next = next { target.playerSeek(to: next) }
        scheduleSeekWatchdog()
    }
    private func updateSeekFeedback(state: PlayerSnapshot) {
        guard let destination = seek.target else { return }
        target?.playerPreviewSeek(to: destination)
        show(String(format: "%+.3g s", destination - state.position),
             detail: "\(playerTimestamp(destination)) / \(playerTimestamp(state.duration))")
    }
    private func scheduleSeekWatchdog() {
        guard seek.hasQueuedTarget, seekWork == nil else { return }
        let work = DispatchWorkItem { [weak self] in
            guard let self = self, let target = self.target else { return }
            self.seekWork = nil
            let state = target.playerSnapshot
            if let next = self.seek.advanceStalled(position: state.position, generation: state.seekGeneration,
                                                    now: ProcessInfo.processInfo.systemUptime) {
                target.playerSeek(to: next)
            }
            // No repeated seeks to an unchanged target. Polling here only checks
            // for a newer intent that can release an obsolete network request.
            self.scheduleSeekWatchdog()
        }
        seekWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2, execute: work)
    }
    private func eligible(_ event: NSEvent) -> Bool {
        guard let target = target, target.playerKeyboardAllowed, let window = target.playerView.window,
              event.window === window, window.isVisible, !target.playerView.isHiddenOrHasHiddenAncestor,
              window.attachedSheet == nil, NSApp.modalWindow == nil else { return false }
        if event.type == .keyDown {
            guard window.isKeyWindow else { return false }
            if window.firstResponder is NSTextView || window.firstResponder is NSTextField { return false }
        }
        return true
    }
    // Internal so integration tests exercise real event routing, not just commands.
    func handle(_ event: NSEvent) -> NSEvent? {
        if event.type == .keyUp, event.keyCode == heldKey { endTemporarySpeed(); return nil }
        if event.type == .flagsChanged, heldKey != nil {
            let expected = store.preferences.shortcuts[PlayerAction.temporarySpeed.rawValue]?.modifiers ?? 0
            if event.modifierFlags.rawValue & PlayerShortcut.modifierMask != expected { endTemporarySpeed() }
        }
        guard isActive, store.preferences.enabled, eligible(event), let target = target else { return event }
        if event.type == .keyDown {
            let shortcut = PlayerShortcut(event.keyCode, event.modifierFlags.rawValue)
            if let action = store.preferences.action(for: shortcut) {
                if event.isARepeat && !action.repeats { return nil }
                if action == .temporarySpeed { heldKey = event.keyCode }
                perform(action)
                return nil
            }
            // Unbinding/remapping must not silently uncover gallery's old keys.
            // This applies only to an active video, never to image galleries.
            if shortcut.modifiers == 0 && [UInt16(123),124,49,3,53].contains(shortcut.keyCode) { return nil }
            return event
        }
        if event.type == .mouseMoved, target.playerPresentation != .gallery {
            target.playerShowControls(true)
            hideWork?.cancel()
            let work = DispatchWorkItem { [weak self] in
                guard let self = self, let target = self.target, target.playerInputAllowed,
                      target.playerSnapshot.playing else { return }
                target.playerShowControls(false)
            }
            hideWork = work
            DispatchQueue.main.asyncAfter(deadline: .now() + store.preferences.controlsHideDelay, execute: work)
        }
        guard target.playerInputAllowed else { return event }
        let point = target.playerView.convert(event.locationInWindow, from: nil)
        guard target.playerView.bounds.contains(point), target.playerCanHandleMouse(at: point) else { return event }
        // The gallery normally closes on the FIRST mouse-up. Consume a canvas
        // click while double-click playback gestures are enabled, otherwise its
        // second click would target a gallery which has already disappeared.
        // Actual controls and clicks outside the video were excluded above.
        if event.type == .leftMouseUp, event.clickCount == 1,
           target.playerPresentation == .gallery, store.preferences.doubleClick != .none {
            target.playerShowControls(true)
            return nil
        }
        if event.type == .leftMouseUp, event.clickCount == 2 {
            switch store.preferences.doubleClick {
            case .fullscreen: perform(.fullscreen)
            case .playPause: perform(.playPause)
            case .regionalSeek:
                if point.x < target.playerView.bounds.width / 3 { perform(.seekBackward) }
                else if point.x > target.playerView.bounds.width * 2 / 3 { perform(.seekForward) }
                else { perform(.playPause) }
            case .none: return event
            }
            return nil
        }
        if event.type == .scrollWheel {
            let mode: PlayerScrollAction = event.modifierFlags.contains(.shift) ? .seek : store.preferences.scrollAction
            guard mode != .none else { return event }
            // Inertia must not keep changing playback after fingers leave the pad.
            guard event.momentumPhase == [] else { return nil }
            let now = ProcessInfo.processInfo.systemUptime
            if now - lastWheelTime > 0.3 || wheelMode != mode { wheelRemainder = 0 }
            lastWheelTime = now; wheelMode = mode
            let raw = abs(event.scrollingDeltaY) >= abs(event.scrollingDeltaX) ? event.scrollingDeltaY : event.scrollingDeltaX
            wheelRemainder += raw
            let threshold: CGFloat = event.hasPreciseScrollingDeltas ? 24 : 1
            let steps = max(-4, min(4, Int(wheelRemainder / threshold)))
            if steps != 0 {
                wheelRemainder -= CGFloat(steps) * threshold
                if mode == .seek { requestSeek(Double(steps) * store.preferences.seekStep) }
                else { changeVolume(target.playerSnapshot.volume + Double(steps) * store.preferences.volumeStep / 100) }
            }
            return nil
        }
        return event
    }
}

/// One directly drawn layer: no Auto Layout constraints in Telegram's
/// frame-driven video hierarchy, and no NSTextField sublayers hidden by video.
final class PlayerHUD: NSView {
    private var title = ""
    private var detail = ""
    private var dismiss: DispatchWorkItem?
    private var resizeObserver: NSObjectProtocol?
    init(in parent: NSView) {
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = 8
        layer?.backgroundColor = NSColor.black.withAlphaComponent(0.72).cgColor
        parent.addSubview(self)
        parent.postsFrameChangedNotifications = true
        resizeObserver = NotificationCenter.default.addObserver(forName: NSView.frameDidChangeNotification,
            object: parent, queue: .main) { [weak self] _ in self?.positionInParent() }
        isHidden = true
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }
    override var isFlipped: Bool { true }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
    private var titleAttributes: [NSAttributedString.Key: Any] {
        return [.font: NSFont.monospacedDigitSystemFont(ofSize: 15, weight: .medium), .foregroundColor: NSColor.white]
    }
    private var detailAttributes: [NSAttributedString.Key: Any] {
        return [.font: NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .regular), .foregroundColor: NSColor.white.withAlphaComponent(0.85)]
    }
    private func positionInParent() {
        guard let parent = superview else { return }
        let textWidth = max((title as NSString).size(withAttributes: titleAttributes).width,
                            (detail as NSString).size(withAttributes: detailAttributes).width)
        let width = min(max(96, ceil(textWidth) + 24), max(40, parent.bounds.width - 24))
        let height: CGFloat = detail.isEmpty ? 34 : 52
        let y: CGFloat = parent.isFlipped ? 16 : max(0, parent.bounds.height - height - 16)
        frame = NSRect(x: floor((parent.bounds.width - width) / 2), y: y, width: width, height: height)
        needsDisplay = true
    }
    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        let style = NSMutableParagraphStyle(); style.alignment = .center; style.lineBreakMode = .byTruncatingTail
        var attributes = titleAttributes; attributes[.paragraphStyle] = style
        (title as NSString).draw(in: NSRect(x: 10, y: 8, width: bounds.width - 20, height: 20), withAttributes: attributes)
        if !detail.isEmpty {
            var secondary = detailAttributes; secondary[.paragraphStyle] = style
            (detail as NSString).draw(in: NSRect(x: 10, y: 30, width: bounds.width - 20, height: 16), withAttributes: secondary)
        }
    }
    func show(_ title: String, detail: String) {
        dismiss?.cancel()
        self.title = title; self.detail = detail
        layer?.removeAllAnimations()
        isHidden = false; alphaValue = 1
        positionInParent()
        displayIfNeeded()
        let work = DispatchWorkItem { [weak self] in self?.isHidden = true }
        dismiss = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.15, execute: work)
    }
    func hide() { dismiss?.cancel(); isHidden = true }
    deinit {
        dismiss?.cancel()
        if let observer = resizeObserver { NotificationCenter.default.removeObserver(observer) }
    }
}

/// New forms must target their own field editor, not Telegram's main chat
/// window menu actions. This helper is used only while such a form is visible.
public enum PlayerTextEditing {
    public static func handle(_ event: NSEvent, in window: NSWindow) -> Bool {
        guard event.type == .keyDown, event.window === window,
              let editor = window.firstResponder as? NSTextView else { return false }
        let flags = event.modifierFlags.intersection([.command, .shift, .control, .option])
        guard flags == .command || flags == [.command, .shift] else { return false }
        if event.keyCode == 6 {
            if flags.contains(.shift) { editor.undoManager?.redo() } else { editor.undoManager?.undo() }
            return true
        }
        guard flags == .command else { return false }
        switch event.keyCode {
        case 0: editor.selectAll(nil)
        case 7: editor.cut(nil)
        case 8: editor.copy(nil)
        case 9: editor.paste(nil)
        default: return false
        }
        return true
    }
}
#endif
