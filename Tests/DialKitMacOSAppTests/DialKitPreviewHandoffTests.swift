import Network
import XCTest
import DialkitmacOSProtocol
@testable import DialkitmacOSAgent
@testable import DialkitmacOSApp

@MainActor
final class DialKitPreviewHandoffTests: XCTestCase {
    func testExplicitResumeReclaimsPreviewButAutomaticRetriesDoNot() async throws {
        let service = DialKitInspectorService(port: nil, healthCheckInterval: .milliseconds(50), responseTimeout: .seconds(1))
        try await waitUntil { service.listeningPort != nil }
        let port = try XCTUnwrap(service.listeningPort)
        let first = DialKitAgent(previewAppID: "scroll.options")
        let second = DialKitAgent(previewAppID: "scroll.options")
        defer { first.stop(); second.stop() }
        first.start(appName: "First preview", port: port)
        try await waitUntil { service.snapshot?.appName == "First preview" }
        let firstActivation = try XCTUnwrap(service.snapshot?.previewSession)
        second.start(appName: "Second preview", port: port)
        try await waitUntil { service.snapshot?.appName == "Second preview" }
        let secondActivation = service.snapshot?.previewSession
        // Old retries must not steal the socket; health probes keep the idle
        // selected preview connected for longer than the response timeout.
        try await Task.sleep(for: .milliseconds(1200))
        XCTAssertEqual(service.snapshot?.previewSession, secondActivation)
        first.start(appName: "First preview", port: port)
        try await waitUntil { service.snapshot?.appName == "First preview" }
        let resumedActivation = try XCTUnwrap(service.snapshot?.previewSession)
        XCTAssertNotEqual(resumedActivation.id, firstActivation.id)
        XCTAssertGreaterThan(resumedActivation.startedAt, firstActivation.startedAt)
        try await Task.sleep(for: .milliseconds(1200))
        XCTAssertEqual(service.snapshot?.previewSession, resumedActivation)
    }

    func testPausedSocketIsReleasedAndSameSessionCanReconnectOnResume() async throws {
        let service = DialKitInspectorService(port: nil, healthCheckInterval: .milliseconds(50), responseTimeout: .milliseconds(300))
        try await waitUntil { service.listeningPort != nil }
        let port = try XCTUnwrap(service.listeningPort)
        let original = snapshot(time: 100)
        let paused = Peer(port: port, snapshot: original)
        defer { paused.connection.cancel() }
        try await waitUntil { service.snapshot?.id == original.id }
        paused.respondsToRequests = false
        try await waitUntil { service.snapshot == nil }
        XCTAssertEqual(service.status, "Waiting for app")

        let resumed = Peer(port: port, snapshot: original)
        defer { resumed.connection.cancel() }
        try await waitUntil { service.snapshot?.id == original.id }
        try await Task.sleep(for: .milliseconds(450))
        XCTAssertEqual(service.snapshot?.previewSession, original.previewSession)
        let panelID = UUID()
        let editID = service.setControlValue(panelID: panelID, path: "value", value: .number(42))
        try await waitUntil {
            resumed.messages.contains(.setControlValue(panelID: panelID, path: "value", value: .number(42), editID: editID))
        }
    }

