import Combine
import Foundation
import Network
import DialkitmacOSCore
import DialkitmacOSProtocol

@MainActor
public final class DialKitAgent {
    public static let shared = DialKitAgent()

    private let queue = DispatchQueue(label: "DialKitAgent.network")
    private var connection: NWConnection?
    private var receiveBuffer = Data()
    private var storeCancellable: AnyCancellable?
    private var reconnectTask: Task<Void, Never>?
    private var appName = "App"
    private var host = DialKitConnectionDefaults.host
    private var port = DialKitConnectionDefaults.port
    private var isRunning = false
    private let previewAppID: String?
    // Explicit starts identify a new activation; automatic retries retain it.
    private var previewSession: DialKitPreviewSession?

    private convenience init() {
        self.init(previewAppID: ProcessInfo.processInfo.environment["XCODE_RUNNING_FOR_PREVIEWS"] == "1"
            ? Bundle.main.bundleIdentifier ?? Bundle.main.bundleURL.lastPathComponent
            : nil)
    }

    init(previewAppID: String?) {
        self.previewAppID = previewAppID
    }

    public func start(
        appName: String? = nil,
        host: String = DialKitConnectionDefaults.host,
        port: UInt16 = DialKitConnectionDefaults.port
    ) {
        let resolvedAppName = appName ?? Self.defaultAppName
        if let previewAppID {
            // Resuming a canvas may reuse a process superseded by a different
            // preview. Only this explicit activation may reclaim its connection.
            previewSession = DialKitPreviewSession(appID: previewAppID)
        }

        // Calling start() again keeps a healthy connection and refreshes the
        // app name and preview activation. This is common in Xcode Previews, where a
        // `.task` that starts the agent re-runs whenever the view is recreated.
        if isRunning, self.host == host, self.port == port {
            self.appName = resolvedAppName
            if connection == nil { connect() }
            else { sendSnapshot() }
            return
        }

        stop()

        self.appName = resolvedAppName
        self.host = host
        self.port = port
        isRunning = true

        storeCancellable = DialStore.shared.objectWillChange
            .throttle(for: .milliseconds(80), scheduler: DispatchQueue.main, latest: true)
            // objectWillChange fires before the model is updated. Deliver on the
            // next main-queue turn so even the first throttled event reads new values.
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.sendSnapshot()
            }

        connect()
    }

    public func stop() {
        isRunning = false
        reconnectTask?.cancel()
        reconnectTask = nil
        storeCancellable = nil
        receiveBuffer.removeAll()
        connection?.cancel()
        connection = nil
    }

    public func sendSnapshot() {
        sendSnapshot(acknowledging: nil)
    }

    private func sendSnapshot(acknowledging editID: UUID?) {
        var snapshot = DialStore.shared.remoteSnapshot(appName: appName)
        snapshot.previewSession = previewSession
        snapshot.acknowledgedEditID = editID
        send(.snapshot(snapshot))
    }

    private func connect() {
        guard isRunning else {
            return
        }

        reconnectTask?.cancel()
        reconnectTask = nil
        receiveBuffer.removeAll()

        guard let nwPort = NWEndpoint.Port(rawValue: port) else {
            sendLog("Invalid DialKit port: \(port)")
            return
        }

        // Never leave a previous connection alive when replacing it. Its
        // callbacks are ignored by the identity checks below.
        self.connection?.cancel()

        let connection = NWConnection(host: NWEndpoint.Host(host), port: nwPort, using: .tcp)
        self.connection = connection

        connection.stateUpdateHandler = { [weak self, weak connection] state in
            Task { @MainActor [weak self, weak connection] in
                guard let connection else { return }
                self?.handleStateUpdate(state, connection: connection)
            }
        }

        receive(on: connection)
        connection.start(queue: queue)
    }

    private func handleStateUpdate(_ state: NWConnection.State, connection: NWConnection) {
        guard self.connection === connection else {
            // Stale callback from a connection that was already replaced or stopped.
            return
        }

        switch state {
        case .ready:
            var snapshot = DialStore.shared.remoteSnapshot(appName: appName)
            snapshot.previewSession = previewSession
            send(.hello(snapshot))
        case .waiting, .failed, .cancelled:
            // A refused connection can remain waiting forever, even after the
            // inspector starts. Retire it before retrying so stale callbacks
            // cannot schedule a second reconnect.
            self.connection = nil
            connection.cancel()
            receiveBuffer.removeAll()
            scheduleReconnect()
        default:
            break
        }
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
            return
        }

        if let data, !data.isEmpty {
            receiveBuffer.append(data)

            do {
                let messages = try DialKitWireCodec.decodeAvailableMessages(
                    from: &receiveBuffer,
                    as: DialKitInspectorMessage.self,
                    onDecodingError: { error in
                        self.sendLog("Could not decode inspector message: \(error.localizedDescription)")
                    }
                )

                for message in messages {
                    handle(message)
                }
            } catch {
                sendLog("Could not decode inspector message: \(error.localizedDescription)")
                if error as? DialKitWireError == .frameTooLarge {
                    self.connection = nil
                    connection.cancel()
                    receiveBuffer.removeAll()
                    scheduleReconnect()
                    return
                }
            }
        }

        guard error == nil, !isComplete else {
            // The inspector closed the connection (or it failed). Tear it down
            // so the state handler cannot also schedule a competing reconnect.
            self.connection = nil
            connection.cancel()
            scheduleReconnect()
            return
        }

        receive(on: connection)
    }

    private func handle(_ message: DialKitInspectorMessage) {
        switch message {
        case .requestSnapshot:
            sendSnapshot()
        case let .setControlValue(panelID, path, value, editID):
            _ = DialStore.shared.setRemoteControlValue(panelID: panelID, path: path, value: value)
            sendSnapshot(acknowledging: editID)
        case let .setMotionComponent(panelID, path, component, editID):
            _ = DialStore.shared.setRemoteMotionComponent(panelID: panelID, path: path, component: component)
            sendSnapshot(acknowledging: editID)
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
            let outgoing: DialKitAgentMessage
            switch message {
            case let .hello(snapshot), let .snapshot(snapshot):
                let cleaned = snapshot.removingInvalidControls()
                if !cleaned.paths.isEmpty {
                    sendLog("Ignored invalid controls: \(cleaned.paths.prefix(10).joined(separator: ", "))")
                }
                if case .hello = message { outgoing = .hello(cleaned.snapshot) }
                else { outgoing = .snapshot(cleaned.snapshot) }
            case .log: outgoing = message
            }
            let data = try DialKitWireCodec.encode(outgoing)
            connection.send(content: data, completion: .contentProcessed { [weak self, weak connection] error in
                guard error != nil else { return }
                Task { @MainActor [weak self, weak connection] in
                    guard let self, let connection, self.connection === connection else { return }
                    self.connection = nil
                    connection.cancel()
                    self.receiveBuffer.removeAll()
                    self.scheduleReconnect()
                }
            })
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

        reconnectTask?.cancel()
        reconnectTask = Task { @MainActor [weak self] in
            do { try await Task.sleep(for: .seconds(1)) }
            catch { return }
            self?.connect()
        }
    }

    private static var defaultAppName: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String
            ?? Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as? String
            ?? "App"
    }
}
