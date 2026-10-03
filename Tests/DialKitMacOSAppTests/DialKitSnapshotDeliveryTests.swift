import AppKit
import SwiftUI
import XCTest
import DialkitmacOSProtocol
@testable import DialkitmacOSApp

@MainActor
final class DialKitSnapshotDeliveryTests: XCTestCase {
    struct SliderProbe: View {
        @ObservedObject var service: DialKitInspectorService
        let source: DialSliderValueSource
        let received: (Double, Double?) -> Void
        let displayed: (Double) -> Void
        @State var editing: DialSliderEditingState

        var body: some View {
            let remote = source.value(in: service.snapshot) ?? 0
            let value = editing.displayedValue(remote: remote)
            Text("\(value)")
                .modifier(DialSliderSnapshotObserver(source: source) { next, acknowledged in
                    editing.receive(next, acknowledgingEdit: acknowledged)
                    received(next, editing.pendingValue)
                })
                .onChange(of: value, initial: true) { _, next in displayed(next) }
                .environmentObject(service)
        }
    }

    func testCoalescedSliderSnapshotsAcknowledgeEditAndDisplayNewerValues() async throws {
        try await checkCoalescedUpdates(field: .value) {
            .slider(value: $0, lowerBound: 0, upperBound: 100, step: 1, unit: nil)
        }
    }

    func testCoalescedMotionSnapshotsAcknowledgeEditAndDisplayNewerValues() async throws {
        try await checkCoalescedUpdates(field: .stiffness) {
            .transition(value: .spring(.physics(stiffness: $0, damping: 25, mass: 1)))
        }
    }

    func testAdjustedAcknowledgementReachesRenderedSlider() async throws {
        try await checkCoalescedUpdates(field: .value, adjusted: true) {
            .slider(value: $0, lowerBound: 0, upperBound: 100, step: 1, unit: nil)
        }
    }

    private func checkCoalescedUpdates(field: DialSliderValueSource.Field, adjusted: Bool = false, kind: (Double) -> DialKitControlKind) async throws {
        let service = DialKitInspectorService(port: nil)
        let panelID = UUID()
        let source = DialSliderValueSource(panelID: panelID, path: "group.value", field: field)
        func send(_ value: Double, editID: UUID? = nil) {
            let control = DialKitControlSnapshot(path: "group.value", label: "Value", kind: kind(value))
            let group = DialKitControlSnapshot(path: "group", label: "Group", kind: .group(collapsed: false, controls: [control]))
            let panel = DialKitPanelSnapshot(id: panelID, name: "Probe", controls: [group], presets: [], activePresetID: nil, nextPresetName: "Version 2")
            var snapshot = DialKitSessionSnapshot(appName: "Probe", panels: [panel])
            snapshot.acknowledgedEditID = editID
            service.handle(.snapshot(snapshot))
        }
        send(20)
        var editing = DialSliderEditingState()
        XCTAssertTrue(editing.commit(50, remote: 20, step: 1))
        let editID = service.setControlValue(panelID: panelID, path: source.path, value: .number(50))
        var received: [(Double, Double?)] = []
        var displayed: [Double] = []
        let host = NSHostingView(rootView: SliderProbe(service: service, source: source,
            received: { received.append(($0, $1)) }, displayed: { displayed.append($0) }, editing: editing))
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 120, height: 60),
                              styleMask: .borderless, backing: .buffered, defer: false)
        window.contentView = host
        host.layoutSubtreeIfNeeded()
        try await Task.sleep(for: .milliseconds(100))
        // The network decoder delivers consecutive frames in the same turn.
        let acknowledgedValue = adjusted ? 45.0 : 50.0
        send(acknowledgedValue, editID: adjusted ? editID : nil)
        send(60)
        host.layoutSubtreeIfNeeded()
        try await Task.sleep(for: .milliseconds(100))
        send(70)
        host.layoutSubtreeIfNeeded()
        try await Task.sleep(for: .milliseconds(100))
        XCTAssertTrue(received.contains { $0.0 == acknowledgedValue && $0.1 == nil }, "Receive the acknowledgement even when it never renders")
        XCTAssertEqual(received.last?.0, 70)
        XCTAssertNil(received.last?.1)
        XCTAssertEqual(displayed.last, 70)
        withExtendedLifetime(window) {}
    }

    func testMotionSourcesReadOnlyTheirOwnPanelPathAndField() {
        let panelID = UUID()
        let source = DialSliderValueSource(panelID: panelID, path: "motion")
        func snapshot(_ kind: DialKitControlKind) -> DialKitSessionSnapshot {
            .init(appName: "Test", panels: [.init(id: panelID, name: "Test",
                controls: [.init(path: "motion", label: "Motion", kind: kind)],
                presets: [], activePresetID: nil, nextPresetName: "Version 2")])
        }
        let time = snapshot(.spring(value: .time(duration: 0.4, bounce: 0.2)))
        XCTAssertEqual(source.component(.duration).value(in: time), 0.4)
        XCTAssertEqual(source.component(.bounce).value(in: time), 0.2)
        XCTAssertNil(source.component(.mass).value(in: time))
        let physics = snapshot(.spring(value: .physics(stiffness: 200, damping: 25, mass: 1)))
        XCTAssertEqual(source.component(.stiffness).value(in: physics), 200)
        XCTAssertEqual(source.component(.damping).value(in: physics), 25)
        XCTAssertEqual(source.component(.mass).value(in: physics), 1)
        let easing = snapshot(.transition(value: .easing(duration: 0.7, bezier: .standard)))
        XCTAssertEqual(source.component(.duration).value(in: easing), 0.7)
        XCTAssertEqual(source.component(.x1).value(in: easing), 0.25)
        XCTAssertEqual(source.component(.y1).value(in: easing), 0.1)
        XCTAssertEqual(source.component(.x2).value(in: easing), 0.25)
        XCTAssertEqual(source.component(.y2).value(in: easing), 1)
        XCTAssertNil(DialSliderValueSource(panelID: UUID(), path: "motion").component(.duration).value(in: easing))
        XCTAssertNil(DialSliderValueSource(panelID: panelID, path: "other").component(.duration).value(in: easing))
    }
}
