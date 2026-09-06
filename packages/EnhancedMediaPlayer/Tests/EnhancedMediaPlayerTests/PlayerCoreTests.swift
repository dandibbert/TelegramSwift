import XCTest
@testable import EnhancedMediaPlayer

final class PlayerCoreTests: XCTestCase {
    func testDefaultsCoverEveryActionWithoutConflicts() {
        let p = PlayerPreferences()
        XCTAssertEqual(p.shortcuts.count, PlayerAction.allCases.count)
        XCTAssertEqual(Set(p.shortcuts.values).count, p.shortcuts.count)
        for a in PlayerAction.allCases { XCTAssertEqual(p.action(for: p.shortcuts[a.rawValue]!), a) }
    }
    func testArrowsIgnoreFnNumericPadAndCapsLockFlags() {
        let flags = UInt(1 << 21 | 1 << 23 | 1 << 16)
        XCTAssertEqual(PlayerShortcut(124, flags), PlayerShortcut(124))
        XCTAssertEqual(PlayerPreferences().action(for: .init(124, flags)), .seekForward)
    }
    func testModifiedArrowsRemainDistinct() {
        let p = PlayerPreferences()
        XCTAssertEqual(p.action(for: .init(124, PlayerShortcut.shift)), .largeForward)
        XCTAssertEqual(p.action(for: .init(124, PlayerShortcut.command)), .fineForward)
        XCTAssertEqual(p.action(for: .init(124, PlayerShortcut.option)), .next)
    }
    func testHyperKeyBindingIsSupported() {
        var p = PlayerPreferences()
        let shortcut = PlayerShortcut(17, PlayerShortcut.modifierMask)
        p.shortcuts[PlayerAction.pin.rawValue] = shortcut
        p.normalize()
        XCTAssertEqual(p.action(for: shortcut), .pin)
        XCTAssertEqual(shortcut.display, "⌃⌥⇧⌘T")
    }
    func testConflictExcludesTheActionBeingEdited() {
        let p = PlayerPreferences()
        XCTAssertNil(p.conflict(for: .init(49), except: .playPause))
        XCTAssertEqual(p.conflict(for: .init(49), except: .pin), .playPause)
    }
    func testReservedCombinationsRejected() {
        for code: UInt16 in [12, 48, 49] { XCTAssertTrue(PlayerShortcut(code, PlayerShortcut.command).isReserved) }
        XCTAssertFalse(PlayerShortcut(48).isReserved)
    }
    func testNormalizeDeduplicatesAndDropsUnknownAndReservedKeys() {
        var p = PlayerPreferences()
        p.shortcuts[PlayerAction.pin.rawValue] = .init(49)
        p.shortcuts[PlayerAction.detach.rawValue] = .init(12, PlayerShortcut.command)
        p.shortcuts["not-an-action"] = .init(56)
        p.normalize()
        XCTAssertNil(p.shortcuts["not-an-action"])
        XCTAssertNil(p.shortcuts[PlayerAction.pin.rawValue])
        XCTAssertNil(p.shortcuts[PlayerAction.detach.rawValue])
        XCTAssertEqual(p.action(for: .init(49)), .playPause)
    }
    func testNormalizationHandlesNaNInfinityAndBounds() {
        var p = PlayerPreferences()
        p.seekStep = -.infinity; p.fineSeekStep = -5; p.largeSeekStep = 99999
        p.speedStep = .nan; p.temporarySpeed = 999; p.volumeStep = 0; p.controlsHideDelay = .infinity
        p.normalize()
        XCTAssertEqual(p.seekStep, 5); XCTAssertEqual(p.fineSeekStep, 0.1)
        XCTAssertEqual(p.largeSeekStep, 3600); XCTAssertEqual(p.speedStep, 0.1)
        XCTAssertEqual(p.temporarySpeed, 2.5); XCTAssertEqual(p.volumeStep, 1)
        XCTAssertEqual(p.controlsHideDelay, 2.5)
    }
    func testPartialOlderSchemaMergesDefaults() {
        let p = PlayerPreferences.decode(Data("{\"seekStep\":7}".utf8))
        XCTAssertEqual(p.seekStep, 7); XCTAssertEqual(p.shortcuts.count, PlayerAction.allCases.count)
    }
    func testDeliberatelyClearedBindingsStayUnbound() {
        let p = PlayerPreferences.decode(Data("{\"shortcuts\":{}}".utf8))
        XCTAssertTrue(p.shortcuts.isEmpty)
    }
    func testMalformedSettingsFallBackSafely() {
        for text in ["not-json", "[]", "{\"seekStep\":\"NaN\"}"] {
            XCTAssertEqual(PlayerPreferences.decode(Data(text.utf8)), PlayerPreferences())
        }
    }
    func testSettingsRoundTripAndResetDoesNotTouchOtherKeys() throws {
        let suite = "PlayerCoreTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set("keep", forKey: "TelegramOtherSetting")
        let store = PlayerSettingsStore(defaults: defaults)
        store.update { $0.seekStep = 7.5; $0.shortcuts.removeValue(forKey: PlayerAction.pin.rawValue) }
        let loaded = PlayerSettingsStore(defaults: defaults)
        XCTAssertEqual(loaded.preferences.seekStep, 7.5)
        XCTAssertNil(loaded.preferences.shortcuts[PlayerAction.pin.rawValue])
        loaded.reset()
        XCTAssertEqual(loaded.preferences, PlayerPreferences())
        XCTAssertEqual(defaults.string(forKey: "TelegramOtherSetting"), "keep")
    }
    func testRapidSeekAccumulatesAgainstPendingPosition() {
        var s = PlayerSeekAccumulator()
        for n in 1...4 { XCTAssertEqual(s.add(5, position: 100, duration: 1000, now: Double(n) * 0.01), 100 + Double(n) * 5) }
        XCTAssertEqual(s.take(), 120); XCTAssertNil(s.take())
        XCTAssertEqual(s.add(5, position: 100, duration: 1000, now: 0.1), 125)
    }
    func testSeekClampsBothEndsAndCanReverseAtTheEnd() {
        var s = PlayerSeekAccumulator()
        XCTAssertEqual(s.add(-50, position: 10, duration: 100, now: 0), 0)
        XCTAssertEqual(s.add(1000, position: 10, duration: 100, now: 0.1), 100)
        XCTAssertEqual(s.add(-5, position: 10, duration: 100, now: 0.2), 95)
    }
    func testSeekRejectsInvalidMediaMetadata() {
        var s = PlayerSeekAccumulator()
        XCTAssertNil(s.add(5, position: 0, duration: 0, now: 0))
        XCTAssertNil(s.add(.nan, position: 0, duration: 100, now: 0))
        XCTAssertNil(s.add(5, position: .infinity, duration: 100, now: 0))
        XCTAssertNil(s.take())
    }
    func testNewSeekAfterLongIdleUsesActualPosition() {
        var s = PlayerSeekAccumulator()
        _ = s.add(5, position: 100, duration: 1000, now: 0); _ = s.take()
        XCTAssertEqual(s.add(5, position: 200, duration: 1000, now: 4), 205)
    }
    func testObservedLandingClearsPendingBase() {
        var s = PlayerSeekAccumulator()
        _ = s.add(5, position: 100, duration: 1000, now: 0); _ = s.take()
        s.observe(position: 105, now: 0.5)
        XCTAssertNil(s.target)
        XCTAssertEqual(s.add(5, position: 106, duration: 1000, now: 1), 111)
    }
    func testStatusDoesNotCancelUncommittedSeek() {
        var s = PlayerSeekAccumulator()
        _ = s.add(5, position: 100, duration: 1000, now: 0)
        s.observe(position: 105, now: 0.01)
        XCTAssertEqual(s.take(), 105)
    }
    func testDirectScrubResetsQueuedIntent() {
        var s = PlayerSeekAccumulator()
        _ = s.add(5, position: 100, duration: 1000, now: 0)
        s.reset(); XCTAssertNil(s.take())
        XCTAssertEqual(s.add(5, position: 500, duration: 1000, now: 0.5), 505)
    }
    func testToggleActionsDoNotAutoRepeat() {
        for a in [PlayerAction.playPause, .fullscreen, .pictureInPicture, .detach, .pin, .temporarySpeed] { XCTAssertFalse(a.repeats) }
        XCTAssertTrue(PlayerAction.seekForward.repeats); XCTAssertTrue(PlayerAction.volumeUp.repeats)
    }
    func testTimeFormattingHandlesLongAndInvalidVideos() {
        XCTAssertEqual(playerTimestamp(0), "0:00"); XCTAssertEqual(playerTimestamp(61.9), "1:01")
        XCTAssertEqual(playerTimestamp(3661), "1:01:01"); XCTAssertEqual(playerTimestamp(-1), "--:--")
        XCTAssertEqual(playerTimestamp(.infinity), "--:--"); XCTAssertEqual(playerTimestamp(.nan), "--:--")
    }
}
