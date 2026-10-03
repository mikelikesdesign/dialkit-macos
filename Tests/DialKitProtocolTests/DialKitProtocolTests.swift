import XCTest
@testable import DialkitmacOSProtocol

final class DialKitProtocolTests: XCTestCase {
    func testSliderNumericMetadataRoundTripsAndOldSnapshotsStillDecode() throws {
        for numericType in [DialKitSliderValueType.float, .double] {
            let control = DialKitControlSnapshot(path: "value", label: "Value",
                kind: .slider(value: 0.3, lowerBound: 0, upperBound: 1, step: 0, unit: nil), numericType: numericType)
            let panel = DialKitPanelSnapshot(id: UUID(), name: "Numeric", controls: [control],
                presets: [], activePresetID: nil, nextPresetName: "Version 2")
            let message = DialKitAgentMessage.snapshot(.init(appName: "Test", panels: [panel]))
            var buffer = try DialKitWireCodec.encode(message)
            XCTAssertEqual(try DialKitWireCodec.decodeAvailableMessages(from: &buffer, as: DialKitAgentMessage.self), [message])
        }
        // A control from an older agent has no numericType key at all.
        let control = DialKitControlSnapshot(path: "value", label: "Value",
            kind: .slider(value: 0.3, lowerBound: 0, upperBound: 1, step: 0, unit: nil))
        let encoded = try JSONEncoder().encode(control)
        XCTAssertFalse(String(decoding: encoded, as: UTF8.self).contains("numericType"))
        XCTAssertNil(try JSONDecoder().decode(DialKitControlSnapshot.self, from: encoded).numericType)
    }

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
