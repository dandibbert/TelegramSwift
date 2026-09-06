// Opt-in, account-free integration smoke test for the *built Telegram app*.
// It renders production TGUIKit settings and the real SVideoView/HUD/menu.
// The media source below is a deterministic fake, not a playback benchmark.
import Cocoa
import TGUIKit
import TelegramMedia
import TelegramMediaPlayer
import TelegramCore
import SwiftSignalKit
import RangeSet

private final class SmokeMediaView: View, UniversalVideoContentView {
    var duration: Double { 600 }
    var ready: Signal<Void, NoError> { .single(()) }
    var status: Signal<MediaPlayerStatus, NoError> { .single(MediaPlayerStatus(generationTimestamp: 0, duration: 600, dimensions: .zero, timestamp: 100, baseRate: 1, volume: 0.8, seekId: 0, status: .paused)) }
    var bufferingStatus: Signal<(RangeSet<Int64>, Int64)?, NoError> { .single(nil) }
    var fileRef: FileMediaReference { fatalError("Smoke media must never request a Telegram file") }
    func updateLayout(size: CGSize, transition: ContainedViewLayoutTransition) {}
    func play() {}
    func pause() {}
    func togglePlayPause() {}
    func setSoundEnabled(_ value: Bool) {}
    func setVolume(_ value: Float) {}
    func seek(_ timestamp: Double) {}
    func playOnceWithSound(playAndRecord: Bool, actionAtEnd: MediaPlayerActionAtEnd) {}
    func setSoundMuted(soundMuted: Bool) {}
    func setBaseRate(_ baseRate: Double) {}
    func setVideoQuality(_ videoQuality: UniversalVideoContentVideoQuality) {}
    func videoQualityState() -> (current: Int, preferred: UniversalVideoContentVideoQuality, available: [Int])? { (1080, .auto, [1080, 720, 480]) }
    func addPlaybackCompleted(_ f: @escaping () -> Void) -> Int { 0 }
    func removePlaybackCompleted(_ index: Int) {}
    func fetchControl(_ control: UniversalVideoNodeFetchControl) {}
    func setVideoLayerGravity(_ gravity: AVLayerVideoGravity) {}
}

private final class SmokePlayerTarget: PlayerCommandTarget {
    let view: SVideoView
    var playerView: NSView { view }
    var playerPresentation = PlayerPresentation.detached
    var playerInputAllowed: Bool { true }
    var playerKeyboardAllowed: Bool { !view.isInMenu && !contextMenuOnScreen() }
    var playerSnapshot = PlayerSnapshot(position: 100, duration: 600, volume: 0.8, rate: 1, playing: false)
    var actions: [PlayerAction] = []
    var seeks: [Double] = []
    init(view: SVideoView) { self.view = view }
    func playerPerform(_ action: PlayerAction) { actions.append(action) }
    func playerSeek(to timestamp: Double) { seeks.append(timestamp) }
    func playerPreviewSeek(to timestamp: Double) { view.status = view.status?.withUpdatedTimestamp(timestamp) }
    func playerSetVolume(_ volume: Double) { playerSnapshot.volume = volume }
    func playerSetRate(_ rate: Double, persist: Bool) { playerSnapshot.rate = rate }
    func playerCanHandleMouse(at point: NSPoint) -> Bool { view.enhancedCanHandleMouse(at: point) }
    func playerShowControls(_ show: Bool) { view.hideControls(!show, animated: false) }
}

