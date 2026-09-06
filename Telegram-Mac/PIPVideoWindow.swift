// Telegram's media session is reused across the gallery, detached window and PiP.
// No second decoder, export, URL bridge or global input monitor is created.
import Cocoa
import TGUIKit
import SwiftSignalKit
import TelegramMedia

enum PictureInPictureControlMode { case normal, pip }
protocol PictureInPictureControl {
    func pause()
    func play()
    func didEnter()
    func didExit()
    func isPlaying() -> Bool
    var view: NSView { get }
    var isPictureInPicture: Bool { get }
    func setMode(_ mode: PictureInPictureControlMode, animated: Bool)
}

private final class EnhancedMiniPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

private final class FloatingVideoSession: NSObject, NSWindowDelegate {
    let control: SVideoController
    let item: MGalleryItem
    let viewer: GalleryViewer
    private weak var contentDelegate: InteractionContentViewProtocol?
    private let interactions: ChatMediaLayoutParameters?
    private let type: GalleryAppearType
    private let sourceOrigin: NSPoint
    private var window: NSWindow?
    private(set) var presentation: PlayerPresentation
    var forcePaused = false
    private var transitioning = false
    private var pendingPresentation: PlayerPresentation?
    private var pendingReturn = false
    private var settingsObserver: NSObjectProtocol?
    private var screensObserver: NSObjectProtocol?
    private var mouseMonitor: Any?
    private let messageDisposable = MetaDisposable()
    private var saveWork: DispatchWorkItem?
    private var isChangingWindow = false
    private var lastPreferences: PlayerPreferences
    private(set) var pinned: Bool
    var isFullscreen: Bool { window?.styleMask.contains(.fullScreen) == true }

