import Combine
import Foundation

public final class DialPanelState<Model: Codable & Equatable>: ObservableObject, Identifiable {
    public let id: UUID

    @Published public var name: String
    @Published public var values: Model {
        didSet {
            guard !isApplyingInternalChange else { return }
            synchronizeValues()
        }
    }
    @Published public private(set) var presets: [DialPreset<Model>]
    @Published public private(set) var activePresetID: UUID?

    public private(set) var controls: [DialControl<Model>]

    private var baseValues: Model
    private var isApplyingInternalChange = false
    private let onAction: ((String) -> Void)?
    package let panelBox: AnyDialPanelBox

    public init(
        id: UUID = UUID(),
        name: String,
        initial: Model,
        controls: [DialControl<Model>],
        onAction: ((String) -> Void)? = nil
    ) {
        self.id = id
        self.name = name
        self.controls = controls
        var normalizedInitial = dialCopyModel(initial)
        for control in controls {
            control.node.normalize(current: &normalizedInitial, fallback: initial)
        }
        self.values = normalizedInitial
        self.baseValues = dialCopyModel(normalizedInitial)
        self.presets = []
        self.activePresetID = nil
        self.onAction = onAction
        self.panelBox = AnyDialPanelBox(id: id)
        self.panelBox.bind(to: self)
        DialStore.shared.register(panelBox)
    }

    deinit {
        DialStore.shared.unregister(panelBox)
    }

    public func configure(
        name: String? = nil,
        initial: Model? = nil,
        controls: [DialControl<Model>]
    ) {
        objectWillChange.send()

        let fallbackSeed = dialCopyModel(initial ?? baseValues)
        var normalizedFallback = dialCopyModel(fallbackSeed)
        for control in controls {
            control.node.normalize(current: &normalizedFallback, fallback: fallbackSeed)
        }

        var nextValues = dialCopyModel(values)
        for control in controls {
            control.node.normalize(current: &nextValues, fallback: normalizedFallback)
        }

        var nextBase = dialCopyModel(baseValues)
        for control in controls {
            control.node.normalize(current: &nextBase, fallback: normalizedFallback)
        }

        var nextPresets = presets
        for index in nextPresets.indices {
            var candidate = dialCopyModel(nextPresets[index].values)
            for control in controls {
                control.node.normalize(current: &candidate, fallback: normalizedFallback)
            }
            nextPresets[index].values = candidate
        }

        self.controls = controls
        self.baseValues = nextBase
        self.presets = nextPresets
        if let name {
            self.name = name
        }
        applyInternalValueChange(nextValues)
    }

    public func savePreset(named name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedName = trimmed.isEmpty ? nextPresetName : trimmed
        let preset = DialPreset(name: resolvedName, values: dialCopyModel(values))
        presets.append(preset)
        activePresetID = preset.id
    }

    public func loadPreset(id: UUID) {
        guard let preset = presets.first(where: { $0.id == id }) else { return }
        activePresetID = id
        applyInternalValueChange(dialCopyModel(preset.values))
    }

    public func clearActivePreset() {
        activePresetID = nil
        applyInternalValueChange(dialCopyModel(baseValues))
    }

    public func deletePreset(id: UUID) {
        let isDeletingActivePreset = activePresetID == id
        presets.removeAll { $0.id == id }
        if isDeletingActivePreset {
            clearActivePreset()
        }
    }

    public func copyInstructionText() -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]

        guard let data = try? encoder.encode(values),
              let json = String(data: data, encoding: .utf8) else {
            return ""
        }

        return """
        Update the DialKit configuration for \"\(name)\" with these values:

        ```json
        \(json)
        ```

        Apply these values as the new defaults in the DialKit configuration.
        """
    }

    package var nextPresetName: String {
        let names = Set(presets.map(\.name))
        var version = presets.count + 2
        while names.contains("Version \(version)") {
            version += 1
        }
        return "Version \(version)"
    }

    package var presetSummaries: [DialPresetSummary] {
        presets.map { DialPresetSummary(id: $0.id, name: $0.name) }
    }

    package func resolvedControls() -> [DialResolvedControl] {
        controls.flatMap { $0.node.resolve(state: self) }
    }

    package func triggerAction(path: String) {
        onAction?(path)
    }

    private func synchronizeValues() {
        if let activePresetID, let index = presets.firstIndex(where: { $0.id == activePresetID }) {
            presets[index].values = dialCopyModel(values)
        } else {
            baseValues = dialCopyModel(values)
        }
    }

    private func applyInternalValueChange(_ newValue: Model) {
        isApplyingInternalChange = true
        values = newValue
        isApplyingInternalChange = false
    }
}
