#if canImport(AppKit)
import AppKit
import XCTest
@testable import EnhancedMediaPlayer

private final class EventTarget: PlayerCommandTarget {
    let playerView = NSView(frame: NSRect(x: 0, y: 0, width: 800, height: 450))
    var playerSnapshot = PlayerSnapshot(position: 10, duration: 100, volume: 0.5, rate: 1, playing: true)
    var playerPresentation = PlayerPresentation.gallery
    var playerInputAllowed = true
    var allowsCanvas = true
    var actions: [PlayerAction] = []
    func playerPerform(_ action: PlayerAction) { actions.append(action) }
    func playerSeek(to timestamp: Double) {}
    func playerSetVolume(_ volume: Double) { playerSnapshot.volume = volume }
    func playerSetRate(_ rate: Double, persist: Bool) { playerSnapshot.rate = rate }
    func playerCanHandleMouse(at point: NSPoint) -> Bool { allowsCanvas }
    func playerShowControls(_ show: Bool) {}
}
final class PlayerEventRoutingTests: XCTestCase {
    private var window: NSWindow!
    private var target: EventTarget!
    private var input: PlayerInputController!
    private var store: PlayerSettingsStore!
    private var defaults: UserDefaults!
    private var suite: String!
    override func setUp() {
        _ = NSApplication.shared
        suite = "PlayerEventRoutingTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suite)!
        store = PlayerSettingsStore(defaults: defaults)
        store.update { $0.showOSD = false }
        target = EventTarget()
        window = NSWindow(contentRect: target.playerView.bounds, styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = target.playerView
        window.makeKeyAndOrderFront(nil)
        window.becomeKey()
        input = PlayerInputController(target: target, store: store)
        input.activate()
    }
    override func tearDown() {
        input.deactivate(); input = nil
        window.close(); window = nil
        target = nil
        defaults.removePersistentDomain(forName: suite)
    }
    private func click(_ count: Int, point: NSPoint = NSPoint(x: 400, y: 225)) throws -> NSEvent {
        try XCTUnwrap(NSEvent.mouseEvent(with: .leftMouseUp, location: point, modifierFlags: [],
                                        timestamp: ProcessInfo.processInfo.systemUptime,
                                        windowNumber: window.windowNumber, context: nil,
                                        eventNumber: count, clickCount: count, pressure: 0))
    }
    private func key(_ code: UInt16, flags: NSEvent.ModifierFlags = []) throws -> NSEvent {
        try XCTUnwrap(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: flags,
                                      timestamp: ProcessInfo.processInfo.systemUptime,
                                      windowNumber: window.windowNumber, context: nil,
                                      characters: "", charactersIgnoringModifiers: "", isARepeat: false, keyCode: code))
    }
    func testFirstCanvasClickCannotDismissGalleryBeforeDoubleClick() throws {
        XCTAssertTrue(window.isVisible)
        XCTAssertNil(input.handle(try click(1)))
        XCTAssertTrue(target.actions.isEmpty)
        XCTAssertNil(input.handle(try click(2)))
        XCTAssertEqual(target.actions, [.fullscreen])
    }
    func testDisabledDoubleClickPreservesOriginalCanvasBehavior() throws {
        store.update { $0.doubleClick = .none }
        XCTAssertNotNil(input.handle(try click(1)))
        XCTAssertNotNil(input.handle(try click(2)))
        XCTAssertTrue(target.actions.isEmpty)
    }
    func testControlsAndOutsideVideoAreNotConsumedAsCanvas() throws {
        target.allowsCanvas = false
        XCTAssertNotNil(input.handle(try click(1)))
        XCTAssertNotNil(input.handle(try click(2)))
        target.allowsCanvas = true
        XCTAssertNotNil(input.handle(try click(2, point: NSPoint(x: -20, y: -20))))
        XCTAssertTrue(target.actions.isEmpty)
    }
    func testInactiveCachedPlayerNeverConsumesInput() throws {
        input.deactivate()
        XCTAssertNotNil(input.handle(try click(2)))
        XCTAssertNotNil(input.handle(try key(49)))
        XCTAssertTrue(target.actions.isEmpty)
    }
    func testClearedEscapeCannotFallThroughToLegacyGalleryClose() throws {
        XCTAssertTrue(window.isKeyWindow)
        store.update { $0.shortcuts.removeValue(forKey: PlayerAction.escape.rawValue) }
        XCTAssertNil(input.handle(try key(53)))
        XCTAssertTrue(target.actions.isEmpty)
    }
    func testTextEditingRetainsArrowKeysAndSpace() throws {
        let editor = NSTextView(frame: NSRect(x: 0, y: 0, width: 200, height: 50))
        target.playerView.addSubview(editor)
        XCTAssertTrue(window.makeFirstResponder(editor))
        XCTAssertNotNil(input.handle(try key(123)))
        XCTAssertNotNil(input.handle(try key(49)))
        XCTAssertTrue(target.actions.isEmpty)
    }
    func testReboundActionConsumesExactlyOnce() throws {
        XCTAssertTrue(window.isKeyWindow)
        store.update { $0.shortcuts[PlayerAction.playPause.rawValue] = PlayerShortcut(40, PlayerShortcut.option) }
        XCTAssertNil(input.handle(try key(40, flags: .option)))
        XCTAssertEqual(target.actions, [.playPause])
    }
}
#endif