    init(control: SVideoController, item: MGalleryItem, viewer: GalleryViewer, origin: NSPoint,
         delegate: InteractionContentViewProtocol?, interactions: ChatMediaLayoutParameters?, type: GalleryAppearType) {
        self.control = control; self.item = item; self.viewer = viewer
        self.contentDelegate = delegate; self.interactions = interactions; self.type = type; self.sourceOrigin = origin
        self.presentation = control.enhancedInitialPresentation
        let p = PlayerSettingsStore.shared.preferences
        self.lastPreferences = p
        self.pinned = presentation == .mini ? p.miniOnTop : p.detachedOnTop
        super.init()
    }
    func start() {
        makeWindow()
        settingsObserver = NotificationCenter.default.addObserver(forName: PlayerSettingsStore.didChange, object: nil, queue: .main) { [weak self] _ in
            guard let self = self else { return }
            let p = PlayerSettingsStore.shared.preferences
            if self.presentation == .mini ? p.miniOnTop != self.lastPreferences.miniOnTop : p.detachedOnTop != self.lastPreferences.detachedOnTop {
                self.pinned = self.presentation == .mini ? p.miniOnTop : p.detachedOnTop
            }
            self.lastPreferences = p
            self.applyWindowPolicy()
        }
        screensObserver = NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in self?.keepOnScreen() }
        mouseMonitor = NSEvent.addLocalMonitorForEvents(matching: .leftMouseUp) { [weak self] event in
            if event.window === self?.window { self?.snapIfNeeded() }
            return event
        }
        // Keep the upstream privacy behavior: deleted/expired messages close PiP.
        if let message = item.entry.message {
            messageDisposable.set((item.context.account.postbox.messageView(message.id) |> deliverOnMainQueue).start(next: { [weak self] value in
                if value.message == nil { self?.close() }
            }))
        }
    }
    private func makeWindow() {
        isChangingWindow = true
        let previousScreen = window?.screen
        control.enhancedInput?.deactivate()
        control.view.removeFromSuperview()
        window?.delegate = nil
        (window as? Window)?.removeAllHandlers(for: control)
        window?.close()
        let screen = previousScreen ?? NSScreen.screens.first(where: { $0.frame.contains(sourceOrigin) }) ?? NSScreen.main
        let visible = screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1280, height: 800)
        let raw = item.notFittedSize
        let ratio = raw.width > 0 && raw.height > 0 ? raw.width / raw.height : 16.0 / 9.0
        let width: CGFloat = presentation == .mini ? 340 : min(900, visible.width * 0.75)
        let height = min(visible.height * 0.8, width / ratio)
        let size = NSSize(width: height * ratio, height: height)
        let rect = NSRect(x: visible.maxX - size.width - 24, y: visible.maxY - size.height - 40, width: size.width, height: size.height)
        let next: NSWindow
        if presentation == .mini {
            let panel = EnhancedMiniPanel(contentRect: rect, styleMask: [.borderless, .resizable, .nonactivatingPanel], backing: .buffered, defer: false)
            panel.hidesOnDeactivate = false; panel.isFloatingPanel = true
            panel.becomesKeyOnlyIfNeeded = false
            next = panel
        } else {
            let player = Window(contentRect: rect, styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
            player.name = "enhanced-video-player"
            player.title = playerText("视频", "Video")
            player.titleVisibility = .hidden
            player.titlebarAppearsTransparent = true
            player.styleMask.insert(.fullSizeContentView)
            next = player
        }
        next.isReleasedWhenClosed = false
        next.acceptsMouseMovedEvents = true
        next.isMovableByWindowBackground = true
        next.backgroundColor = presentation == .mini ? .clear : .black
        next.isOpaque = presentation != .mini
        next.hasShadow = true
        next.contentAspectRatio = NSSize(width: ratio, height: 1)
        next.contentMinSize = NSSize(width: max(160, 100 * ratio), height: max(100, 160 / ratio))
        next.delegate = self
        if #available(macOS 10.14, *) { next.appearance = NSAppearance(named: .darkAqua) }
        let root = View(frame: NSRect(origin: .zero, size: size))
        root.wantsLayer = true; root.layer?.backgroundColor = NSColor.black.cgColor
        if presentation == .mini { root.layer?.cornerRadius = 10; root.layer?.masksToBounds = true }
        next.contentView = root
        control.view.frame = root.bounds
        control.view.autoresizingMask = [.width, .height]
        root.addSubview(control.view)
        window = next
        if PlayerSettingsStore.shared.preferences.rememberWindow,
           let stored = UserDefaults.standard.string(forKey: frameKey) {
            let saved = NSRectFromString(stored)
            if [saved.minX, saved.minY, saved.width, saved.height].allSatisfy({ $0.isFinite }),
               saved.width >= 160, saved.height >= 100 { next.setFrame(saved, display: false) }
        }
        applyWindowPolicy()
        keepOnScreen()
        next.makeKeyAndOrderFront(nil)
        control.enhancedSetPresentation(presentation)
        control.view.frame = root.bounds
        control.genericView.updateLayout(size: root.bounds.size, transition: .immediate)
        control.playerShowControls(true)
        isChangingWindow = false
    }
    private var frameKey: String { "EnhancedMediaPlayer.window.\(presentation.rawValue).v1" }
    private func applyWindowPolicy() {
        guard let window = window else { return }
        let p = PlayerSettingsStore.shared.preferences
        window.level = isFullscreen ? .normal : (pinned ? .floating : .normal)
        if !isFullscreen && !transitioning {
            let all = presentation == .mini ? p.miniAllSpaces : p.detachedAllSpaces
            window.collectionBehavior = presentation == .mini ? [.fullScreenAuxiliary] : [.fullScreenPrimary]
            if all { window.collectionBehavior.insert(.canJoinAllSpaces) }
        }
    }
    func changePresentation(_ mode: PlayerPresentation) {
        guard mode != .gallery else { returnToGallery(); return }
        guard presentation != mode else { return }
        if isFullscreen || transitioning {
            pendingPresentation = mode
            if !transitioning { toggleFullscreen() }
            return
        }
        saveFrame()
        presentation = mode
        let p = PlayerSettingsStore.shared.preferences
        pinned = mode == .mini ? p.miniOnTop : p.detachedOnTop
        makeWindow()
    }
    func togglePin() {
        pinned.toggle(); applyWindowPolicy()
        control.enhancedInput?.show(pinned ? playerText("播放器已置顶", "Player pinned") : playerText("已取消置顶", "Player unpinned"))
    }
    func toggleFullscreen() {
        guard !transitioning else { return }
        if presentation == .mini { changePresentation(.detached) }
        window?.level = .normal
        if !isFullscreen { window?.collectionBehavior = [.fullScreenPrimary] }
        transitioning = true
        window?.toggleFullScreen(nil)
    }
    func returnToGallery() {
        if isFullscreen || transitioning {
            pendingReturn = true
            if !transitioning { toggleFullscreen() }
            return
        }
        let wasPlaying = control.isPlaying()
        releaseWindow()
        if floatingVideoSession === self { floatingVideoSession = nil }
        if let current = getGalleryViewer(), current !== viewer { closeGalleryViewer(false) }
        control.enhancedResumeOnGallery = wasPlaying
        control.enhancedSetPresentation(.gallery)
        showGalleryFromPip(item: item, gallery: viewer, delegate: contentDelegate, contentInteractions: interactions, type: type)
    }
    func close() {
        // Closing is synchronous, including during native fullscreen transitions.
        // Clear the delegate before closing so an obsolete session cannot later
        // clear a newer floating session in a delayed fullscreen callback.
        control.pause()
        releaseWindow()
        if floatingVideoSession === self { floatingVideoSession = nil }
        control.enhancedSetPresentation(.gallery)
        control.enhancedInput?.deactivate()
    }
    private func releaseWindow() {
        saveFrame(); saveWork?.cancel()
        control.enhancedInput?.deactivate()
        control.view.removeFromSuperview()
        (window as? Window)?.removeAllHandlers(for: control)
        window?.delegate = nil; window?.close(); window = nil
    }
    func windowShouldClose(_ sender: NSWindow) -> Bool { close(); return false }
    func windowWillEnterFullScreen(_ notification: Notification) { transitioning = true }
    func windowDidEnterFullScreen(_ notification: Notification) {
        transitioning = false
        control.genericView.set(isInFullScreen: true)
        if pendingReturn || pendingPresentation != nil { toggleFullscreen() }
    }
    func windowWillExitFullScreen(_ notification: Notification) { transitioning = true }
    func windowDidExitFullScreen(_ notification: Notification) {
        transitioning = false
        control.genericView.set(isInFullScreen: false)
        applyWindowPolicy()
        if pendingReturn { pendingReturn = false; returnToGallery() }
        else if let mode = pendingPresentation { pendingPresentation = nil; changePresentation(mode) }
    }
    func windowDidFailToEnterFullScreen(_ window: NSWindow) { transitioning = false; applyWindowPolicy() }
    func windowDidFailToExitFullScreen(_ window: NSWindow) { transitioning = false; applyWindowPolicy() }
    func windowDidMove(_ notification: Notification) { scheduleSave() }
    func windowDidResize(_ notification: Notification) {
        // Do not defer video geometry to the 300 ms window-state save timer.
        if let root = window?.contentView {
            control.view.frame = root.bounds
            control.genericView.updateLayout(size: root.bounds.size, transition: .immediate)
        }
        scheduleSave()
    }
    private func scheduleSave() {
        guard !isChangingWindow, !transitioning else { return }
        saveWork?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.saveFrame() }
        saveWork = work; DispatchQueue.main.asyncAfter(deadline: .now() + 0.3, execute: work)
    }
    private func saveFrame() {
        guard PlayerSettingsStore.shared.preferences.rememberWindow, let window = window,
              !isFullscreen, !transitioning else { return }
        UserDefaults.standard.set(NSStringFromRect(window.frame), forKey: frameKey)
    }
    private func keepOnScreen() {
        guard let window = window, !isFullscreen else { return }
        let screen = NSScreen.screens.first(where: { $0.visibleFrame.contains(NSPoint(x: window.frame.midX, y: window.frame.midY)) }) ?? NSScreen.main
        guard let visible = screen?.visibleFrame else { return }
        var frame = window.frame
        let scale = min(1, min(visible.width / frame.width, visible.height / frame.height))
        frame.size = NSSize(width: frame.width * scale, height: frame.height * scale)
        frame.origin.x = max(visible.minX, min(frame.minX, visible.maxX - frame.width))
        frame.origin.y = max(visible.minY, min(frame.minY, visible.maxY - frame.height))
        window.setFrame(frame, display: true)
    }
    private func snapIfNeeded() {
        guard presentation == .mini, PlayerSettingsStore.shared.preferences.snapToCorners,
              let window = window, let visible = window.screen?.visibleFrame else { return }
        var frame = window.frame
        if abs(frame.minX - visible.minX) < 32 { frame.origin.x = visible.minX + 12 }
        else if abs(frame.maxX - visible.maxX) < 32 { frame.origin.x = visible.maxX - frame.width - 12 }
        if abs(frame.minY - visible.minY) < 32 { frame.origin.y = visible.minY + 12 }
        else if abs(frame.maxY - visible.maxY) < 32 { frame.origin.y = visible.maxY - frame.height - 12 }
        if frame != window.frame { window.setFrame(frame, display: true, animate: true) }
        saveFrame()
    }
    deinit {
        messageDisposable.dispose(); saveWork?.cancel()
        if let observer = settingsObserver { NotificationCenter.default.removeObserver(observer) }
        if let observer = screensObserver { NotificationCenter.default.removeObserver(observer) }
        if let monitor = mouseMonitor { NSEvent.removeMonitor(monitor) }
        // Deliberately no pause here: presentation changes must never pause the session.
    }
}

