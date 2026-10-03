import XCTest
import DialkitmacOSCore
import DialkitmacOSAgent
import DialkitmacOSProtocol
@testable import DialkitmacOSApp

@MainActor
final class DialKitEdgeCaseRegressionTests: XCTestCase {
    struct FloatModel: Codable, Equatable { var value: Float = 0 }

    func testContinuousFloatTypedEditAcknowledgesAndShowsLaterPresetChanges() throws {
        let panel = makeFloatPanel()
        panel.savePreset(named: "Before")
        let presetID = try XCTUnwrap(panel.activePresetID)
        panel.clearActivePreset()
        var editing = DialSliderEditingState(numericType: .float)
        XCTAssertTrue(editing.commit(0.3, remote: 0, step: 0))
        XCTAssertTrue(DialStore.shared.setRemoteControlValue(panelID: panel.id, path: "value", value: .number(0.3)))
        let actual = Double(panel.values.value)
        XCTAssertNotEqual(actual, 0.3)
        editing.receive(actual)
        XCTAssertNil(editing.pendingValue)
        panel.values.value = 0.8
        editing.receive(Double(panel.values.value))
        XCTAssertEqual(editing.displayedValue(remote: Double(panel.values.value)), Double(panel.values.value))
        panel.loadPreset(id: presetID)
        editing.receive(Double(panel.values.value))
        XCTAssertEqual(editing.displayedValue(remote: Double(panel.values.value)), 0)
    }

    func testContinuousFloatDragRejectsStaleEchoAndAcknowledgesOnMouseUp() throws {
        let panel = makeFloatPanel()
        var editing = DialSliderEditingState(numericType: .float)
        editing.begin(remote: 0)
        let first = try XCTUnwrap(editing.update(translation: 30, width: 100, range: 0...1, step: 0))
        let final = try XCTUnwrap(editing.update(translation: 70, width: 100, range: 0...1, step: 0))
        editing.receive(Double(Float(first)))
        editing.end(remote: Double(Float(first)))
        XCTAssertEqual(editing.pendingValue, final)
        XCTAssertTrue(DialStore.shared.setRemoteControlValue(panelID: panel.id, path: "value", value: .number(final)))
        editing.receive(Double(panel.values.value))
        XCTAssertNil(editing.pendingValue)
    }

    func testContinuousDoubleDoesNotAcknowledgeNearbyDifferentEdit() {
        var editing = DialSliderEditingState()
        XCTAssertTrue(editing.commit(0.3, remote: 0, step: 0))
        editing.receive(0.3.nextUp)
        XCTAssertEqual(editing.pendingValue, 0.3)
        editing.receive(0.3)
        XCTAssertNil(editing.pendingValue)
        // A Double subnormal must remain pending until its exact value arrives.
        XCTAssertTrue(editing.commit(1e-50, remote: 0.1, step: 0))
        editing.receive(0)
        XCTAssertEqual(editing.pendingValue, 1e-50)
        editing.receive(1e-50)
        XCTAssertNil(editing.pendingValue)
    }

    func testContinuousFloatSubnormalAcknowledgesItsRoundedZero() {
        var editing = DialSliderEditingState(numericType: .float)
        XCTAssertTrue(editing.commit(1e-50, remote: 0.1, step: 0))
        editing.receive(0)
        XCTAssertNil(editing.pendingValue)
    }

    func testZeroDurationInspectorModeSwitchWorksOverLiveConnection() async throws {
        struct Model: Codable, Equatable { var transition = DialTransition.easing(duration: 0, bezier: .standard) }
        let panel = DialPanelState(name: "Instant", initial: Model(), controls: [
            .transition("transition", keyPath: \.transition)
        ])
        let service = DialKitInspectorService(port: nil)
        defer { DialKitAgent.shared.stop(); withExtendedLifetime(panel) {} }
        try await waitUntil { service.listeningPort != nil }
        DialKitAgent.shared.start(appName: "Zero duration regression", port: try XCTUnwrap(service.listeningPort))
        try await waitUntil { service.snapshot?.panels.contains { $0.id == panel.id } == true }
        let current = DialKitTransitionValue.easing(duration: 0, bezier: .standard)
        let next = current.switching(to: .simple)
        XCTAssertEqual(next, .spring(.time(duration: 0.1, bounce: 0.2)))
        service.setControlValue(panelID: panel.id, path: "transition", value: .transition(next))
        try await waitUntil {
            service.snapshot?.panels.first(where: { $0.id == panel.id })?.controls.first?.kind == .transition(value: next)
        }
        XCTAssertEqual(panel.values.transition.mode, .simple)
        XCTAssertEqual(DialKitTransitionValue.easing(duration: 0.05, bezier: .standard).switching(to: .simple),
                       .spring(.time(duration: 0.05, bounce: 0.2)))
    }

    func testInspectorGraphPreservesValidUndampedLowMassSpring() {
        let physics = DialKitSpringValue.physics(stiffness: 0.5, damping: 0, mass: 0.05).resolvedPhysics
        XCTAssertEqual(physics.stiffness, 0.5)
        XCTAssertEqual(physics.damping, 0)
        XCTAssertEqual(physics.mass, 0.05)
        let modelPhysics = DialSpring.physics(stiffness: 0.5, damping: 0, mass: 0.05).resolvedPhysics
        XCTAssertEqual(physics.stiffness, modelPhysics.stiffness)
        XCTAssertEqual(physics.damping, modelPhysics.damping)
        XCTAssertEqual(physics.mass, modelPhysics.mass)
        // An undamped spring reaches exactly 2 at half its oscillation period.
        XCTAssertEqual(SpringResponse.position(at: .pi / sqrt(10), stiffness: physics.stiffness,
                                               damping: physics.damping, mass: physics.mass), 2, accuracy: 1e-12)
    }

    private func makeFloatPanel() -> DialPanelState<FloatModel> {
        DialPanelState(name: "Continuous", initial: FloatModel(), controls: [
            .slider("value", keyPath: \.value, range: Float(0)...Float(1), step: 0)
        ])
    }

    private func waitUntil(_ condition: () -> Bool) async throws {
        let deadline = ContinuousClock.now + .seconds(5)
        while !condition() {
            guard ContinuousClock.now < deadline else {
                XCTFail("Timed out waiting for live inspector update")
                throw NSError(domain: "DialKitEdgeCaseRegressionTests", code: 1)
            }
            try await Task.sleep(for: .milliseconds(20))
        }
    }
}
