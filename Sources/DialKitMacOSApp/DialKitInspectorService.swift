import Combine
import Foundation
import Network
import DialkitmacOSProtocol

@MainActor
final class DialKitInspectorService: ObservableObject {
    @Published private(set) var snapshot: DialKitSessionSnapshot?
    @Published private(set) var status = "Waiting for app"
    @Published private(set) var lastLog: String?

    private let queue = DispatchQueue(label: "DialKitInspector.network")
    private var listener: NWListener?
    private var connection: NWConnection?
    private var receiveBuffer = Data()
    private var handshakeTimeout: Task<Void, Never>?
    private var healthCheck: Task<Void, Never>?
    private var lastSnapshotAt: ContinuousClock.Instant?
    private let healthCheckInterval: Duration
    private let responseTimeout: Duration
    private final class Candidate {
        let connection: NWConnection
        var buffer = Data()
        var timeout: Task<Void, Never>?

        init(_ connection: NWConnection) { self.connection = connection }
        deinit { timeout?.cancel() }
    }
    private var candidates: [ObjectIdentifier: Candidate] = [:]
    private var latestPreviewSessions: [String: DialKitPreviewSession] = [:]
    @Published private(set) var listeningPort: UInt16?
    private let port: UInt16?
    private struct ControlAddress: Hashable {
        let panelID: UUID
        let path: String
    }
    private var latestEdits: [ControlAddress: UUID] = [:]

    init(
        port: UInt16? = DialKitConnectionDefaults.port,
        healthCheckInterval: Duration = .seconds(2),
        responseTimeout: Duration = .seconds(8)
    ) {
        self.port = port
        self.healthCheckInterval = healthCheckInterval
        self.responseTimeout = responseTimeout
        startListening()
    }

    deinit {
        handshakeTimeout?.cancel()
        healthCheck?.cancel()
        listener?.cancel()
        connection?.cancel()
        for candidate in candidates.values { candidate.connection.cancel() }
    }

    func requestSnapshot() {
        if listener == nil { startListening() }
        send(.requestSnapshot)
    }

    @discardableResult
    func setControlValue(panelID: UUID, path: String, value: DialKitControlValue) -> UUID {
        let editID = UUID()
        latestEdits[ControlAddress(panelID: panelID, path: path)] = editID
        send(.setControlValue(panelID: panelID, path: path, value: value, editID: editID))
        return editID
    }

    func triggerAction(panelID: UUID, path: String) {
        send(.triggerAction(panelID: panelID, path: path))
    }

    @discardableResult
    func setMotionComponent(panelID: UUID, path: String, component: DialKitMotionComponent) -> UUID {
        let editID = UUID()
        latestEdits[ControlAddress(panelID: panelID, path: path)] = editID
        send(.setMotionComponent(panelID: panelID, path: path, component: component, editID: editID))
        return editID
    }

    func acknowledgesLatestEdit(_ snapshot: DialKitSessionSnapshot, panelID: UUID, path: String) -> Bool {
        guard let editID = snapshot.acknowledgedEditID else { return false }
        return latestEdits[ControlAddress(panelID: panelID, path: path)] == editID
    }

    func savePreset(panelID: UUID, name: String) {
        send(.savePreset(panelID: panelID, name: name))
    }

    func loadPreset(panelID: UUID, presetID: UUID) {
        send(.loadPreset(panelID: panelID, presetID: presetID))
    }

    func clearActivePreset(panelID: UUID) {
        send(.clearActivePreset(panelID: panelID))
    }

    func deletePreset(panelID: UUID, presetID: UUID) {
        send(.deletePreset(panelID: panelID, presetID: presetID))
    }

    private func startListening() {
        guard listener == nil else {
            return
        }

        do {
            let nwPort: NWEndpoint.Port
            if let port {
                guard let validatedPort = NWEndpoint.Port(rawValue: port) else {
                    status = "Invalid port \(port)"
                    return
                }
                nwPort = validatedPort
            } else {
                nwPort = .any
            }

            // Bind to loopback only. The inspector is a local development tool and
            // must not accept connections from other machines on the network.
            let parameters = NWParameters.tcp
            parameters.requiredLocalEndpoint = .hostPort(
                host: NWEndpoint.Host(DialKitConnectionDefaults.host),
                port: nwPort
            )

            let listener = try NWListener(using: parameters)
            self.listener = listener
            status = "Starting listener"

            listener.newConnectionHandler = { [weak self] connection in
                Task { @MainActor [weak self] in
                    self?.accept(connection)
                }
            }

            listener.stateUpdateHandler = { [weak self] state in
                Task { @MainActor [weak self] in
                    self?.handleListenerState(state)
                }
            }

            listener.start(queue: queue)
        } catch {
            status = "Could not listen: \(error.localizedDescription)"
        }
    }

