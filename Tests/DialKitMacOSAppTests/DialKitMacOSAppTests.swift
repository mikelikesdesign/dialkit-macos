import Combine
import Network
import XCTest
import DialkitmacOSAgent
import DialkitmacOSCore
import DialkitmacOSProtocol
@testable import DialkitmacOSApp

@MainActor
final class DialKitMacOSAppTests: XCTestCase {
    struct Model: Codable, Equatable { var value = 0.0 }

    func testNumericEditorRoundTripsFineStepsAndLargeValues() {
        for (value, step) in [(0.125, 0.001), (0.25, 0.25), (1000.0, 1.0), (0.05, 0.1), (1e-14, 1e-14)] {
            let draft = formatted(value, step: step, unit: nil)
            XCTAssertEqual(DialNumber.parse(draft), value)
            XCTAssertFalse(draft.contains(","))
        }
        XCTAssertNil(DialNumber.parse("nan"))
        XCTAssertNil(DialNumber.parse("inf"))
    }

    func testCopyPreservesFineSliderAndSpringValues() {
        let panel = DialKitPanelSnapshot(id: UUID(), name: "Fine", controls: [
            .init(path: "value", label: "Value", kind: .slider(value: 0.125, lowerBound: 0, upperBound: 1, step: 0.001, unit: nil)),
            .init(path: "spring", label: "Spring", kind: .spring(value: .physics(stiffness: 200.125, damping: 20.375, mass: 0.125)))
        ], presets: [], activePresetID: nil, nextPresetName: "Version 2")
        let text = copyInstructionText(for: panel)
        XCTAssertTrue(text.contains("Value: 0.125"))
        XCTAssertTrue(text.contains("200.125"))
        XCTAssertTrue(text.contains("20.375"))
        XCTAssertTrue(text.contains("mass: 0.125"))
    }

    func testColorDraftCommitNormalizesValidEditsAndRevertsInvalidEdits() {
        XCTAssertEqual(InspectorDraft.color(" ff00aa80 ", fallback: "#000000"), "#FF00AA80")
        XCTAssertEqual(InspectorDraft.color("#abc", fallback: "#000000"), "#ABC")
        for draft in ["", "#12", "#GG0000", "#123456789"] {
            XCTAssertEqual(InspectorDraft.color(draft, fallback: "#aabbcc"), "#AABBCC")
        }
    }

    func testBezierDraftCommitPreservesPrecisionAndRevertsInvalidEdits() {
        let current = DialKitBezierValue.standard
        XCTAssertEqual(InspectorDraft.bezier("0.125, -0.375, 0.875, 1.25", fallback: current),
                       DialKitBezierValue(x1: 0.125, y1: -0.375, x2: 0.875, y2: 1.25))
        for draft in ["", "0.1,,0.2,1", "nan,0,0,1", "0,inf,0,1", "2,0,0,1"] {
            XCTAssertEqual(InspectorDraft.bezier(draft, fallback: current), current)
        }
    }

    func testDisconnectClearsSnapshotAndReconnectRestoresIt() async throws {
        let service = DialKitInspectorService(port: nil)
        let panel = makePanel()
        defer { DialKitAgent.shared.stop(); withExtendedLifetime(panel) {} }
        try await connect(to: service)
        DialKitAgent.shared.stop()
        try await waitUntil { service.snapshot == nil && service.status == "Waiting for app" }
        try await connect(to: service)
        XCTAssertEqual(service.snapshot?.panels.first?.id, panel.id)
    }

    func testCompetingClientsCannotEvictActiveAppOrInterruptEdits() async throws {
        let service = DialKitInspectorService(port: nil)
        let panel = makePanel()
        defer { DialKitAgent.shared.stop(); withExtendedLifetime(panel) {} }
        try await connect(to: service)
        var lostSession = false
        let observer = service.$snapshot.sink { snapshot in
            if snapshot?.appName != "Inspector Test" { lostSession = true }
        }
        defer { observer.cancel() }
        let port = try XCTUnwrap(service.listeningPort)
        for _ in 0..<5 {
            let competitor = NWConnection(host: "127.0.0.1", port: NWEndpoint.Port(rawValue: port)!, using: .tcp)
            competitor.start(queue: DispatchQueue(label: "CompetingPreview"))
            let hello = DialKitAgentMessage.hello(.init(appName: "Competing Preview", panels: []))
            competitor.send(content: try DialKitWireCodec.encode(hello), completion: .contentProcessed { _ in })
            try await Task.sleep(for: .milliseconds(100))
            competitor.cancel()
        }
        service.setControlValue(panelID: panel.id, path: "value", value: .number(42))
        try await waitUntil { panel.values.value == 42 }
        XCTAssertFalse(lostSession, "Preview reconnects must never clear or replace the active session")
        XCTAssertEqual(service.snapshot?.appName, "Inspector Test")
    }

