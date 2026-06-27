import Combine
import Foundation
import Network
import DialKitCore
import DialKitProtocol

@MainActor
public final class DialKitAgent {
    public static let shared = DialKitAgent()

    private let queue = DispatchQueue(label: "DialKitAgent.network")
    private var connection: NWConnection?
    private var receiveBuffer = Data()
    private var storeCancellable: AnyCancellable?
    private var reconnectWorkItem: DispatchWorkItem?
    private var appName = "App"
    private var host = DialKitConnectionDefaults.host
    private var port = DialKitConnectionDefaults.port
    private var isRunning = false

    private init() {}

    public func start(
        appName: String? = nil,
        host: String = DialKitConnectionDefaults.host,
        port: UInt16 = DialKitConnectionDefaults.port
    ) {
        stop()

        self.appName = appName ?? Self.defaultAppName
        self.host = host
        self.port = port
        isRunning = true

        storeCancellable = DialStore.shared.objectWillChange
            .debounce(for: .milliseconds(80), scheduler: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.sendSnapshot()
            }

        connect()
    }

    public func stop() {
        isRunning = false
        reconnectWorkItem?.cancel()
        reconnectWorkItem = nil
        storeCancellable = nil
        receiveBuffer.removeAll()
        connection?.cancel()
        connection = nil
    }

    public func sendSnapshot() {
        send(.snapshot(DialStore.shared.remoteSnapshot(appName: appName)))
    }

    private func connect() {
        guard isRunning else {
            return
        }

        receiveBuffer.removeAll()

        guard let nwPort = NWEndpoint.Port(rawValue: port) else {
            sendLog("Invalid DialKit port: \(port)")
            return
        }

        let connection = NWConnection(host: NWEndpoint.Host(host), port: nwPort, using: .tcp)
        self.connection = connection

        connection.stateUpdateHandler = { [weak self] state in
            Task { @MainActor in
                self?.handleStateUpdate(state)
            }
        }

        receive(on: connection)
        connection.start(queue: queue)
    }

    private func handleStateUpdate(_ state: NWConnection.State) {
        switch state {
        case .ready:
            send(.hello(DialStore.shared.remoteSnapshot(appName: appName)))
        case .failed, .cancelled:
            if isRunning {
                scheduleReconnect()
            }
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
                    as: DialKitInspectorMessage.self
                )

                for message in messages {
                    handle(message)
                }
            } catch {
                sendLog("Could not decode inspector message: \(error.localizedDescription)")
            }
        }

        guard error == nil, !isComplete, self.connection === connection else {
            scheduleReconnect()
            return
        }

        receive(on: connection)
    }

    private func handle(_ message: DialKitInspectorMessage) {
        switch message {
        case .requestSnapshot:
            sendSnapshot()
        case let .setControlValue(panelID, path, value):
            if DialStore.shared.setRemoteControlValue(panelID: panelID, path: path, value: value) {
                sendSnapshot()
            }
        case let .triggerAction(panelID, path):
            if DialStore.shared.triggerRemoteAction(panelID: panelID, path: path) {
                sendSnapshot()
            }
        case let .savePreset(panelID, name):
            if DialStore.shared.saveRemotePreset(panelID: panelID, name: name) {
                sendSnapshot()
            }
        case let .loadPreset(panelID, presetID):
            if DialStore.shared.loadRemotePreset(panelID: panelID, presetID: presetID) {
                sendSnapshot()
            }
        case let .clearActivePreset(panelID):
            if DialStore.shared.clearRemoteActivePreset(panelID: panelID) {
                sendSnapshot()
            }
        case let .deletePreset(panelID, presetID):
            if DialStore.shared.deleteRemotePreset(panelID: panelID, presetID: presetID) {
                sendSnapshot()
            }
        }
    }

    private func send(_ message: DialKitAgentMessage) {
        guard let connection else {
            return
        }

        do {
            let data = try DialKitWireCodec.encode(message)
            connection.send(content: data, completion: .contentProcessed { _ in })
        } catch {
            sendLog("Could not encode agent message: \(error.localizedDescription)")
        }
    }

    private func sendLog(_ text: String) {
        guard let connection else {
            return
        }

        guard let data = try? DialKitWireCodec.encode(DialKitAgentMessage.log(text)) else {
            return
        }

        connection.send(content: data, completion: .contentProcessed { _ in })
    }

    private func scheduleReconnect() {
        guard isRunning else {
            return
        }

        reconnectWorkItem?.cancel()
        let item = DispatchWorkItem { [weak self] in
            Task { @MainActor in
                self?.connect()
            }
        }
        reconnectWorkItem = item
        queue.asyncAfter(deadline: .now() + 1.0, execute: item)
    }

    private static var defaultAppName: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String
            ?? Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as? String
            ?? "App"
    }
}
