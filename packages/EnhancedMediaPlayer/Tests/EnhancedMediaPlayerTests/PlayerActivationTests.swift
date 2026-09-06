#if canImport(AppKit)
import AppKit
import XCTest
@testable import EnhancedMediaPlayer

private final class ActivationTarget: PlayerCommandTarget {
    let playerView = NSView(frame: NSRect(x: 0, y: 0, width: 640, height: 360))
    var playerSnapshot = PlayerSnapshot(position: 10, duration: 100, volume: 0.5, rate: 1.5, playing: true)
    var playerPresentation = PlayerPresentation.gallery
    var playerInputAllowed = true
    func playerPerform(_ action: PlayerAction) {}
    func playerSeek(to timestamp: Double) {}
    func playerSetVolume(_ volume: Double) { playerSnapshot.volume = volume }
    func playerSetRate(_ rate: Double, persist: Bool) { playerSnapshot.rate = rate }
    func playerCanHandleMouse(at point: NSPoint) -> Bool { true }
    func playerShowControls(_ show: Bool) {}
}
final class PlayerActivationTests: XCTestCase {
    func testPreloadedPlayersStayInactiveUntilPresentedAndDeactivateRestoresRate() throws {
        _ = NSApplication.shared
        let suite = "PlayerActivationTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = PlayerSettingsStore(defaults: defaults)
        store.update { $0.showOSD = false }
        let target = ActivationTarget()
        let controller = PlayerInputController(target: target, store: store)
        XCTAssertFalse(controller.isActive)
        controller.activate()
        XCTAssertTrue(controller.isActive)
        controller.perform(.temporarySpeed)
        XCTAssertEqual(target.playerSnapshot.rate, 2)
        controller.deactivate()
        XCTAssertFalse(controller.isActive)
        XCTAssertEqual(target.playerSnapshot.rate, 1.5)
        controller.activate()
        XCTAssertTrue(controller.isActive)
        controller.deactivate()
    }
}
#endif