enum PlayerAppSmoke {
    private static var runner: Runner?
    static func run(window: Window, directory: String) {
        runner = Runner(window: window, directory: directory)
        runner?.start()
    }
    private final class Runner {
        let window: Window
        let directory: URL
        let store: PlayerSettingsStore
        let defaults: UserDefaults
        let suite = "io.github.dandibbert.TelegramPlayer.smoke"
        var navigation: NavigationViewController?
        var target: SmokePlayerTarget?
        var input: PlayerInputController?
        var checks: [String] = []
        var frames: [String] = []
        init(window: Window, directory: String) {
            self.window = window; self.directory = URL(fileURLWithPath: directory, isDirectory: true)
            defaults = UserDefaults(suiteName: suite)!
            defaults.removePersistentDomain(forName: suite)
            store = PlayerSettingsStore(defaults: defaults)
        }
        func start() {
            do { try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true) }
            catch { fail("Cannot create smoke output") }
            setDefaultTheme(for: window)
            window.setContentSize(NSSize(width: 600, height: 680))
            window.makeKeyAndOrderFront(nil)
            showPage(.controls, name: "controls") {
                self.store.update { $0.defaultPresentation = .detached }
                self.check(self.store.preferences.defaultPresentation == .detached, "Default detached mode persists")
                self.showPage(.windows, name: "windows") {
                    self.showPage(.shortcuts, name: "shortcuts") {
                        telegramUpdateTheme(generateTheme(palette: darkPalette, cloudTheme: nil, bubbled: false, fontSize: 13, wallpaper: ThemeWallpaper()), window: self.window, animated: false)
                        self.showPage(.controls, name: "controls-dark") { self.showVideo() }
                    }
                }
            }
        }
        func showPage(_ page: PlayerSettingsPage, name: String, completion: @escaping() -> Void) {
            navigation?.viewDidDisappear(false)
            navigation?.view.removeFromSuperview()
            let controller = PlayerSettingsController(page: page, store: store)
            let nav = NavigationViewController(controller, window)
            nav._frameRect = window.contentView!.bounds
            nav.view.frame = window.contentView!.bounds
            nav.view.autoresizingMask = [.width, .height]
            window.contentView!.addSubview(nav.view)
            nav.viewDidAppear(false)
            navigation = nav
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) {
                self.check(controller.tableView.count > 3, "Production settings populated: " + name)
                self.snapshot(name, view: nav.view)
                completion()
            }
        }
        func showVideo() {
            navigation?.viewDidDisappear(false); navigation?.view.removeFromSuperview(); navigation = nil
            window.setContentSize(NSSize(width: 880, height: 495))
            let media = SmokeMediaView(frame: .zero)
            media.backgroundColor = NSColor(rgb: 0x18212b)
            let video = SVideoView(frame: window.contentView!.bounds, mediaPlayer: media)
            video.autoresizingMask = [.width, .height]
            window.contentView!.addSubview(video)
            let player = SmokePlayerTarget(view: video)
            target = player
            let input = PlayerInputController(target: player, store: store)
            self.input = input
            video.enhancedAction = { [weak input] action in input?.perform(action) }
            video.enhancedIsFloating = { true }
            video.enhancedIsPinned = { false }
            video.status = MediaPlayerStatus(generationTimestamp: 0, duration: 600, dimensions: NSSize(width: 1920, height: 1080), timestamp: 100, baseRate: 1, volume: 0.8, seekId: 0, status: .paused)
            video.enhancedRefreshSeekButtons()
            video.hideControls(false, animated: false)
            input.activate()
            input.perform(.seekForward)
            self.check(player.seeks == [105], "First seek dispatch is synchronous")
            for _ in 0..<8 { input.perform(.seekForward) }
            self.check(player.seeks == [105], "Repeats cannot cancel decoder seeks")
            input.observe(position: 105, generation: 1, buffering: true)
            self.check(player.seeks == [105], "Buffering is not completion")
            input.observe(position: 105, generation: 1, buffering: false)
            self.check(player.seeks == [105, 145], "Completion chases only latest target")
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                self.snapshot("detached-hud", view: video)
                video.setMode(.pip, animated: false)
                video.setFrameSize(NSSize(width: 340, height: 190))
                input.show("+15 s", detail: "02:25 / 10:00")
                self.snapshot("mini-hud", view: video)
                self.testMenu(video: video, player: player)
            }
        }
        func testMenu(video: SVideoView, player: SmokePlayerTarget) {
            video.setMode(.normal, animated: false)
            video.frame = window.contentView!.bounds
            guard let menu = video.enhancedMakeMenu() else { fail("Missing production player menu") }
            // Invoke real production menu callbacks while the popup is active.
            // These must not be blocked by the keyboard-only menu guard.
            let commands = Array(menu.contextItems.suffix(4))
            check(commands.count == 4, "Production menu has four player commands")
            check(commands.allSatisfy { !$0.title.contains("    ") }, "Shortcut labels use a separate trailing column")
            for item in commands {
                menu.onShow(menu)
                item.handler?()
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                self.check(player.actions == [.detach, .pictureInPicture, .pin, .settings], "All mouse menu callbacks dispatch exactly once")
                self.input?.deactivate()
                self.finish()
            }
        }
        func snapshot(_ name: String, view: NSView) {
            view.layoutSubtreeIfNeeded()
            guard let image = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { fail("Cannot capture " + name) }
            view.cacheDisplay(in: view.bounds, to: image)
            do {
                try image.representation(using: .png, properties: [:])!.write(to: directory.appendingPathComponent(name + ".png"))
                frames.append(name + ".png")
            } catch { fail("Cannot save " + name) }
        }
        func check(_ condition: Bool, _ description: String) {
            guard condition else { fail(description) }
            checks.append(description)
        }
        func fail(_ reason: String) -> Never {
            print("PLAYER_UI_SMOKE_FAILED: " + reason)
            exit(1)
        }
        func finish() {
            defaults.removePersistentDomain(forName: suite)
            let report: [String: Any] = ["passed": true, "checks": checks, "snapshots": frames,
                "coverage": "Production TGUIKit settings, SVideoView/HUD and menu callbacks; deterministic fake media. No account or real streaming playback."]
            do {
                let data = try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys])
                try data.write(to: directory.appendingPathComponent("result.json"))
            } catch { fail("Cannot save report") }
            print("PLAYER_UI_SMOKE_PASSED: \(checks.count) checks")
            exit(0)
        }
    }
}
