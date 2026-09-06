import XCTest
@testable import EnhancedMediaPlayer

final class PlayerSeekPipelineTests: XCTestCase {
    func testFirstPressIsImmediateAndRepeatDoesNotCancelDecoder() {
        var p = PlayerSeekPipeline()
        XCTAssertEqual(p.request(delta: 5, position: 100, duration: 1000, generation: 0, now: 0), 105)
        for i in 1...10 { XCTAssertNil(p.request(delta: 5, position: 100, duration: 1000, generation: 0, now: Double(i) * 0.02)) }
        XCTAssertEqual(p.target, 155)
        XCTAssertEqual(p.observe(position: 105, generation: 1, buffering: false, now: 0.3), 155)
        XCTAssertNil(p.observe(position: 155, generation: 2, buffering: false, now: 0.5))
        XCTAssertNil(p.target)
    }
    func testBufferingAtRequestedTimestampIsNotCompletion() {
        var p = PlayerSeekPipeline()
        _ = p.request(delta: 5, position: 100, duration: 1000, generation: 0, now: 0)
        _ = p.request(delta: 5, position: 100, duration: 1000, generation: 0, now: 0.01)
        XCTAssertNil(p.observe(position: 105, generation: 1, buffering: true, now: 0.02))
        XCTAssertTrue(p.isSeeking)
        XCTAssertEqual(p.observe(position: 105, generation: 1, buffering: false, now: 0.1), 110)
    }
    func testOldGenerationCannotCompleteSeekEvenAtTarget() {
        var p = PlayerSeekPipeline()
        _ = p.request(delta: 0.1, position: 10, duration: 100, generation: 7, now: 0)
        XCTAssertNil(p.observe(position: 10.1, generation: 7, buffering: false, now: 0.1))
        XCTAssertNotNil(p.target)
        _ = p.observe(position: 10.1, generation: 8, buffering: false, now: 0.2)
        XCTAssertNil(p.target)
    }
    func testQueuedNetworkSeekCanAdvanceOnlyOnceAfterQuietPeriod() {
        var p = PlayerSeekPipeline()
        _ = p.request(delta: 5, position: 100, duration: 1000, generation: 0, now: 0)
        _ = p.request(delta: 5, position: 100, duration: 1000, generation: 1, now: 0.65)
        XCTAssertNil(p.advanceStalled(position: 105, generation: 1, now: 0.7))
        XCTAssertNil(p.advanceStalled(position: 105, generation: 1, now: 0.76))
        XCTAssertEqual(p.advanceStalled(position: 105, generation: 1, now: 0.9), 110)
        for i in 1...10 { XCTAssertNil(p.advanceStalled(position: 105, generation: 1, now: Double(i))) }
    }
    func testAbsoluteScrubReplacesQueuedKeyboardIntentWithoutLosingPause() {
        var p = PlayerSeekPipeline()
        _ = p.request(delta: 5, position: 100, duration: 1000, generation: 0, now: 0)
        _ = p.request(delta: 5, position: 100, duration: 1000, generation: 0, now: 0.01)
        XCTAssertNil(p.request(to: 500, position: 100, duration: 1000, generation: 0, now: 0.02))
        XCTAssertEqual(p.observe(position: 105, generation: 1, buffering: false, now: 0.2), 500)
    }
    func testResetDropsQueuedTargetsAndDefaultWindowSurvivesSettingsRoundTrip() throws {
        var p = PlayerSeekPipeline()
        _ = p.request(delta: 5, position: 100, duration: 1000, generation: 0, now: 0)
        _ = p.request(delta: 5, position: 100, duration: 1000, generation: 0, now: 0.02)
        p.reset()
        XCTAssertNil(p.observe(position: 105, generation: 1, buffering: false, now: 0.3))
        XCTAssertNil(p.target)
        var settings = PlayerPreferences(); settings.defaultPresentation = .detached
        let roundTrip = PlayerPreferences.decode(try JSONEncoder().encode(settings))
        XCTAssertEqual(roundTrip.defaultPresentation, .detached)
        XCTAssertEqual(PlayerPreferences.decode(Data("{}".utf8)).defaultPresentation, .gallery)
    }
}