    func testRefreshRecoversAfterAnotherInspectorReleasesPort() async throws {
        var owner: DialKitInspectorService? = DialKitInspectorService(port: nil)
        try await waitUntil { owner?.listeningPort != nil }
        let port = try XCTUnwrap(owner?.listeningPort)
        let service = DialKitInspectorService(port: port)
        try await waitUntil { service.status.contains("already running") }
        owner = nil
        try await Task.sleep(for: .milliseconds(100))
        service.requestSnapshot()
        try await waitUntil { service.listeningPort == port }
    }

    func testDragIgnoresDelayedEchoesUntilFinalValueIsAcknowledged() {
        var editing = DialSliderEditingState()
        editing.begin(remote: 20)
        XCTAssertEqual(editing.update(translation: 30, width: 100, range: 0...100, step: 1), 50)
        editing.receive(25)
        XCTAssertEqual(editing.displayedValue(remote: 25), 50)
        XCTAssertEqual(editing.update(translation: 40, width: 100, range: 0...100, step: 1), 60)
        editing.end(remote: 40)
        editing.receive(50)
        XCTAssertEqual(editing.displayedValue(remote: 50), 60)
        editing.receive(60)
        XCTAssertNil(editing.pendingValue)
        XCTAssertEqual(editing.displayedValue(remote: 70), 70)
    }

    func testUnchangedNumericCommitDoesNotBlockLaterPresetValue() {
        var editing = DialSliderEditingState()
        XCTAssertFalse(editing.commit(20, remote: 20, step: 1))
        XCTAssertNil(editing.pendingValue)
        // An unchanged snapshot does not call the view's onChange observer.
        editing.receive(40)
        XCTAssertEqual(editing.displayedValue(remote: 40), 40)
    }

    func testIntegerDefaultStepProducesRepresentableEdits() throws {
        struct IntegerModel: Codable, Equatable { var count = 0 }
        let panel = DialPanelState(name: "Integer", initial: IntegerModel(), controls: [
            .slider("count", keyPath: \.count, range: 0...10)
        ])
        let control = try XCTUnwrap(DialStore.shared.remoteSnapshot(appName: "Test")
            .panels.first { $0.id == panel.id }?.controls.first)
        guard case let .slider(value, lower, upper, step, _) = control.kind else {
            return XCTFail("Missing slider")
        }
        XCTAssertEqual(step, 1)
        var editing = DialSliderEditingState()
        editing.begin(remote: value)
        XCTAssertNil(editing.update(translation: 3, width: 100, range: lower...upper, step: step))
        for translation in stride(from: 10.0, through: 100.0, by: 10) {
            let sent = try XCTUnwrap(editing.update(translation: translation, width: 100, range: lower...upper, step: step))
            XCTAssertTrue(DialStore.shared.setRemoteControlValue(panelID: panel.id, path: "count", value: .number(sent)))
            XCTAssertEqual(sent, Double(panel.values.count))
            editing.receive(Double(panel.values.count))
        }
        editing.end(remote: Double(panel.values.count))
        XCTAssertNil(editing.pendingValue)
    }

    func testAcknowledgementDuringDragSurvivesNewerAppValues() {
        var editing = DialSliderEditingState()
        editing.begin(remote: 20)
        XCTAssertEqual(editing.update(translation: 30, width: 100, range: 0...100, step: 1), 50)
        editing.receive(50)
        editing.receive(70)
        XCTAssertEqual(editing.displayedValue(remote: 70), 50, "The pointer owns the display until mouse-up")
        editing.end(remote: 70)
        XCTAssertNil(editing.pendingValue)
        XCTAssertEqual(editing.displayedValue(remote: 70), 70)
        editing.receive(80)
        XCTAssertEqual(editing.displayedValue(remote: 80), 80)
    }

    func testNewDragValueRequiresItsOwnAcknowledgement() {
        var editing = DialSliderEditingState()
        editing.begin(remote: 20)
        XCTAssertEqual(editing.update(translation: 30, width: 100, range: 0...100, step: 1), 50)
        editing.receive(50)
        XCTAssertEqual(editing.update(translation: 40, width: 100, range: 0...100, step: 1), 60)
        editing.end(remote: 50)
        XCTAssertEqual(editing.pendingValue, 60)
        editing.receive(60)
        XCTAssertNil(editing.pendingValue)
    }

    func testRevertingToRemoteValueStillSendsOverAnInFlightEdit() {
        var editing = DialSliderEditingState()
        XCTAssertTrue(editing.commit(30, remote: 20, step: 1))
        XCTAssertTrue(editing.commit(20, remote: 20, step: 1))
        XCTAssertNil(editing.pendingValue)
        editing.receive(40)
        XCTAssertEqual(editing.displayedValue(remote: 40), 40)
    }

