import XCTest
@testable import DialKitProtocol

final class DialKitProtocolTests: XCTestCase {
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
