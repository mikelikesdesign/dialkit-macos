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
    private let port: UInt16

    init(port: UInt16 = DialKitConnectionDefaults.port) {
        self.port = port
        startListening()
    }

    func requestSnapshot() {
        send(.requestSnapshot)
    }

    func setControlValue(panelID: UUID, path: String, value: DialKitControlValue) {
        send(.setControlValue(panelID: panelID, path: path, value: value))
    }

    func triggerAction(panelID: UUID, path: String) {
        send(.triggerAction(panelID: panelID, path: path))
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
            guard let nwPort = NWEndpoint.Port(rawValue: port) else {
                status = "Invalid port \(port)"
                return
            }

            let listener = try NWListener(using: .tcp, on: nwPort)
            self.listener = listener
            status = "Listening on \(DialKitConnectionDefaults.host):\(port)"

            listener.newConnectionHandler = { [weak self] connection in
                Task { @MainActor in
                    self?.accept(connection)
                }
            }

            listener.stateUpdateHandler = { [weak self] state in
                Task { @MainActor in
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
            status = connection == nil ? "Listening on \(DialKitConnectionDefaults.host):\(port)" : status
        case let .failed(error):
            status = "Listener failed: \(error.localizedDescription)"
        default:
            break
        }
    }

    private func accept(_ newConnection: NWConnection) {
        connection?.cancel()
        connection = newConnection
        receiveBuffer.removeAll()
        status = "Connecting..."

        newConnection.stateUpdateHandler = { [weak self] state in
            Task { @MainActor in
                self?.handleConnectionState(state)
            }
        }

        receive(on: newConnection)
        newConnection.start(queue: queue)
    }

    private func handleConnectionState(_ state: NWConnection.State) {
        switch state {
        case .ready:
            status = snapshot.map { "Connected to \($0.appName)" } ?? "Connected"
            requestSnapshot()
        case .failed, .cancelled:
            status = "Waiting for app"
            connection = nil
        default:
            break
        }
    }

    private func receive(on connection: NWConnection) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 64 * 1024) { [weak self] data, _, isComplete, error in
            Task { @MainActor in
                self?.handleReceive(data: data, isComplete: isComplete, error: error, connection: connection)
            }
        }
    }

    private func handleReceive(data: Data?, isComplete: Bool, error: NWError?, connection: NWConnection) {
        if let data, !data.isEmpty {
            receiveBuffer.append(data)

            do {
                let messages = try DialKitWireCodec.decodeAvailableMessages(
                    from: &receiveBuffer,
                    as: DialKitAgentMessage.self
                )

                for message in messages {
                    handle(message)
                }
            } catch {
                lastLog = "Could not decode app message: \(error.localizedDescription)"
            }
        }

        guard error == nil, !isComplete, self.connection === connection else {
            status = "Waiting for app"
            self.connection = nil
            return
        }

        receive(on: connection)
    }

    private func handle(_ message: DialKitAgentMessage) {
        switch message {
        case let .hello(snapshot), let .snapshot(snapshot):
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
            connection.send(content: data, completion: .contentProcessed { _ in })
        } catch {
            lastLog = "Could not encode inspector message: \(error.localizedDescription)"
        }
    }
}
