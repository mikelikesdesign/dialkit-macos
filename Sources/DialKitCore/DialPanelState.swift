import Combine
import Foundation

public final class DialPanelState<Model: Codable & Equatable>: ObservableObject, Identifiable {
    public let id: UUID

    @Published public var name: String
    @DialPanelValues public var values: Model
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
        self._values = DialPanelValues(wrappedValue: normalizedInitial)
        self.baseValues = dialCopyModel(normalizedInitial)
        self.presets = []
        self.activePresetID = nil
        self.onAction = onAction
        self.panelBox = AnyDialPanelBox(id: id)
        self._values.bind(to: self)
        self.panelBox.bind(to: self)
        DialStore.shared.register(panelBox)
    }

    deinit {
        _values.cancelBindings()
        DialStore.shared.unregister(panelBox)
    }

    /// Make this instance the edit target for its ID when its view appears.
    /// Use a stable ID for a logical panel that Xcode may recreate while
    /// retaining older view instances. Call on the UI thread.
    public func activate() {
        DialStore.shared.register(panelBox)
    }

    /// Remove this instance when its view disappears. A newer instance with
    /// the same ID remains registered. Call on the UI thread.
    public func deactivate() {
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

    fileprivate func normalizedValues(_ newValue: Model) -> Model {
        var normalized = dialCopyModel(newValue)
        for control in controls {
            control.node.normalizeMotion(current: &normalized, fallback: values)
        }
        return normalized
    }

    fileprivate func valuesDidChange() {
        guard !isApplyingInternalChange else { return }
        synchronizeValues()
    }

    private func applyInternalValueChange(_ newValue: Model) {
        isApplyingInternalChange = true
        values = newValue
        isApplyingInternalChange = false
    }
}

/// Publishes validated panel values and supports lifetime-managed Combine
/// assignment through `publisher.assign(to: &panel.$values)`.
@propertyWrapper
public struct DialPanelValues<Model: Codable & Equatable> {
    fileprivate final class Storage {
        @Published var value: Model
        weak var state: DialPanelState<Model>?
        var bindings: Set<AnyCancellable> = []

        init(_ value: Model) { self.value = value }
    }

    private let storage: Storage

    public init(wrappedValue: Model) {
        self.storage = Storage(wrappedValue)
    }

    @available(*, unavailable, message: "DialPanelValues is managed by DialPanelState.")
    public var wrappedValue: Model {
        get { fatalError() }
        set { fatalError() }
    }

    /// The writable projection lets Combine assignment retain a subscription
    /// in this panel. Assignments use the validated values setter, never the
    /// underlying Published storage directly.
    public var projectedValue: Publisher {
        get { Publisher(storage: storage) }
        nonmutating set {
            // assign(to:) installs its subscription in the existing storage.
            // Swift's inout writeback must not replace this panel's identity.
        }
    }

    fileprivate func bind(to state: DialPanelState<Model>) { storage.state = state }
    fileprivate func cancelBindings() { storage.bindings.removeAll() }

    public struct Publisher: Combine.Publisher {
        public typealias Output = Model
        public typealias Failure = Never
        fileprivate let storage: Storage

        public func receive<S: Subscriber>(subscriber: S) where S.Input == Model, S.Failure == Never {
            storage.$value.receive(subscriber: subscriber)
        }

        fileprivate func assign<P: Combine.Publisher>(from publisher: P) where P.Output == Model, P.Failure == Never {
            publisher.sink { [weak storage] value in
                storage?.state?.values = value
            }.store(in: &storage.bindings)
        }
    }

    public static subscript(
        _enclosingInstance state: DialPanelState<Model>,
        wrapped wrappedKeyPath: ReferenceWritableKeyPath<DialPanelState<Model>, Model>,
        storage storageKeyPath: ReferenceWritableKeyPath<DialPanelState<Model>, Self>
    ) -> Model {
        get { state[keyPath: storageKeyPath].storage.value }
        set {
            let normalized = state.normalizedValues(newValue)
            state.objectWillChange.send()
            state[keyPath: storageKeyPath].storage.value = normalized
            state.valuesDidChange()
        }
    }
}

public extension Combine.Publisher where Failure == Never, Output: Codable & Equatable {
    /// Assigns each value through panel validation and cancels automatically
    /// when the panel is released, matching Combine's Published assignment use.
    func assign(to published: inout DialPanelValues<Output>.Publisher) {
        published.assign(from: self)
    }
}
