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
    func testRapidSeeksSubmitImmediatelyThenChaseOnlyLatestOnCompletion() {
        let player = MockPlayer(); let input = controller(player)
        input.perform(.seekForward)
        XCTAssertEqual(player.seeks, [105])
        for _ in 0..<3 { input.perform(.seekForward) }
        XCTAssertEqual(player.seeks, [105])
        input.observe(position: 105, generation: 1, buffering: true)
        XCTAssertEqual(player.seeks, [105])
        input.observe(position: 105, generation: 1, buffering: false)
        XCTAssertEqual(player.seeks, [105, 120])
        input.deactivate()
    }
    func testDeactivationDropsPendingButDoesNotPretendToUndoIssuedSeek() {
        let player = MockPlayer(); let input = controller(player)
        input.perform(.seekForward); input.perform(.seekForward)
        input.cancelPendingSeek()
        input.observe(position: 105, generation: 1, buffering: false)
        XCTAssertEqual(player.seeks, [105])
        XCTAssertNil(input.pendingSeekPosition)
    }
}
#endif
