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

    func testReplacementConnectionClearsOldSnapshotBeforeHello() async throws {
        let service = DialKitInspectorService(port: nil)
        let panel = makePanel()
        defer { DialKitAgent.shared.stop(); withExtendedLifetime(panel) {} }
        try await connect(to: service)
        let replacement = NWConnection(host: "127.0.0.1", port: NWEndpoint.Port(rawValue: try XCTUnwrap(service.listeningPort))!, using: .tcp)
        defer { replacement.cancel() }
        replacement.start(queue: DispatchQueue(label: "InspectorReplacementTest"))
        try await waitUntil { service.snapshot == nil }
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
