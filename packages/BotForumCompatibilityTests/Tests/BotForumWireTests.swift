import XCTest
import TelegramApi

final class BotForumWireTests: XCTestCase {
    let user = Api.InputPeer.inputPeerUser(userId: 123456, accessHash: 987654)
    func testBotRequestsUsePeerBasedMethods() {
        XCTAssertEqual(BufferReader(Api.functions.channels.getForumTopics(flags: 0, channel: user, q: nil, offsetDate: 0, offsetId: 0, offsetTopic: 0, limit: 20).1).readInt32(), 1000635391)
        XCTAssertEqual(BufferReader(Api.functions.channels.getForumTopicsByID(channel: user, topics: [7]).1).readInt32(), -1358280184)
        XCTAssertEqual(BufferReader(Api.functions.channels.createForumTopic(flags: 1, channel: user, title: "Work", iconColor: 0x6fb9f0, iconEmojiId: nil, randomId: 17, sendAs: nil).1).readInt32(), 798540757)
        XCTAssertEqual(BufferReader(Api.functions.channels.editForumTopic(flags: 1, channel: user, topicId: 7, title: "New name", iconEmojiId: nil, closed: nil, hidden: nil).1).readInt32(), -825487052)
        XCTAssertEqual(BufferReader(Api.functions.channels.updatePinnedForumTopic(channel: user, topicId: 7, pinned: .boolTrue).1).readInt32(), 392032849)
        XCTAssertEqual(BufferReader(Api.functions.channels.reorderPinnedForumTopics(flags: 1, channel: user, order: [7]).1).readInt32(), 242762224)
        XCTAssertEqual(BufferReader(Api.functions.channels.deleteTopicHistory(channel: user, topMsgId: 7).1).readInt32(), -763269360)
    }
    func testInputPeerUserIsSerializedNotInputChannel() {
        let reader = BufferReader(Api.functions.channels.getForumTopics(flags: 0, channel: user, q: nil, offsetDate: 1, offsetId: 2, offsetTopic: 3, limit: 20).1)
        XCTAssertEqual(reader.readInt32(), 1000635391)
        XCTAssertEqual(reader.readInt32(), 0)
        let expected = Buffer(); user.serialize(expected, true)
        XCTAssertEqual(reader.readInt32(), BufferReader(expected).readInt32())
        XCTAssertEqual(reader.readInt64(), 123456)
        XCTAssertEqual(reader.readInt64(), 987654)
        XCTAssertEqual(reader.readInt32(), 1)
        XCTAssertEqual(reader.readInt32(), 2)
        XCTAssertEqual(reader.readInt32(), 3)
        XCTAssertEqual(reader.readInt32(), 20)
        XCTAssertNil(reader.readInt32())
    }
    func testChannelRequestsRemainWireCompatible() {
        let channel = Api.InputChannel.inputChannel(channelId: 99, accessHash: 111)
        let peer = Api.InputPeer.inputPeerChannel(channelId: 99, accessHash: 111)
        XCTAssertEqual(Api.functions.channels.getForumTopics(flags: 0, channel: peer, q: nil, offsetDate: 0, offsetId: 0, offsetTopic: 0, limit: 20).1.makeData(), Api.functions.channels.getForumTopics(flags: 0, channel: channel, q: nil, offsetDate: 0, offsetId: 0, offsetTopic: 0, limit: 20).1.makeData())
        XCTAssertEqual(Api.functions.channels.getForumTopicsByID(channel: peer, topics: [7]).1.makeData(), Api.functions.channels.getForumTopicsByID(channel: channel, topics: [7]).1.makeData())
        XCTAssertEqual(Api.functions.channels.createForumTopic(flags: 1, channel: peer, title: "A", iconColor: 1, iconEmojiId: nil, randomId: 42, sendAs: nil).1.makeData(), Api.functions.channels.createForumTopic(flags: 1, channel: channel, title: "A", iconColor: 1, iconEmojiId: nil, randomId: 42, sendAs: nil).1.makeData())
        XCTAssertEqual(Api.functions.channels.deleteTopicHistory(channel: peer, topMsgId: 7).1.makeData(), Api.functions.channels.deleteTopicHistory(channel: channel, topMsgId: 7).1.makeData())
    }
    func testBothUserConstructorsPreserveBotForumFlags() {
        for constructor: Int32 in [34280482, 829899656] {
            let buffer = Buffer()
            buffer.appendInt32(constructor); buffer.appendInt32(1 << 14)
            buffer.appendInt32((1 << 16) | (1 << 17)); buffer.appendInt64(123456); buffer.appendInt32(1)
            guard let result = Api.parse(buffer) as? Api.User,
                  case let .user(_, flags2, id, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _) = result else { return XCTFail("Cannot parse bot user") }
            XCTAssertEqual(id, 123456)
            XCTAssertEqual(flags2 & (1 << 16), 1 << 16)
            XCTAssertEqual(flags2 & (1 << 17), 1 << 17)
        }
    }
    func testNewUserRecentStoryIsConsumedWithoutCorruptingFollowingFields() {
        let buffer = Buffer()
        buffer.appendInt32(829899656); buffer.appendInt32(1 << 14)
        buffer.appendInt32((1 << 5) | (1 << 12) | (1 << 16)); buffer.appendInt64(123456); buffer.appendInt32(1)
        buffer.appendInt32(1897752877); buffer.appendInt32(2); buffer.appendInt32(27)
        buffer.appendInt32(1234)
        guard let result = Api.parse(buffer) as? Api.User,
              case let .user(_, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, maxStory, _, _, active, _, _) = result else { return XCTFail("RecentStory parser") }
        XCTAssertEqual(maxStory, 27)
        XCTAssertEqual(active, 1234)
    }
    func testPeerBearingForumTopicResponse() {
        let buffer = Buffer()
        buffer.appendInt32(-838922550); buffer.appendInt32(0)
        buffer.appendInt32(42); buffer.appendInt32(1700000000)
        Api.Peer.peerUser(userId: 123456).serialize(buffer, true)
        // TL string "Work": length + bytes, padded to a four-byte boundary.
        var bytes: [UInt8] = [4, 87, 111, 114, 107, 0, 0, 0]
        bytes.withUnsafeBytes { buffer.appendBytes($0.baseAddress!, length: UInt($0.count)) }
        buffer.appendInt32(0x6fb9f0)
        for value: Int32 in [45, 44, 43, 1, 0, 0] { buffer.appendInt32(value) }
        Api.Peer.peerUser(userId: 999).serialize(buffer, true)
        Api.PeerNotifySettings.peerNotifySettings(flags: 0, showPreviews: nil, silent: nil, muteUntil: nil, iosSound: nil, androidSound: nil, otherSound: nil, storiesMuted: nil, storiesHideSender: nil, storiesIosSound: nil, storiesAndroidSound: nil, storiesOtherSound: nil).serialize(buffer, true)
        guard let value = Api.parse(buffer) as? Api.ForumTopic,
              case let .forumTopic(_, id, _, title, _, _, top, _, _, unread, _, _, _, _, _) = value else { return XCTFail("Peer-based topic parser") }
        XCTAssertEqual(id, 42); XCTAssertEqual(title, "Work"); XCTAssertEqual(top, 45); XCTAssertEqual(unread, 1)
    }
    func testTruncatedCompatibilityHeadersReturnNil() {
        for constructor: Int32 in [-838922550, 829899656] {
            let buffer = Buffer(); buffer.appendInt32(constructor)
            XCTAssertNil(Api.parse(buffer))
        }
    }
}
