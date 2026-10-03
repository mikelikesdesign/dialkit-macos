import XCTest
@testable import DialkitmacOSProtocol

final class DialKitProtocolTests: XCTestCase {
    func testMalformedFramesPreserveValidNeighboursAndPartialTail() throws {
        let first = DialKitInspectorMessage.requestSnapshot
        let second = DialKitInspectorMessage.setControlValue(panelID: UUID(), path: "opacity", value: .number(0.4))
        let third = DialKitInspectorMessage.clearActivePreset(panelID: UUID())
        var buffer = try DialKitWireCodec.encode(first)
        buffer.append(Data("invalid-json\n".utf8))
        buffer.append(try DialKitWireCodec.encode(second))
        buffer.append(Data("{}\n\n".utf8))
        let partial = try DialKitWireCodec.encode(third).dropLast()
        buffer.append(partial)
        var errors: [Error] = []
        let decoded = try DialKitWireCodec.decodeAvailableMessages(
            from: &buffer, as: DialKitInspectorMessage.self,
            onDecodingError: { errors.append($0) }
        )
        XCTAssertEqual(decoded, [first, second])
        XCTAssertEqual(errors.count, 2)
        XCTAssertEqual(buffer, Data(partial))
        buffer.append(10)
        XCTAssertEqual(try DialKitWireCodec.decodeAvailableMessages(from: &buffer, as: DialKitInspectorMessage.self), [third])
        XCTAssertTrue(buffer.isEmpty)
    }

    func testMalformedFirstFrameDoesNotBlockFollowingSnapshot() throws {
        let snapshot = DialKitAgentMessage.hello(.init(appName: "Test", panels: []))
        var buffer = Data("bad-frame\n".utf8)
        buffer.append(try DialKitWireCodec.encode(snapshot))
        XCTAssertEqual(try DialKitWireCodec.decodeAvailableMessages(from: &buffer, as: DialKitAgentMessage.self), [snapshot])
        XCTAssertTrue(buffer.isEmpty)
    }

    func testWireCodecDecodesCompleteLinesAndKeepsPartialMessageBuffered() throws {
        let first = DialKitInspectorMessage.requestSnapshot
        let second = DialKitInspectorMessage.setControlValue(
            panelID: UUID(),
            path: "opacity",
            value: .number(0.42)
        )

        var firstData = try DialKitWireCodec.encode(first)
        let secondData = try DialKitWireCodec.encode(second)
        firstData.append(secondData.dropLast())

        var buffer = firstData
        let decoded = try DialKitWireCodec.decodeAvailableMessages(
            from: &buffer,
            as: DialKitInspectorMessage.self
        )

        XCTAssertEqual(decoded, [first])
        XCTAssertFalse(buffer.isEmpty)

        buffer.append(10)

        let remaining = try DialKitWireCodec.decodeAvailableMessages(
            from: &buffer,
            as: DialKitInspectorMessage.self
        )

        XCTAssertEqual(remaining, [second])
        XCTAssertTrue(buffer.isEmpty)
    }
}
