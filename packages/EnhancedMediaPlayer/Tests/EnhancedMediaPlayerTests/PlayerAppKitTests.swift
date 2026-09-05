#if canImport(AppKit)
import AppKit
import XCTest
@testable import EnhancedMediaPlayer

private final class MockPlayer: PlayerCommandTarget {
    let playerView = NSView(frame: NSRect(x: 0, y: 0, width: 800, height: 450))
    var playerSnapshot = PlayerSnapshot(position: 100, duration: 1000, volume: 0.8, rate: 1.25, playing: true)
    var playerPresentation = PlayerPresentation.detached
    var playerInputAllowed = true
    var actions: [PlayerAction] = []
    var seeks: [Double] = []
    var rateWrites: [(Double, Bool)] = []
    func playerPerform(_ action: PlayerAction) { actions.append(action) }
    func playerSeek(to timestamp: Double) { seeks.append(timestamp) }
    func playerSetVolume(_ volume: Double) { playerSnapshot.volume = volume }
    func playerSetRate(_ rate: Double, persist: Bool) { playerSnapshot.rate = rate; rateWrites.append((rate, persist)) }
    func playerCanHandleMouse(at point: NSPoint) -> Bool { true }
    func playerShowControls(_ show: Bool) {}
}
final class PlayerAppKitTests: XCTestCase {
    private var defaults: UserDefaults!
    private var suite: String!
    override func setUp() {
        _ = NSApplication.shared
        suite = "PlayerAppKitTests.\(UUID().uuidString)"; defaults = UserDefaults(suiteName: suite)!
    }
    override func tearDown() { defaults.removePersistentDomain(forName: suite) }
    private func controller(_ target: MockPlayer) -> PlayerInputController {
        let store = PlayerSettingsStore(defaults: defaults); store.update { $0.showOSD = false }
        return PlayerInputController(target: target, store: store)
    }
    func testTemporarySpeedRestoresActualPreviousSpeedWithoutPersisting() {
        let player = MockPlayer(); let input = controller(player)
        input.perform(.temporarySpeed); XCTAssertEqual(player.playerSnapshot.rate, 2)
        input.perform(.temporarySpeed); XCTAssertEqual(player.rateWrites.count, 1)
        input.endTemporarySpeed(); XCTAssertEqual(player.playerSnapshot.rate, 1.25)
        XCTAssertTrue(player.rateWrites.allSatisfy { !$0.1 })
    }
    func testDeactivationRestoresBoost() {
        let player = MockPlayer(); let input = controller(player)
        input.perform(.temporarySpeed); input.deactivate()
        XCTAssertEqual(player.playerSnapshot.rate, 1.25)
    }
    func testVolumeAndMuteRespectBoundsAndRestore() {
        let player = MockPlayer(); let input = controller(player)
        input.perform(.mute); XCTAssertEqual(player.playerSnapshot.volume, 0)
        input.perform(.mute); XCTAssertEqual(player.playerSnapshot.volume, 0.8)
        for _ in 0..<30 { input.perform(.volumeUp) }
        XCTAssertEqual(player.playerSnapshot.volume, 1)
        for _ in 0..<30 { input.perform(.volumeDown) }
        XCTAssertEqual(player.playerSnapshot.volume, 0)
    }
    func testRateCommandsRespectBackendLimits() {
        let player = MockPlayer(); let input = controller(player)
        for _ in 0..<50 { input.perform(.speedUp) }
        XCTAssertEqual(player.playerSnapshot.rate, 2.5)
        for _ in 0..<50 { input.perform(.speedDown) }
        XCTAssertEqual(player.playerSnapshot.rate, 0.25)
        input.perform(.resetSpeed); XCTAssertEqual(player.playerSnapshot.rate, 1)
    }
    func testRestrictedPlayerRejectsControlCommands() {
        let player = MockPlayer(); player.playerInputAllowed = false
        let input = controller(player)
        input.perform(.playPause); input.perform(.temporarySpeed); input.perform(.mute)
        XCTAssertTrue(player.actions.isEmpty); XCTAssertTrue(player.rateWrites.isEmpty)
        XCTAssertEqual(player.playerSnapshot.volume, 0.8)
    }
    func testRapidSeeksCommitOnlyLatestIntent() {
        let player = MockPlayer(); let input = controller(player)
        for _ in 0..<4 { input.perform(.seekForward) }
        let done = expectation(description: "coalesced seek")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { done.fulfill() }
        wait(for: [done], timeout: 1)
        XCTAssertEqual(player.seeks, [120])
    }
    func testDirectScrubCancelsOutstandingKeyboardSeek() {
        let player = MockPlayer(); let input = controller(player)
        input.perform(.seekForward); input.cancelPendingSeek()
        let done = expectation(description: "cancelled seek")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { done.fulfill() }
        wait(for: [done], timeout: 1); XCTAssertTrue(player.seeks.isEmpty)
    }
    func testSettingsWindowLaysOutAndRenders() throws {
        let controller = PlayerSettingsWindow(store: PlayerSettingsStore(defaults: defaults))
        let window = try XCTUnwrap(controller.window)
        let view = try XCTUnwrap(window.contentView)
        window.setContentSize(NSSize(width: 750, height: 660))
        view.layoutSubtreeIfNeeded()
        XCTAssertEqual(window.title, playerText("播放器设置", "Playback Settings"))
        XCTAssertFalse(view.hasAmbiguousLayout)
        if let path = ProcessInfo.processInfo.environment["PLAYER_UI_SNAPSHOT_DIR"] {
            try FileManager.default.createDirectory(atPath: path, withIntermediateDirectories: true)
            if let image = view.bitmapImageRepForCachingDisplay(in: view.bounds) {
                view.cacheDisplay(in: view.bounds, to: image)
                try image.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: path).appendingPathComponent("playback-settings.png"))
            }
        }
        window.close()
    }
}
#endif