    func testNewPreviewTakesOverAndOlderRetriesCannotStealConnection() async throws {
        let service = DialKitInspectorService(port: nil)
        try await waitUntil { service.listeningPort != nil }
        let port = try XCTUnwrap(service.listeningPort)
        let original = snapshot(time: 100)
        let replacement = snapshot(time: 200)
        let old = Peer(port: port, snapshot: original)
        defer { old.connection.cancel() }
        try await waitUntil { service.snapshot?.id == original.id }
        let current = Peer(port: port, snapshot: replacement)
        defer { current.connection.cancel() }
        try await waitUntil { service.snapshot?.id == replacement.id }

        // Keep the superseded process alive and retry, as Xcode does.
        for competitorSnapshot in [original, snapshot(time: 300, appID: "other.app"),
                                   DialKitSessionSnapshot(appName: "Regular app", panels: [])] {
            let competitor = Peer(port: port, snapshot: competitorSnapshot)
            try await Task.sleep(for: .milliseconds(150))
            competitor.connection.cancel()
            XCTAssertEqual(service.snapshot?.id, replacement.id)
        }
        let panelID = UUID()
        let editID = service.setControlValue(panelID: panelID, path: "value", value: .number(42))
        try await waitUntil {
            current.messages.contains(.setControlValue(panelID: panelID, path: "value", value: .number(42), editID: editID))
        }
        XCTAssertFalse(old.messages.contains(.setControlValue(panelID: panelID, path: "value", value: .number(42), editID: editID)))

        // An old process must not reclaim the slot during a restart gap.
        current.connection.cancel()
        try await waitUntil { service.snapshot == nil }
        let retiredRetry = Peer(port: port, snapshot: original)
        defer { retiredRetry.connection.cancel() }
        try await Task.sleep(for: .milliseconds(150))
        XCTAssertNil(service.snapshot)
        let reconnected = Peer(port: port, snapshot: replacement)
        defer { reconnected.connection.cancel() }
        try await waitUntil { service.snapshot?.id == replacement.id }
    }

    func testIncompletePreviewHandshakeDoesNotInterruptActivePreview() async throws {
        let service = DialKitInspectorService(port: nil)
        try await waitUntil { service.listeningPort != nil }
        let port = try XCTUnwrap(service.listeningPort)
        let original = snapshot(time: 100)
        let active = Peer(port: port, snapshot: original)
        defer { active.connection.cancel() }
        try await waitUntil { service.snapshot?.id == original.id }
        let silent = NWConnection(host: "127.0.0.1", port: NWEndpoint.Port(rawValue: port)!, using: .tcp)
        silent.start(queue: DispatchQueue(label: "Silent preview"))
        defer { silent.cancel() }
        try await Task.sleep(for: .milliseconds(150))
        XCTAssertEqual(service.snapshot?.id, original.id)
    }

    private func snapshot(time: TimeInterval, appID: String = "scroll.options") -> DialKitSessionSnapshot {
        var snapshot = DialKitSessionSnapshot(appName: "Scroll Options Preview", panels: [])
        snapshot.previewSession = .init(appID: appID, startedAt: Date(timeIntervalSince1970: time))
        return snapshot
    }

    private func waitUntil(_ predicate: () -> Bool) async throws {
        let deadline = Date().addingTimeInterval(4)
        while !predicate() {
            if Date() > deadline { throw NSError(domain: "Preview handoff timeout", code: 1) }
            try await Task.sleep(for: .milliseconds(10))
        }
    }

    @MainActor
    private final class Peer {
        let connection: NWConnection
        var messages: [DialKitInspectorMessage] = []
        var respondsToRequests = true
        private let snapshot: DialKitSessionSnapshot
        private var buffer = Data()

        init(port: UInt16, snapshot: DialKitSessionSnapshot) {
            self.snapshot = snapshot
            connection = NWConnection(host: "127.0.0.1", port: NWEndpoint.Port(rawValue: port)!, using: .tcp)
            connection.start(queue: DispatchQueue(label: "Preview peer"))
            connection.send(content: try! DialKitWireCodec.encode(DialKitAgentMessage.hello(snapshot)), completion: .contentProcessed { _ in })
            receive()
        }

        private func receive() {
            connection.receive(minimumIncompleteLength: 1, maximumLength: 64 * 1024) { [weak self] data, _, complete, error in
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    if let data {
                        self.buffer.append(data)
                        let incoming = (try? DialKitWireCodec.decodeAvailableMessages(from: &self.buffer, as: DialKitInspectorMessage.self)) ?? []
                        self.messages += incoming
                        if self.respondsToRequests, incoming.contains(.requestSnapshot) {
                            self.connection.send(content: try? DialKitWireCodec.encode(DialKitAgentMessage.snapshot(self.snapshot)), completion: .contentProcessed { _ in })
                        }
                    }
                    if !complete && error == nil { self.receive() }
                }
            }
        }
    }
}