    func testFloatModelAcknowledgesDragAndTypedEdits() throws {
        struct FloatModel: Codable, Equatable { var value: Float = 0 }
        let panel = DialPanelState(name: "Float", initial: FloatModel(), controls: [
            .slider("value", keyPath: \.value, range: Float(0)...Float(1), step: Float(0.1))
        ])
        let step = 0.1
        var editing = DialSliderEditingState(numericType: .float)
        editing.begin(remote: 0)
        let sent = try XCTUnwrap(editing.update(translation: 30, width: 100, range: 0...1, step: step))
        editing.end(remote: 0)
        XCTAssertTrue(DialStore.shared.setRemoteControlValue(panelID: panel.id, path: "value", value: .number(sent)))
        let echoed = Double(String(panel.values.value))!
        XCTAssertNotEqual(sent, Double(panel.values.value), "Exercise a real Float conversion, not an exact Double model")
        editing.receive(echoed)
        XCTAssertNil(editing.pendingValue)
        XCTAssertEqual(editing.displayedValue(remote: echoed), echoed)

        let typed = DialNumber.round(0.7, step: step, within: 0...1)
        XCTAssertTrue(editing.commit(typed, remote: echoed, step: step))
        XCTAssertTrue(DialStore.shared.setRemoteControlValue(panelID: panel.id, path: "value", value: .number(typed)))
        editing.receive(Double(String(panel.values.value))!)
        XCTAssertNil(editing.pendingValue)
        panel.values.value = 0.8
        let updated = Double(String(panel.values.value))!
        editing.receive(updated)
        XCTAssertEqual(editing.displayedValue(remote: updated), updated)
    }

    func testFloatToleranceDoesNotAcknowledgeNeighbouringFineDoubleStep() {
        var editing = DialSliderEditingState()
        XCTAssertTrue(editing.commit(1.000000002, remote: 1, step: 0.000000001))
        editing.receive(1.000000001)
        XCTAssertEqual(editing.pendingValue, 1.000000002)
        editing.receive(1.000000002)
        XCTAssertNil(editing.pendingValue)
    }

    func testConsecutiveDragsUseLocalValueAndSkipDuplicateSnappedEdits() {
        var editing = DialSliderEditingState()
        editing.begin(remote: 0.05)
        XCTAssertEqual(editing.update(translation: 50, width: 100, range: 0.05...0.25, step: 0.1), 0.15)
        XCTAssertNil(editing.update(translation: 51, width: 100, range: 0.05...0.25, step: 0.1))
        editing.end(remote: 0.05)
        editing.begin(remote: 0.05)
        XCTAssertEqual(editing.update(translation: 50, width: 100, range: 0.05...0.25, step: 0.1), 0.25)
        editing.receive(0.15)
        XCTAssertEqual(editing.displayedValue(remote: 0.15), 0.25)
    }

    func testContinuousModelChangesSendIntermediateAndFinalSnapshots() async throws {
        let service = DialKitInspectorService(port: nil)
        let panel = makePanel()
        defer { DialKitAgent.shared.stop(); withExtendedLifetime(panel) {} }
        try await connect(to: service)
        var received: [Double] = []
        let observer = service.$snapshot.sink { snapshot in
            if case let .slider(value, _, _, _, _) = snapshot?.panels.first?.controls.first?.kind {
                received.append(value)
            }
        }
        defer { observer.cancel() }
        for value in 1...40 {
            panel.values.value = Double(value)
            try await Task.sleep(for: .milliseconds(20))
        }
        XCTAssertTrue(received.contains { $0 > 0 && $0 < 40 }, "Updates must arrive before continuous edits stop")
        try await waitUntil { received.last == 40 }
    }

    private func makePanel() -> DialPanelState<Model> {
        DialPanelState(name: "Test", initial: Model(), controls: [
            .slider("value", keyPath: \.value, range: 0...100, step: 1)
        ])
    }

    private func connect(to service: DialKitInspectorService) async throws {
        try await waitUntil { service.listeningPort != nil }
        DialKitAgent.shared.start(appName: "Inspector Test", port: try XCTUnwrap(service.listeningPort))
        try await waitUntil { service.snapshot != nil }
    }

    private func waitUntil(_ condition: () -> Bool) async throws {
        let deadline = Date().addingTimeInterval(3)
        while !condition() {
            guard Date() < deadline else {
                XCTFail("Timed out waiting for inspector state")
                throw NSError(domain: "InspectorTests", code: 1)
            }
            try await Task.sleep(for: .milliseconds(10))
        }
    }
}