    private func handleListenerState(_ state: NWListener.State) {
        switch state {
        case .ready:
            listeningPort = listener?.port?.rawValue
            status = connection == nil ? "Listening on \(DialKitConnectionDefaults.host):\(listeningPort ?? 0)" : status
        case let .failed(error):
            listener?.cancel()
            listener = nil
            listeningPort = nil
            if error == .posix(.EADDRINUSE) {
                status = "Another DialKit inspector is already running. Close it, then Refresh."
            } else {
                status = "Listener failed: \(error.localizedDescription)"
            }
        default:
            break
        }
    }

    private func accept(_ newConnection: NWConnection) {
        // Ordinary apps retain their connection. A newer preview of the same
        // app may take over, but only after a complete, bounded handshake.
        guard connection == nil else {
            if snapshot?.previewSession != nil {
                inspectCandidate(newConnection)
            } else {
                newConnection.cancel()
            }
            return
        }
        adopt(newConnection)
    }

    private func adopt(_ newConnection: NWConnection, initial: DialKitSessionSnapshot? = nil, buffer: Data = Data()) {
        connection?.cancel()
        connection = newConnection
        latestEdits.removeAll()
        snapshot = nil
        lastLog = nil
        receiveBuffer = buffer
        status = "Connecting..."
        lastSnapshotAt = nil
        healthCheck?.cancel()
        handshakeTimeout?.cancel()
        handshakeTimeout = Task { @MainActor [weak self, weak newConnection] in
            do { try await Task.sleep(for: .seconds(5)) }
            catch { return }
            guard let self, let newConnection,
                  self.connection === newConnection, self.snapshot == nil else { return }
            self.dropCurrentConnection()
        }

        newConnection.stateUpdateHandler = { [weak self, weak newConnection] state in
            Task { @MainActor [weak self, weak newConnection] in
                guard let newConnection else { return }
                self?.handleConnectionState(state, connection: newConnection)
            }
        }

        if let initial { handle(.hello(initial)) }
        startHealthCheck(for: newConnection)
        receive(on: newConnection)
        if initial == nil { newConnection.start(queue: queue) }
    }

    private func startHealthCheck(for connection: NWConnection) {
        let interval = healthCheckInterval
        healthCheck = Task { @MainActor [weak self, weak connection] in
            while !Task.isCancelled {
                do { try await Task.sleep(for: interval) }
                catch { return }
                guard let self, let connection, self.connection === connection else { return }
                // The initial handshake has its own timeout. Once connected,
                // require actual app responses, not merely an open TCP socket.
                guard let lastSnapshotAt = self.lastSnapshotAt else { continue }
                if lastSnapshotAt.duration(to: .now) >= self.responseTimeout {
                    self.dropCurrentConnection()
                    return
                }
                self.send(.requestSnapshot)
            }
        }
    }

    private func inspectCandidate(_ connection: NWConnection) {
        guard candidates.count < 8 else { connection.cancel(); return }
        let candidate = Candidate(connection)
        let key = ObjectIdentifier(connection)
        candidates[key] = candidate
        candidate.timeout = Task { @MainActor [weak self] in
            do { try await Task.sleep(for: .seconds(5)) }
            catch { return }
            self?.discardCandidate(key)
        }
        receiveCandidate(candidate)
        connection.start(queue: queue)
    }

    private func discardCandidate(_ key: ObjectIdentifier) {
        guard let candidate = candidates.removeValue(forKey: key) else { return }
        candidate.timeout?.cancel()
        candidate.connection.cancel()
    }