private var floatingVideoSession: FloatingVideoSession?
var hasPictureInPicture: Bool { floatingVideoSession != nil }
var enhancedFloatingIsPinned: Bool { floatingVideoSession?.pinned == true }
var enhancedFloatingIsFullscreen: Bool { floatingVideoSession?.isFullscreen == true }
func showPipVideo(control: PictureInPictureControl, viewer: GalleryViewer, item: MGalleryItem, origin: NSPoint,
                  delegate: InteractionContentViewProtocol? = nil, contentInteractions: ChatMediaLayoutParameters? = nil, type: GalleryAppearType) {
    guard let video = control as? SVideoController else { return }
    closePipVideo()
    let session = FloatingVideoSession(control: video, item: item, viewer: viewer, origin: origin,
                                       delegate: delegate, interactions: contentInteractions, type: type)
    floatingVideoSession = session
    session.start()
}
func enhancedChangeFloatingPresentation(_ mode: PlayerPresentation) { floatingVideoSession?.changePresentation(mode) }
func enhancedToggleFloatingFullscreen() { floatingVideoSession?.toggleFullscreen() }
func enhancedToggleFloatingPin() { floatingVideoSession?.togglePin() }
func enhancedFloatingUserInteracted() { floatingVideoSession?.forcePaused = false }
func exitPictureInPicture() { floatingVideoSession?.returnToGallery() }
func closePipVideo() { floatingVideoSession?.close() }
func pausepip() {
    if let session = floatingVideoSession, session.control.isPlaying() {
        session.control.pause(); session.forcePaused = true
    }
}
func playPipIfNeeded() {
    if let session = floatingVideoSession, session.forcePaused {
        session.forcePaused = false
        if !session.control.isPlaying() { session.control.play() }
    }
}
