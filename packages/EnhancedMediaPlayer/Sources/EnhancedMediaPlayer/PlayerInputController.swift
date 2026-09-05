#if canImport(AppKit)
import AppKit

public struct PlayerSnapshot {
    public var position: Double
    public var duration: Double
    public var volume: Double
    public var rate: Double
    public var playing: Bool
    public init(position: Double, duration: Double, volume: Double, rate: Double, playing: Bool) {
        self.position = position; self.duration = duration; self.volume = volume
        self.rate = rate; self.playing = playing
    }
}

public protocol PlayerCommandTarget: AnyObject {
    var playerView: NSView { get }
    var playerSnapshot: PlayerSnapshot { get }
    var playerPresentation: PlayerPresentation { get }
    var playerInputAllowed: Bool { get }
    func playerPerform(_ action: PlayerAction)
    func playerSeek(to timestamp: Double)
    func playerSetVolume(_ volume: Double)
    func playerSetRate(_ rate: Double, persist: Bool)
    func playerCanHandleMouse(at point: NSPoint) -> Bool
    func playerShowControls(_ show: Bool)
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
    private var seek = PlayerSeekAccumulator()
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
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .keyUp, .flagsChanged,
                                                              .scrollWheel, .leftMouseUp, .mouseMoved]) { [weak self] event in
            guard let self = self else { return event }
            return self.handle(event)
        }
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
    public func activate() { isActive = true }
    public func deactivate() {
        isActive = false
        endTemporarySpeed()
        seekWork?.cancel(); seekWork = nil; seek.reset()
        hideWork?.cancel(); hideWork = nil
        hud?.hide()
    }
    public func observe(position: Double) {
        seek.observe(position: position, now: ProcessInfo.processInfo.systemUptime)
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
            PlayerSettingsWindow.show()
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
        guard let destination = seek.add(delta, position: state.position, duration: state.duration,
                                         now: ProcessInfo.processInfo.systemUptime) else {
            show(playerText("正在载入视频", "Loading video")); return
        }
        show(String(format: "%+.3gs", destination - state.position),
             detail: "\(playerTimestamp(destination)) / \(playerTimestamp(state.duration))")
        // Leading window throttle, not an indefinitely postponed debounce: even
        // a held key commits at most every 70ms and always uses the latest target.
        if seekWork == nil {
            let work = DispatchWorkItem { [weak self] in
                guard let self = self else { return }
                self.seekWork = nil
                if let position = self.seek.take() { self.target?.playerSeek(to: position) }
            }
            seekWork = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.07, execute: work)
        }
    }
    private func eligible(_ event: NSEvent) -> Bool {
        guard let target = target, let window = target.playerView.window,
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

private final class PlayerHUD: NSView {
    private let titleLabel = NSTextField(labelWithString: "")
    private let detailLabel = NSTextField(labelWithString: "")
    private var dismiss: DispatchWorkItem?
    private var generation = 0
    init(in parent: NSView) {
        super.init(frame: .zero)
        wantsLayer = true
        layer?.backgroundColor = NSColor.black.withAlphaComponent(0.76).cgColor
        layer?.cornerRadius = 12
        layer?.borderWidth = 0.5
        layer?.borderColor = NSColor.white.withAlphaComponent(0.18).cgColor
        translatesAutoresizingMaskIntoConstraints = false
        titleLabel.font = .monospacedDigitSystemFont(ofSize: 20, weight: .medium)
        titleLabel.textColor = .white; titleLabel.alignment = .center
        detailLabel.font = .monospacedDigitSystemFont(ofSize: 11, weight: .regular)
        detailLabel.textColor = .white.withAlphaComponent(0.8); detailLabel.alignment = .center
        for label in [titleLabel, detailLabel] {
            label.translatesAutoresizingMaskIntoConstraints = false
            label.lineBreakMode = .byTruncatingTail
            addSubview(label)
        }
        parent.addSubview(self)
        let width = widthAnchor.constraint(equalToConstant: 290); width.priority = .defaultHigh
        NSLayoutConstraint.activate([
            centerXAnchor.constraint(equalTo: parent.centerXAnchor), topAnchor.constraint(equalTo: parent.topAnchor, constant: 16),
            width, widthAnchor.constraint(lessThanOrEqualTo: parent.widthAnchor, constant: -16),
            heightAnchor.constraint(equalToConstant: 66),
            titleLabel.topAnchor.constraint(equalTo: topAnchor, constant: 10),
            titleLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10), titleLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -10),
            detailLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 3),
            detailLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8), detailLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8)
        ])
        isHidden = true
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }
    override func hitTest(_ point: NSPoint) -> NSView? { return nil }
    func show(_ title: String, detail: String) {
        dismiss?.cancel(); generation += 1
        titleLabel.stringValue = title; detailLabel.stringValue = detail
        isHidden = false; alphaValue = 1
        let current = generation
        let work = DispatchWorkItem { [weak self] in
            guard let self = self else { return }
            NSAnimationContext.runAnimationGroup({ context in
                context.duration = 0.18; self.animator().alphaValue = 0
            }, completionHandler: { [weak self] in
                if self?.generation == current { self?.isHidden = true }
            })
        }
        dismiss = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.15, execute: work)
    }
    func hide() { generation += 1; dismiss?.cancel(); isHidden = true }
    deinit { dismiss?.cancel() }
}
#endif