    private func receiveCandidate(_ candidate: Candidate) {
        let key = ObjectIdentifier(candidate.connection)
        candidate.connection.receive(minimumIncompleteLength: 1, maximumLength: 64 * 1024) { [weak self] data, _, complete, error in
            Task { @MainActor [weak self] in
                guard let self, let candidate = self.candidates[key] else { return }
                guard error == nil, !complete else { self.discardCandidate(key); return }
                if let data { candidate.buffer.append(data) }
                do {
                    let messages = try DialKitWireCodec.decodeAvailableMessages(from: &candidate.buffer, as: DialKitAgentMessage.self)
                    if let first = messages.first {
                        guard case let .hello(incoming) = first,
                              let preview = incoming.previewSession,
                              !self.isRetired(preview),
                              self.canReplaceCurrentSession(with: preview) else {
                            self.discardCandidate(key)
                            return
                        }
                        self.candidates[key] = nil
                        candidate.timeout?.cancel()
                        self.adopt(candidate.connection, initial: incoming, buffer: candidate.buffer)
                        for message in messages.dropFirst() {
                            guard self.connection === candidate.connection else { return }
                            self.handle(message)
                        }
                        return
                    }
                } catch {
                    self.discardCandidate(key)
                    return
                }
                self.receiveCandidate(candidate)
            }
        }
    }

    private func canReplaceCurrentSession(with preview: DialKitPreviewSession) -> Bool {
        if connection == nil { return true }
        guard let current = snapshot?.previewSession else { return false }
        return current.appID == preview.appID && preview.startedAt > current.startedAt
    }

    private func isRetired(_ preview: DialKitPreviewSession) -> Bool {
        guard let latest = latestPreviewSessions[preview.appID] else { return false }
        return preview.id != latest.id && preview.startedAt <= latest.startedAt
    }

    private func handleConnectionState(_ state: NWConnection.State, connection: NWConnection) {
        guard self.connection === connection else {
            return
        }

        switch state {
        case .ready:
            status = snapshot.map { "Connected to \($0.appName)" } ?? "Connected"
            requestSnapshot()
        case .failed, .cancelled:
            dropCurrentConnection()
        default:
            break
        }
    }

    private func dropCurrentConnection() {
        healthCheck?.cancel()
        healthCheck = nil
        lastSnapshotAt = nil
        handshakeTimeout?.cancel()
        handshakeTimeout = nil
        connection?.cancel()
        connection = nil
        latestEdits.removeAll()
        snapshot = nil
        receiveBuffer.removeAll()
        status = "Waiting for app"
    }

    private func receive(on connection: NWConnection) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 64 * 1024) { [weak self] data, _, isComplete, error in
            Task { @MainActor [weak self] in
                self?.handleReceive(data: data, isComplete: isComplete, error: error, connection: connection)
            }
        }
    }

    private func handleReceive(data: Data?, isComplete: Bool, error: NWError?, connection: NWConnection) {
        guard self.connection === connection else {
            // Stale callback from a connection that has already been replaced.
            return
        }

        if let data, !data.isEmpty {
            receiveBuffer.append(data)

            do {
                let messages = try DialKitWireCodec.decodeAvailableMessages(
                    from: &receiveBuffer,
                    as: DialKitAgentMessage.self,
                    onDecodingError: { error in
                        self.lastLog = "Could not decode app message: \(error.localizedDescription)"
                    }
                )

                for message in messages {
                    handle(message)
                    guard self.connection === connection else { return }
                }
            } catch {
                lastLog = "Could not decode app message: \(error.localizedDescription)"
                if error as? DialKitWireError == .frameTooLarge {
                    dropCurrentConnection()
                    return
                }
            }
        }

        guard error == nil, !isComplete else {
            dropCurrentConnection()
            return
        }

        receive(on: connection)
    }

    func handle(_ message: DialKitAgentMessage) {
        switch message {
        case let .hello(snapshot), let .snapshot(snapshot):
            if let preview = snapshot.previewSession {
                guard !isRetired(preview) else { dropCurrentConnection(); return }
                latestPreviewSessions[preview.appID] = preview
            }
            handshakeTimeout?.cancel()
            handshakeTimeout = nil
            lastSnapshotAt = .now
            self.snapshot = snapshot
            status = "Connected to \(snapshot.appName)"
        case let .log(text):
            lastLog = text
        }
    }

    private func send(_ message: DialKitInspectorMessage) {
        guard let connection else {
            return
        }

        do {
            let data = try DialKitWireCodec.encode(message)
            connection.send(content: data, completion: .contentProcessed { [weak self, weak connection] error in
                guard error != nil else { return }
                Task { @MainActor [weak self, weak connection] in
                    guard let self, let connection, self.connection === connection else { return }
                    self.dropCurrentConnection()
                }
            })
        } catch {
            lastLog = "Could not encode inspector message: \(error.localizedDescription)"
        }
    }
}
