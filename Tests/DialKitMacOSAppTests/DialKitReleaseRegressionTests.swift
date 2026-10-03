import AppKit
import Combine
import Network
import SwiftUI
import XCTest
import DialkitmacOSAgent
import DialkitmacOSCore
import DialkitmacOSProtocol
@testable import DialkitmacOSApp

@MainActor
final class DialKitReleaseRegressionTests: XCTestCase {
    struct Model: Codable, Equatable {
        var spring: DialSpring = .time(duration: 0.35, bounce: 0.24)
        var transition: DialTransition = .easing(duration: 0.3, bezier: .standard)
        var value = 20.0
        var other = 0.0
    }

    func testRapidMotionEditsPreserveAllFieldsOverLiveConnection() async throws {
        let panel = makePanel()
        let service = DialKitInspectorService(port: nil)
        defer { DialKitAgent.shared.stop(); withExtendedLifetime(panel) {} }
        try await connect(service)
        service.setMotionComponent(panelID: panel.id, path: "spring", component: .duration(0.8))
        service.setMotionComponent(panelID: panel.id, path: "spring", component: .bounce(0.6))
        service.setMotionComponent(panelID: panel.id, path: "transition", component: .duration(0.7))
        service.setMotionComponent(panelID: panel.id, path: "transition", component: .x1(0.4))
        service.setMotionComponent(panelID: panel.id, path: "transition", component: .y2(1.5))
        try await waitUntil {
            panel.values.spring == .time(duration: 0.8, bounce: 0.6)
                && panel.values.transition == .easing(duration: 0.7, bezier: .init(x1: 0.4, y1: 0.1, x2: 0.25, y2: 1.5))
        }
        XCTAssertEqual(panel.values.spring, .time(duration: 0.8, bounce: 0.6))
        XCTAssertTrue(DialStore.shared.setRemoteControlValue(panelID: panel.id, path: "spring", value: .spring(.physics(stiffness: 200, damping: 25, mass: 1))))
        service.setMotionComponent(panelID: panel.id, path: "spring", component: .stiffness(300))
        service.setMotionComponent(panelID: panel.id, path: "spring", component: .damping(30))
        service.setMotionComponent(panelID: panel.id, path: "spring", component: .mass(2))
        try await waitUntil { panel.values.spring == .physics(stiffness: 300, damping: 30, mass: 2) }
    }

    func testInvalidControlDoesNotStallOtherUpdatesAndRecovers() async throws {
        let panel = makePanel()
        panel.values.value = .nan
        let service = DialKitInspectorService(port: nil)
        defer { DialKitAgent.shared.stop(); withExtendedLifetime(panel) {} }
        try await connect(service)
        XCTAssertFalse(snapshotControls(service, panel.id).contains { $0.path == "value" })
        XCTAssertTrue(service.lastLog?.contains("Ignored invalid controls") == true)
        service.setControlValue(panelID: panel.id, path: "other", value: .number(42))
        try await waitUntil {
            if case let .slider(value, _, _, _, _) = self.snapshotControls(service, panel.id).first(where: { $0.path == "other" })?.kind {
                return value == 42
            }
            return false
        }
        XCTAssertEqual(panel.values.other, 42)
        panel.values.value = 50
        try await waitUntil { self.snapshotControls(service, panel.id).contains { $0.path == "value" } }
    }

    func testNarrowedSliderConfigurationDropsObsoletePendingValue() throws {
        let panel = makePanel()
        var editing = DialSliderEditingState()
        editing.begin(remote: 20)
        let sent = try XCTUnwrap(editing.update(translation: 60, width: 100, range: 0...100, step: 1))
        editing.end(remote: 20)
        panel.configure(controls: [.slider("value", keyPath: \.value, range: 0...50, step: 1)])
        editing.resetForConfigurationChange()
        XCTAssertTrue(DialStore.shared.setRemoteControlValue(panelID: panel.id, path: "value", value: .number(sent)))
        editing.receive(panel.values.value)
        XCTAssertEqual(editing.displayedValue(remote: panel.values.value), 50)
        XCTAssertNil(editing.pendingValue)
        XCTAssertFalse(editing.isDragging)
    }

    func testDefaultPhysicsStiffnessSurvivesUnchangedCommit() {
        XCTAssertEqual(DialNumber.round(200, step: InspectorMotionParameters.stiffnessStep, within: InspectorMotionParameters.stiffnessRange), 200)
    }

    func testEscapeCancelsNumericDraftAndReturnCommitsIt() {
        for cancel in [true, false] {
            var draft = "99"
            var saved = "20"
            let editor = DialInlineNumberTextField(
                text: Binding(get: { draft }, set: { draft = $0 }),
                onCommit: { saved = draft }, onBlur: { saved = draft }, onCancel: { draft = saved }
            )
            let coordinator = editor.makeCoordinator()
            let field = NSTextField()
            let textView = NSTextView()
            textView.string = "99"
            let command = cancel ? #selector(NSResponder.cancelOperation(_:)) : #selector(NSResponder.insertNewline(_:))
            XCTAssertTrue(coordinator.control(field, textView: textView, doCommandBy: command))
            // AppKit may deliver a subsequent end-editing notification.
            field.stringValue = "99"
            coordinator.controlTextDidEndEditing(Notification(name: NSControl.textDidEndEditingNotification, object: field))
            XCTAssertEqual(saved, cancel ? "20" : "99")
            XCTAssertEqual(draft, cancel ? "20" : "99")
        }
    }

    func testOversizedPeerIsDisconnectedAndLegitimateAppCanReconnect() async throws {
        let service = DialKitInspectorService(port: nil)
        try await waitUntil { service.listeningPort != nil }
        let port = try XCTUnwrap(service.listeningPort)
        let peer = NWConnection(host: "127.0.0.1", port: NWEndpoint.Port(rawValue: port)!, using: .tcp)
        defer { peer.cancel() }
        peer.start(queue: DispatchQueue(label: "Oversized peer"))
        try await waitUntil { service.status == "Connected" }
        peer.send(content: Data(repeating: 65, count: DialKitWireCodec.maximumFrameBytes + 1), completion: .contentProcessed { _ in })
        try await waitUntil { service.status == "Waiting for app" }
        XCTAssertTrue(service.lastLog?.contains("size limit") == true)
        let panel = makePanel()
        defer { DialKitAgent.shared.stop(); withExtendedLifetime(panel) {} }
        try await connect(service)
        XCTAssertEqual(service.snapshot?.appName, "Release regression")
    }

    private func snapshotControls(_ service: DialKitInspectorService, _ id: UUID) -> [DialKitControlSnapshot] {
        service.snapshot?.panels.first { $0.id == id }?.controls ?? []
    }
    private func makePanel() -> DialPanelState<Model> {
        DialPanelState(name: "Release regression", initial: Model(), controls: [
            .spring("spring", keyPath: \.spring), .transition("transition", keyPath: \.transition),
            .slider("value", keyPath: \.value, range: 0...100, step: 1),
            .slider("other", keyPath: \.other, range: 0...100, step: 1)
        ])
    }
    private func connect(_ service: DialKitInspectorService) async throws {
        try await waitUntil { service.listeningPort != nil }
        DialKitAgent.shared.start(appName: "Release regression", port: try XCTUnwrap(service.listeningPort))
        try await waitUntil { service.snapshot != nil }
    }
    private func waitUntil(_ condition: () -> Bool) async throws {
        let deadline = Date().addingTimeInterval(3)
        while !condition() {
            if Date() > deadline { throw NSError(domain: "Release regression timed out", code: 1) }
            try await Task.sleep(for: .milliseconds(10))
        }
    }
}
