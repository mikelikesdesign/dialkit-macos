import Foundation

public enum DialKitConnectionDefaults {
    public static let host = "127.0.0.1"
    public static let port: UInt16 = 44777
}

public struct DialKitSessionSnapshot: Codable, Equatable, Identifiable {
    public var id: UUID
    public var appName: String
    public var panels: [DialKitPanelSnapshot]
    /// Identifies the inspector edit processed before this snapshot was captured.
    public var acknowledgedEditID: UUID?
    /// Present only for Xcode Previews. Older peers omit this metadata.
    public var previewSession: DialKitPreviewSession?

    public init(id: UUID = UUID(), appName: String, panels: [DialKitPanelSnapshot]) {
        self.id = id
        self.appName = appName
        self.panels = panels
    }
}

/// Identifies an explicit preview activation, independently of automatic retries.
public struct DialKitPreviewSession: Codable, Equatable {
    public var id: UUID
    public var appID: String
    public var startedAt: Date

    public init(id: UUID = UUID(), appID: String, startedAt: Date = Date()) {
        self.id = id
        self.appID = appID
        self.startedAt = startedAt
    }
}

public struct DialKitPanelSnapshot: Codable, Equatable, Identifiable {
    public var id: UUID
    public var name: String
    public var controls: [DialKitControlSnapshot]
    public var presets: [DialKitPresetSnapshot]
    public var activePresetID: UUID?
    public var nextPresetName: String

    public init(
        id: UUID,
        name: String,
        controls: [DialKitControlSnapshot],
        presets: [DialKitPresetSnapshot],
        activePresetID: UUID?,
        nextPresetName: String
    ) {
        self.id = id
        self.name = name
        self.controls = controls
        self.presets = presets
        self.activePresetID = activePresetID
        self.nextPresetName = nextPresetName
    }
}

public struct DialKitPresetSnapshot: Codable, Equatable, Identifiable {
    public var id: UUID
    public var name: String

    public init(id: UUID, name: String) {
        self.id = id
        self.name = name
    }
}

public struct DialKitControlSnapshot: Codable, Equatable, Identifiable {
    public var path: String
    public var label: String
    public var kind: DialKitControlKind
    /// Older snapshots omit this field. Missing metadata uses exact Double matching.
    public var numericType: DialKitSliderValueType?

    public var id: String { path }

    public init(path: String, label: String, kind: DialKitControlKind, numericType: DialKitSliderValueType? = nil) {
        self.path = path
        self.label = label
        self.kind = kind
        self.numericType = numericType
    }
}

public enum DialKitSliderValueType: String, Codable {
    case double
    case float
}

public indirect enum DialKitControlKind: Codable, Equatable {
    case slider(value: Double, lowerBound: Double, upperBound: Double, step: Double, unit: String?)
    case toggle(value: Bool)
    case text(value: String, placeholder: String?)
    case color(value: String)
    case select(value: String, options: [DialKitOptionSnapshot])
    case spring(value: DialKitSpringValue)
    case transition(value: DialKitTransitionValue)
    case group(collapsed: Bool, controls: [DialKitControlSnapshot])
    case action
}

public struct DialKitOptionSnapshot: Codable, Equatable, Identifiable {
    public var value: String
    public var label: String

    public var id: String { value }

    public init(value: String, label: String) {
        self.value = value
        self.label = label
    }
}

public enum DialKitControlValue: Codable, Equatable {
    case number(Double)
    case bool(Bool)
    case string(String)
    case spring(DialKitSpringValue)
    case transition(DialKitTransitionValue)
}

public enum DialKitSpringValue: Codable, Equatable {
    case time(duration: Double, bounce: Double)
    case physics(stiffness: Double, damping: Double, mass: Double)
}

public struct DialKitBezierValue: Codable, Equatable {
    public var x1: Double
    public var y1: Double
    public var x2: Double
    public var y2: Double

    public init(x1: Double, y1: Double, x2: Double, y2: Double) {
        self.x1 = x1
        self.y1 = y1
        self.x2 = x2
        self.y2 = y2
    }

    public static let standard = DialKitBezierValue(x1: 0.25, y1: 0.1, x2: 0.25, y2: 1)
}

public enum DialKitTransitionValue: Codable, Equatable {
    case easing(duration: Double, bezier: DialKitBezierValue)
    case spring(DialKitSpringValue)
}

public enum DialKitAgentMessage: Codable, Equatable {
    case hello(DialKitSessionSnapshot)
    case snapshot(DialKitSessionSnapshot)
    case log(String)
}

public enum DialKitInspectorMessage: Codable, Equatable {
    case requestSnapshot
    case setControlValue(panelID: UUID, path: String, value: DialKitControlValue, editID: UUID? = nil)
    case setMotionComponent(panelID: UUID, path: String, component: DialKitMotionComponent, editID: UUID? = nil)
    case triggerAction(panelID: UUID, path: String)
    case savePreset(panelID: UUID, name: String)
    case loadPreset(panelID: UUID, presetID: UUID)
    case clearActivePreset(panelID: UUID)
    case deletePreset(panelID: UUID, presetID: UUID)
}

public enum DialKitWireCodec {
    private static let newline = UInt8(10)
    public static let maximumFrameBytes = 1024 * 1024

    public static func encode<Message: Encodable>(_ message: Message) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        var data = try encoder.encode(message)
        guard data.count <= maximumFrameBytes else { throw DialKitWireError.frameTooLarge }
        data.append(newline)
        return data
    }

    /// Decodes complete frames independently. Malformed frames are reported and
    /// skipped without losing valid neighbours; incomplete frames remain buffered.
    public static func decodeAvailableMessages<Message: Decodable>(
        from buffer: inout Data,
        as type: Message.Type,
        onDecodingError: (Error) -> Void = { _ in }
    ) throws -> [Message] {
        var messages: [Message] = []
        let decoder = JSONDecoder()

        while let newlineIndex = buffer.firstIndex(of: newline) {
            let line = buffer[..<newlineIndex]
            guard line.count <= maximumFrameBytes else {
                buffer.removeAll()
                throw DialKitWireError.frameTooLarge
            }
            buffer.removeSubrange(...newlineIndex)

            guard !line.isEmpty else {
                continue
            }

            do {
                let message = try decoder.decode(Message.self, from: Data(line))
                if let agentMessage = message as? DialKitAgentMessage {
                    switch agentMessage {
                    case let .hello(snapshot), let .snapshot(snapshot):
                        guard snapshot.panels.allSatisfy({ $0.controls.allSatisfy { $0.kind.isValid } }) else {
                            throw DialKitWireError.invalidSnapshot
                        }
                    case .log: break
                    }
                }
                messages.append(message)
            } catch {
                onDecodingError(error)
            }
        }

        guard buffer.count <= maximumFrameBytes else {
            buffer.removeAll()
            throw DialKitWireError.frameTooLarge
        }

        return messages
    }
}

public enum DialKitWireError: Error, Equatable, LocalizedError {
    case frameTooLarge
    case invalidSnapshot

    public var errorDescription: String? {
        switch self {
        case .frameTooLarge: return "DialKit message exceeds the 1 MiB size limit."
        case .invalidSnapshot: return "DialKit snapshot contains invalid control parameters."
        }
    }
}
