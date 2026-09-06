import XCTest
@testable import EnhancedMediaPlayer

final class PlayerSmallSeekTests: XCTestCase {
    func testSmallForwardSeekDoesNotTreatStaleStatusAsLanding() throws {
        var seek = PlayerSeekAccumulator()
        _ = seek.add(0.1, position: 10, duration: 100, now: 0)
        _ = seek.take()
        seek.observe(position: 10, now: 0.1)
        XCTAssertEqual(try XCTUnwrap(seek.target), 10.1, accuracy: 0.000001)
        XCTAssertEqual(try XCTUnwrap(seek.add(0.1, position: 10, duration: 100, now: 0.2)), 10.2, accuracy: 0.000001)
    }
    func testSmallBackwardSeekDoesNotTreatStaleStatusAsLanding() throws {
        var seek = PlayerSeekAccumulator()
        _ = seek.add(-0.1, position: 10, duration: 100, now: 0)
        _ = seek.take()
        seek.observe(position: 10, now: 0.1)
        XCTAssertEqual(try XCTUnwrap(seek.target), 9.9, accuracy: 0.000001)
        XCTAssertEqual(try XCTUnwrap(seek.add(-0.1, position: 10, duration: 100, now: 0.2)), 9.8, accuracy: 0.000001)
    }
    func testOlderSmallSeekLandingDoesNotAcknowledgeNewerRequest() throws {
        var seek = PlayerSeekAccumulator()
        _ = seek.add(0.1, position: 10, duration: 100, now: 0)
        _ = seek.take()
        _ = seek.add(0.1, position: 10, duration: 100, now: 0.1)
        _ = seek.take()
        seek.observe(position: 10.1, now: 0.2)
        XCTAssertEqual(try XCTUnwrap(seek.target), 10.2, accuracy: 0.000001)
        seek.observe(position: 10.2, now: 0.3)
        XCTAssertNil(seek.target)
    }
}
