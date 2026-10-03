import Network
import XCTest
import DialkitmacOSCore
import DialkitmacOSProtocol
@testable import DialkitmacOSAgent

@MainActor
final class DialKitAgentTests: XCTestCase {
    private var inspector: FakeInspector!

    override func setUp() async throws {
        try await super.setUp()
        inspector = FakeInspector()
        try await inspector.start()
    }

    override func tearDown() async throws {
        DialKitAgent.shared.stop()
        inspector.stop()
        inspector = nil
        try await super.tearDown()
    }

    func testRepeatedStartWithSameEndpointKeepsSingleConnection() async throws {
        DialKitAgent.shared.start(appName: "Test", port: inspector.port)
        DialKitAgent.shared.start(appName: "Test", port: inspector.port)
        try await Task.sleep(for: .milliseconds(300))
        DialKitAgent.shared.start(appName: "Test Preview", port: inspector.port)

        try await Task.sleep(for: .seconds(2.5))

        XCTAssertEqual(inspector.acceptCount, 1, "start() with the same endpoint must not open a new connection")
        XCTAssertEqual(inspector.helloAppNames.first, "Test")
    }

    func testAgentReconnectsExactlyOnceAfterInspectorDropsConnection() async throws {
        DialKitAgent.shared.start(appName: "Test", port: inspector.port)
        try await inspector.waitForAccepts(1)

        inspector.dropCurrentConnection()
        try await Task.sleep(for: .seconds(2.5))

        XCTAssertEqual(inspector.acceptCount, 2, "agent should reconnect once, not repeatedly")
    }

    func testAgentReconnectsAfterOversizedInspectorMessage() async throws {
        DialKitAgent.shared.start(appName: "Test", port: inspector.port)
        try await inspector.waitForAccepts(1)
        inspector.sendToCurrentConnection(Data(repeating: 65, count: DialKitWireCodec.maximumFrameBytes + 1))
        try await inspector.waitForAccepts(2)
        XCTAssertEqual(inspector.acceptCount, 2)
    }

    func testRestartOnDifferentPortDoesNotLeaveReconnectLoopBehind() async throws {
        let other = FakeInspector()
        try await other.start()
        defer { other.stop() }

        DialKitAgent.shared.start(appName: "Test", port: inspector.port)
        try await inspector.waitForAccepts(1)

        DialKitAgent.shared.start(appName: "Test", port: other.port)
        try await other.waitForAccepts(1)
        try await Task.sleep(for: .seconds(2.5))

        XCTAssertEqual(inspector.acceptCount, 1)
        XCTAssertEqual(other.acceptCount, 1)
    }
}

/// Minimal stand-in for the Mac inspector: accepts connections on an ephemeral
/// loopback port, records hello messages, and can drop the current connection.
private final class FakeInspector: @unchecked Sendable {
    private let queue = DispatchQueue(label: "FakeInspector")
    private let lock = NSLock()
    private var listener: NWListener?
    private var connections: [NWConnection] = []
    private var buffers: [ObjectIdentifier: Data] = [:]
    private var _acceptCount = 0
    private var _helloAppNames: [String] = []

    private(set) var port: UInt16 = 0

    var acceptCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return _acceptCount
    }

    var helloAppNames: [String] {
        lock.lock()
        defer { lock.unlock() }
        return _helloAppNames
    }

    func start() async throws {
        let parameters = NWParameters.tcp
        parameters.requiredLocalEndpoint = .hostPort(host: "127.0.0.1", port: .any)
        let listener = try NWListener(using: parameters)
        self.listener = listener

        listener.newConnectionHandler = { [weak self] connection in
            self?.accept(connection)
        }

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            listener.stateUpdateHandler = { [weak self] state in
                switch state {
                case .ready:
                    listener.stateUpdateHandler = nil
                    self?.port = listener.port?.rawValue ?? 0
                    continuation.resume()
                case let .failed(error):
                    listener.stateUpdateHandler = nil
                    continuation.resume(throwing: error)
                default:
                    break
                }
            }
            listener.start(queue: queue)
        }
    }

    func stop() {
        listener?.cancel()
        listener = nil
        lock.lock()
        let open = connections
        connections.removeAll()
        lock.unlock()
        open.forEach { $0.cancel() }
    }

    func dropCurrentConnection() {
        lock.lock()
        let current = connections.popLast()
        lock.unlock()
        current?.cancel()
    }

    func sendToCurrentConnection(_ data: Data) {
        lock.lock()
        let current = connections.last
        lock.unlock()
        current?.send(content: data, completion: .contentProcessed { _ in })
    }

    func waitForAccepts(_ count: Int, timeout: TimeInterval = 3) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        while acceptCount < count {
            if Date() > deadline {
                struct Timeout: Error, CustomStringConvertible {
                    let description: String
                }
                throw Timeout(description: "Timed out waiting for \(count) accepted connection(s); got \(acceptCount)")
            }
            try await Task.sleep(for: .milliseconds(50))
        }
    }

    private func accept(_ connection: NWConnection) {
        lock.lock()
        _acceptCount += 1
        connections.append(connection)
        lock.unlock()

        connection.stateUpdateHandler = { [weak self] state in
            if case .ready = state {
                self?.receive(on: connection)
            }
        }
        connection.start(queue: queue)
    }

    private func receive(on connection: NWConnection) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 64 * 1024) { [weak self] data, _, isComplete, error in
            guard let self else { return }
            if let data, !data.isEmpty {
                self.lock.lock()
                var buffer = self.buffers[ObjectIdentifier(connection)] ?? Data()
                buffer.append(data)
                if let messages = try? DialKitWireCodec.decodeAvailableMessages(from: &buffer, as: DialKitAgentMessage.self) {
                    for case let .hello(snapshot) in messages {
                        self._helloAppNames.append(snapshot.appName)
                    }
                }
                self.buffers[ObjectIdentifier(connection)] = buffer
                self.lock.unlock()
            }
            guard error == nil, !isComplete else { return }
            self.receive(on: connection)
        }
    }
}
