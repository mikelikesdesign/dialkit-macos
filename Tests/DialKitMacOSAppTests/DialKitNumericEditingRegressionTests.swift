import XCTest
import DialkitmacOSAgent
import DialkitmacOSCore
import DialkitmacOSProtocol
@testable import DialkitmacOSApp

@MainActor
final class DialKitNumericEditingRegressionTests: XCTestCase {
    func testFineFloatEditAcknowledgesOverTheWireAndShowsLaterPreset() async throws {
        struct Model: Codable, Equatable { var value: Float = 0 }
        let panel = DialPanelState(name: "Fine Float", initial: Model(), controls: [
            .slider("value", keyPath: \.value, range: Float(0)...Float(1), step: Float(1e-8))
        ])
        panel.values.value = 0.8
        panel.savePreset(named: "Later")
        let presetID = try XCTUnwrap(panel.activePresetID)
        panel.clearActivePreset()
        panel.values.value = 0
        let service = DialKitInspectorService(port: nil)
        defer { DialKitAgent.shared.stop(); withExtendedLifetime(panel) {} }
        try await connect(service)
        let control = try XCTUnwrap(service.snapshot?.panels.first { $0.id == panel.id }?.controls.first)
        XCTAssertEqual(control.numericType, .float)
        guard case let .slider(remote, lower, upper, step, _) = control.kind else { return XCTFail("Missing slider") }
        var editing = DialSliderEditingState(numericType: try XCTUnwrap(control.numericType))
        editing.begin(remote: remote)
        let sent = try XCTUnwrap(editing.update(translation: 30.000001, width: 100, range: lower...upper, step: step))
        XCTAssertEqual(sent, 0.30000001)
        editing.end(remote: remote)
        service.setControlValue(panelID: panel.id, path: "value", value: .number(sent))
        try await waitUntil { self.wireValue(service, panelID: panel.id) == 0.3 }
        editing.receive(try XCTUnwrap(wireValue(service, panelID: panel.id)))
        XCTAssertNil(editing.pendingValue)
        service.loadPreset(panelID: panel.id, presetID: presetID)
        try await waitUntil { self.wireValue(service, panelID: panel.id) == 0.8 }
        let presetValue = try XCTUnwrap(wireValue(service, panelID: panel.id))
        editing.receive(presetValue)
        XCTAssertEqual(editing.displayedValue(remote: presetValue), 0.8)
        // Typing a value which becomes the current Float needs no echo.
        XCTAssertFalse(editing.commit(0.80000001, remote: presetValue, step: step))
        XCTAssertNil(editing.pendingValue)
    }

    func testContinuousDoubleTypedEditIsSentAndAcknowledgesOnlyExactValue() async throws {
        struct Model: Codable, Equatable { var value = Double(Float(0.3)) }
        let panel = DialPanelState(name: "Continuous Double", initial: Model(), controls: [
            .slider("value", keyPath: \.value, range: 0...1, step: 0)
        ])
        let service = DialKitInspectorService(port: nil)
        defer { DialKitAgent.shared.stop(); withExtendedLifetime(panel) {} }
        try await connect(service)
        let control = try XCTUnwrap(service.snapshot?.panels.first { $0.id == panel.id }?.controls.first)
        XCTAssertEqual(control.numericType, .double)
        let previous = try XCTUnwrap(wireValue(service, panelID: panel.id))
        var editing = DialSliderEditingState(numericType: try XCTUnwrap(control.numericType))
        let shouldSend = editing.commit(0.3, remote: previous, step: 0)
        XCTAssertTrue(shouldSend)
        editing.receive(previous)
        XCTAssertEqual(editing.pendingValue, 0.3)
        if shouldSend { service.setControlValue(panelID: panel.id, path: "value", value: .number(0.3)) }
        try await waitUntil { self.wireValue(service, panelID: panel.id) == 0.3 }
        XCTAssertEqual(panel.values.value, 0.3)
        editing.receive(try XCTUnwrap(wireValue(service, panelID: panel.id)))
        XCTAssertNil(editing.pendingValue)
    }

    func testFineSteppedDoubleRejectsFloatRoundedEcho() {
        var editing = DialSliderEditingState()
        XCTAssertTrue(editing.commit(0.30000001, remote: 0, step: 1e-8))
        editing.receive(0.3)
        editing.receive(Double(Float(0.30000001)))
        XCTAssertEqual(editing.pendingValue, 0.30000001)
        editing.receive(0.30000001)
        XCTAssertNil(editing.pendingValue)
    }

    func testNumericTypeReconfigurationClearsPendingEdit() {
        var editing = DialSliderEditingState(numericType: .float)
        XCTAssertTrue(editing.commit(0.3, remote: 0, step: 0))
        editing.configure(numericType: .double)
        XCTAssertNil(editing.pendingValue)
        XCTAssertTrue(editing.commit(0.3, remote: Double(Float(0.3)), step: 0))
        editing.resetForConfigurationChange()
        XCTAssertTrue(editing.commit(0.3, remote: Double(Float(0.3)), step: 0))
    }

    private func wireValue(_ service: DialKitInspectorService, panelID: UUID) -> Double? {
        guard case let .slider(value, _, _, _, _) = service.snapshot?.panels.first(where: { $0.id == panelID })?.controls.first?.kind else { return nil }
        return value
    }

    private func connect(_ service: DialKitInspectorService) async throws {
        try await waitUntil { service.listeningPort != nil }
        DialKitAgent.shared.start(appName: "Numeric regression", port: try XCTUnwrap(service.listeningPort))
        try await waitUntil { service.snapshot != nil }
    }

    private func waitUntil(_ condition: () -> Bool) async throws {
        let deadline = ContinuousClock.now + .seconds(5)
        while !condition() {
            guard ContinuousClock.now < deadline else {
                XCTFail("Timed out waiting for numeric update")
                throw NSError(domain: "DialKitNumericEditingRegressionTests", code: 1)
            }
            try await Task.sleep(for: .milliseconds(20))
        }
    }
}
