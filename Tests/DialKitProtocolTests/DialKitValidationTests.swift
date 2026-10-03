import XCTest
@testable import DialkitmacOSProtocol

final class DialKitValidationTests: XCTestCase {
    func testUnterminatedFrameLimitClearsBuffer() {
        var buffer = Data(repeating: 65, count: DialKitWireCodec.maximumFrameBytes + 1)
        XCTAssertThrowsError(try DialKitWireCodec.decodeAvailableMessages(from: &buffer, as: DialKitAgentMessage.self)) {
            XCTAssertEqual($0 as? DialKitWireError, .frameTooLarge)
        }
        XCTAssertTrue(buffer.isEmpty)
    }

    func testCompleteOversizedFrameAndOversizedEncodeAreRejected() throws {
        let message = DialKitAgentMessage.log(String(repeating: "x", count: DialKitWireCodec.maximumFrameBytes))
        XCTAssertThrowsError(try DialKitWireCodec.encode(message))
        var buffer = try JSONEncoder().encode(message)
        buffer.append(10)
        XCTAssertThrowsError(try DialKitWireCodec.decodeAvailableMessages(from: &buffer, as: DialKitAgentMessage.self))
        XCTAssertTrue(buffer.isEmpty)
    }

    func testInvalidNestedBoundsAreSkippedWithoutDroppingValidSnapshot() throws {
        let bad = DialKitControlSnapshot(path: "bad", label: "Bad", kind: .slider(value: 5, lowerBound: 10, upperBound: 0, step: 1, unit: nil))
        let group = DialKitControlSnapshot(path: "group", label: "Group", kind: .group(collapsed: false, controls: [bad]))
        let panel = DialKitPanelSnapshot(id: UUID(), name: "Test", controls: [group], presets: [], activePresetID: nil, nextPresetName: "Version 2")
        var buffer = try DialKitWireCodec.encode(DialKitAgentMessage.snapshot(.init(appName: "Bad", panels: [panel])))
        let good = DialKitAgentMessage.hello(.init(appName: "Good", panels: []))
        buffer.append(try DialKitWireCodec.encode(good))
        var errors: [Error] = []
        XCTAssertEqual(try DialKitWireCodec.decodeAvailableMessages(from: &buffer, as: DialKitAgentMessage.self, onDecodingError: { errors.append($0) }), [good])
        XCTAssertEqual(errors.first as? DialKitWireError, .invalidSnapshot)
    }

    func testSnapshotCleaningKeepsValidSiblingsAndRecoversInvalidValues() {
        let good = DialKitControlSnapshot(path: "good", label: "Good", kind: .slider(value: 42, lowerBound: 0, upperBound: 100, step: 1, unit: nil))
        let bad = DialKitControlSnapshot(path: "bad", label: "Bad", kind: .slider(value: .nan, lowerBound: 0, upperBound: 100, step: 1, unit: nil))
        let group = DialKitControlSnapshot(path: "group", label: "Group", kind: .group(collapsed: false, controls: [good, bad]))
        let panel = DialKitPanelSnapshot(id: UUID(), name: "Test", controls: [group], presets: [], activePresetID: nil, nextPresetName: "Version 2")
        let cleaned = DialKitSessionSnapshot(appName: "Test", panels: [panel]).removingInvalidControls()
        XCTAssertEqual(cleaned.paths, ["Test.bad"])
        guard case let .group(_, children) = cleaned.snapshot.panels[0].controls[0].kind else { return XCTFail("Missing group") }
        XCTAssertEqual(children, [good])
        XCTAssertNoThrow(try DialKitWireCodec.encode(DialKitAgentMessage.snapshot(cleaned.snapshot)))
    }

    func testMotionComponentMessagesRoundTripAndRejectInvalidEdits() throws {
        for component in [DialKitMotionComponent.duration(0.8), .bounce(0.6), .stiffness(200), .damping(20), .mass(1), .x1(0.1), .y1(-0.5), .x2(0.9), .y2(1.5), .bezier(.standard)] {
            let message = DialKitInspectorMessage.setMotionComponent(panelID: UUID(), path: "motion", component: component)
            var buffer = try DialKitWireCodec.encode(message)
            XCTAssertEqual(try DialKitWireCodec.decodeAvailableMessages(from: &buffer, as: DialKitInspectorMessage.self), [message])
        }
        XCTAssertNil(DialKitMotionComponent.duration(.nan).applying(to: .time(duration: 0.3, bounce: 0.2)))
        XCTAssertNil(DialKitMotionComponent.mass(0).applying(to: .physics(stiffness: 200, damping: 25, mass: 1)))
        XCTAssertNil(DialKitMotionComponent.x1(2).applying(to: .easing(duration: 0.3, bezier: .standard)))
    }
}
