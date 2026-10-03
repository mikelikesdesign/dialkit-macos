import XCTest
import DialkitmacOSProtocol
@testable import DialkitmacOSCore

final class DialKitMotionAndFloatRegressionTests: XCTestCase {
    struct Motion: Codable, Equatable {
        var spring: DialSpring = .default
        var transition: DialTransition = .default
        static var controls: [DialControl<Self>] {
            [.group("motion", children: [.spring("spring", keyPath: \.spring), .transition("transition", keyPath: \.transition)])]
        }
    }

    func testInvalidInitialMotionStaysVisibleWithValidDefaults() throws {
        for spring in [DialSpring.time(duration: 0, bounce: 0.2), .time(duration: 1, bounce: .nan),
                       .physics(stiffness: 0, damping: 1, mass: 1), .physics(stiffness: 1, damping: -1, mass: 0)] {
            let state = DialPanelState(name: "Invalid", initial: Motion(spring: spring, transition: .spring(spring)), controls: Motion.controls)
            XCTAssertEqual(state.values.spring, .default)
            XCTAssertEqual(state.values.transition, .default)
            let snapshot = DialStore.shared.remoteSnapshot(appName: "Test")
            XCTAssertTrue(snapshot.removingInvalidControls().paths.isEmpty)
            let panel = try XCTUnwrap(snapshot.panels.first { $0.id == state.id })
            guard case let .group(_, controls) = panel.controls[0].kind else { return XCTFail("Missing motion group") }
            XCTAssertEqual(controls.count, 2)
            XCTAssertNoThrow(try DialKitWireCodec.encode(DialKitAgentMessage.snapshot(snapshot)))
        }
    }

    func testInvalidAssignmentsRestorePreviousMotionAndKeepPresetsValid() throws {
        let initial = Motion(spring: .time(duration: 1.5, bounce: 0.24), transition: .easing(duration: 0, bezier: .standard))
        let state = DialPanelState(name: "Motion", initial: initial, controls: Motion.controls)
        state.savePreset(named: "Keep")
        let presetID = try XCTUnwrap(state.activePresetID)
        state.values.spring = .physics(stiffness: .infinity, damping: 0, mass: 1)
        state.values.transition = .easing(duration: -1, bezier: .standard)
        XCTAssertEqual(state.values, initial)
        state.values.transition = .easing(duration: 1, bezier: .init(x1: 2, y1: 0, x2: 1, y2: 1))
        XCTAssertEqual(state.values, initial)
        state.loadPreset(id: presetID)
        XCTAssertEqual(state.values, initial)
        state.configure(initial: Motion(spring: .time(duration: 0, bounce: 0), transition: .spring(.time(duration: 0, bounce: 0))), controls: Motion.controls)
        XCTAssertEqual(state.values, initial)
    }

    func testValidMotionOutsideEditorRangesIsPreserved() {
        let initial = Motion(spring: .physics(stiffness: 2000, damping: 0, mass: 20), transition: .spring(.time(duration: 4, bounce: 0.24)))
        let state = DialPanelState(name: "Valid", initial: initial, controls: Motion.controls)
        XCTAssertEqual(state.values, initial)
    }

    func testSteppedFloatsUseTheirDecimalPrecisionLocallyAndOnTheWire() throws {
        struct Model: Codable, Equatable { var value: Float = 0.3 }
        let state = DialPanelState(name: "Float", initial: Model(), controls: [
            .slider("value", keyPath: \.value, range: Float(0)...Float(1), step: Float(0.1))
        ])
        guard case let .slider(slider) = state.resolvedControls()[0].kind else { return XCTFail("Missing slider") }
        XCTAssertEqual(slider.step, 0.1)
        XCTAssertEqual(DialNumber.format(slider.get(), step: slider.step), "0.3")
        slider.set(0.7)
        XCTAssertEqual(state.values.value, Float(0.7))
        let panel = try XCTUnwrap(DialStore.shared.remoteSnapshot(appName: "Float").panels.first { $0.id == state.id })
        guard case let .slider(value, _, _, step, _) = panel.controls[0].kind else { return XCTFail("Missing remote slider") }
        XCTAssertEqual(DialNumber.format(value, step: step), "0.7")
    }

    func testFloatRangeOffsetAndFineStepsDoNotAcquireBinaryDigits() {
        struct Model: Codable, Equatable { var value: Float = 0.35 }
        let state = DialPanelState(name: "Offset", initial: Model(), controls: [
            .slider("value", keyPath: \.value, range: Float(0.05)...Float(0.95), step: Float(0.1))
        ])
        guard case let .slider(slider) = state.resolvedControls()[0].kind else { return XCTFail("Missing slider") }
        XCTAssertEqual(slider.range, 0.05...0.95)
        XCTAssertEqual(DialNumber.format(slider.get(), step: slider.step), "0.35")
        slider.set(0.46)
        XCTAssertEqual(DialNumber.format(slider.get(), step: slider.step), "0.45")
    }
}
