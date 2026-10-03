import Foundation
import DialkitmacOSProtocol

package struct DialResolvedControl: Identifiable {
    package let path: String
    package let label: String
    package let kind: DialResolvedControlKind

    package init(path: String, label: String, kind: DialResolvedControlKind) {
        self.path = path
        self.label = label
        self.kind = kind
    }

    package var id: String {
        switch kind {
        case let .group(group):
            return "\(path)|group|\(group.collapsed)"
        default:
            return path
        }
    }
}

package indirect enum DialResolvedControlKind {
    case slider(DialResolvedSlider)
    case toggle(DialResolvedToggle)
    case text(DialResolvedText)
    case color(DialResolvedColor)
    case select(DialResolvedSelect)
    case spring(DialResolvedSpring)
    case transition(DialResolvedTransition)
    case group(DialResolvedGroup)
    case action(DialResolvedAction)
}

package struct DialResolvedSlider {
    package let range: ClosedRange<Double>
    package let step: Double
    package let unit: String?
    package let numericType: DialKitSliderValueType
    package let get: () -> Double
    package let set: (Double) -> Void

    package init(range: ClosedRange<Double>, step: Double, unit: String?, numericType: DialKitSliderValueType = .double, get: @escaping () -> Double, set: @escaping (Double) -> Void) {
        self.range = range
        self.step = step
        self.unit = unit
        self.numericType = numericType
        self.get = get
        self.set = set
    }
}

package struct DialResolvedToggle {
    package let get: () -> Bool
    package let set: (Bool) -> Void

    package init(get: @escaping () -> Bool, set: @escaping (Bool) -> Void) {
        self.get = get
        self.set = set
    }
}

package struct DialResolvedText {
    package let placeholder: String?
    package let get: () -> String
    package let set: (String) -> Void

    package init(placeholder: String?, get: @escaping () -> String, set: @escaping (String) -> Void) {
        self.placeholder = placeholder
        self.get = get
        self.set = set
    }
}

package struct DialResolvedColor {
    package let get: () -> String
    package let set: (String) -> Void

    package init(get: @escaping () -> String, set: @escaping (String) -> Void) {
        self.get = get
        self.set = set
    }
}

package struct DialResolvedSelect {
    package let options: [DialOption]
    package let get: () -> String
    package let set: (String) -> Void

    package init(options: [DialOption], get: @escaping () -> String, set: @escaping (String) -> Void) {
        self.options = options
        self.get = get
        self.set = set
    }
}

package struct DialResolvedSpring {
    package let get: () -> DialSpring
    package let set: (DialSpring) -> Void

    package init(get: @escaping () -> DialSpring, set: @escaping (DialSpring) -> Void) {
        self.get = get
        self.set = set
    }
}

package struct DialResolvedTransition {
    package let get: () -> DialTransition
    package let set: (DialTransition) -> Void

    package init(get: @escaping () -> DialTransition, set: @escaping (DialTransition) -> Void) {
        self.get = get
        self.set = set
    }
}

package struct DialResolvedGroup {
    package let collapsed: Bool
    package let children: [DialResolvedControl]

    package init(collapsed: Bool, children: [DialResolvedControl]) {
        self.collapsed = collapsed
        self.children = children
    }
}

package struct DialResolvedAction {
    package let trigger: () -> Void

    package init(trigger: @escaping () -> Void) {
        self.trigger = trigger
    }
}

package indirect enum DialControlNode<Model> {
    case slider(
        path: String,
        label: String,
        range: ClosedRange<Double>,
        step: Double,
        unit: String?,
        numericType: DialKitSliderValueType,
        getter: (Model) -> Double,
        setter: (inout Model, Double) -> Void
    )
    case toggle(
        path: String,
        label: String,
        getter: (Model) -> Bool,
        setter: (inout Model, Bool) -> Void
    )
    case text(
        path: String,
        label: String,
        placeholder: String?,
        getter: (Model) -> String,
        setter: (inout Model, String) -> Void
    )
    case color(
        path: String,
        label: String,
        getter: (Model) -> String,
        setter: (inout Model, String) -> Void
    )
    case select(
        path: String,
        label: String,
        options: [DialOption],
        getter: (Model) -> String,
        setter: (inout Model, String) -> Void
    )
    case spring(
        path: String,
        label: String,
        getter: (Model) -> DialSpring,
        setter: (inout Model, DialSpring) -> Void
    )
    case transition(
        path: String,
        label: String,
        getter: (Model) -> DialTransition,
        setter: (inout Model, DialTransition) -> Void
    )
    case group(
        path: String,
        label: String,
        collapsed: Bool,
        children: [DialControlNode<Model>]
    )
    case action(
        path: String,
        label: String
    )
}

public struct DialControl<Model> {
    package let node: DialControlNode<Model>

    fileprivate init(node: DialControlNode<Model>) {
        self.node = node
    }

    public static func slider<Value: DialNumericValue>(
        _ path: String,
        keyPath: WritableKeyPath<Model, Value>,
        label: String? = nil,
        range: ClosedRange<Value>,
        step: Value? = nil,
        unit: String? = nil
    ) -> DialControl<Model> {
        // Preserve Float's intended decimal precision when describing a stepped
        // control. Promoting its binary representation to Double adds digits
        // that were never present in the model's value or step.
        func decimalValue(_ value: Value) -> Double {
            if let float = value as? Float, let decimal = Double(String(float)) { return decimal }
            return value.dialDoubleValue
        }
        let doubleRange = decimalValue(range.lowerBound)...decimalValue(range.upperBound)
        var doubleStep = step.map(decimalValue) ?? dialInferredStep(for: doubleRange)
        if Value.self == Int.self {
            // Integer models cannot acknowledge fractional slider values.
            doubleStep = max(1, doubleStep)
        }
        return DialControl<Model>(
            node: .slider(
                path: path,
                label: label ?? dialFormattedLabel(path),
                range: doubleRange,
                step: doubleStep,
                unit: unit,
                numericType: Value.self == Float.self ? .float : .double,
                getter: { model in
                    doubleStep > 0 ? decimalValue(model[keyPath: keyPath]) : model[keyPath: keyPath].dialDoubleValue
                },
                setter: { model, newValue in
                    let currentValue = model[keyPath: keyPath]
                    // Preserve an in-range integer that already has this wire
                    // value; adjacent large integers can share one Double.
                    if range.contains(currentValue), currentValue.dialDoubleValue == newValue { return }
                    let converted = Value(dialDoubleValue: newValue)
                    // Large Int bounds can map to the same Double. Enforce the
                    // original typed bounds after conversion as well.
                    model[keyPath: keyPath] = min(max(converted, range.lowerBound), range.upperBound)
                }
            )
        )
    }

    public static func toggle(
        _ path: String,
        keyPath: WritableKeyPath<Model, Bool>,
        label: String? = nil
    ) -> DialControl<Model> {
        DialControl<Model>(
            node: .toggle(
                path: path,
                label: label ?? dialFormattedLabel(path),
                getter: { $0[keyPath: keyPath] },
                setter: { model, newValue in model[keyPath: keyPath] = newValue }
            )
        )
    }

    public static func text(
        _ path: String,
        keyPath: WritableKeyPath<Model, String>,
        label: String? = nil,
        placeholder: String? = nil
    ) -> DialControl<Model> {
        DialControl<Model>(
            node: .text(
                path: path,
                label: label ?? dialFormattedLabel(path),
                placeholder: placeholder,
                getter: { $0[keyPath: keyPath] },
                setter: { model, newValue in model[keyPath: keyPath] = newValue }
            )
        )
    }

    public static func color(
        _ path: String,
        keyPath: WritableKeyPath<Model, String>,
        label: String? = nil
    ) -> DialControl<Model> {
        DialControl<Model>(
            node: .color(
                path: path,
                label: label ?? dialFormattedLabel(path),
                getter: { $0[keyPath: keyPath] },
                setter: { model, newValue in model[keyPath: keyPath] = newValue }
            )
        )
    }

    public static func select(
        _ path: String,
        keyPath: WritableKeyPath<Model, String>,
        label: String? = nil,
        options: [DialOption]
    ) -> DialControl<Model> {
        DialControl<Model>(
            node: .select(
                path: path,
                label: label ?? dialFormattedLabel(path),
                options: options,
                getter: { $0[keyPath: keyPath] },
                setter: { model, newValue in model[keyPath: keyPath] = newValue }
            )
        )
    }

    public static func select(
        _ path: String,
        keyPath: WritableKeyPath<Model, String>,
        label: String? = nil,
        options: [String]
    ) -> DialControl<Model> {
        select(path, keyPath: keyPath, label: label, options: options.map { DialOption($0) })
    }

    public static func spring(
        _ path: String,
        keyPath: WritableKeyPath<Model, DialSpring>,
        label: String? = nil
    ) -> DialControl<Model> {
        DialControl<Model>(
            node: .spring(
                path: path,
                label: label ?? dialFormattedLabel(path),
                getter: { $0[keyPath: keyPath] },
                setter: { model, newValue in model[keyPath: keyPath] = newValue }
            )
        )
    }

    public static func transition(
        _ path: String,
        keyPath: WritableKeyPath<Model, DialTransition>,
        label: String? = nil
    ) -> DialControl<Model> {
        DialControl<Model>(
            node: .transition(
                path: path,
                label: label ?? dialFormattedLabel(path),
                getter: { $0[keyPath: keyPath] },
                setter: { model, newValue in model[keyPath: keyPath] = newValue }
            )
        )
    }

    public static func group(
        _ path: String,
        label: String? = nil,
        collapsed: Bool = false,
        children: [DialControl<Model>]
    ) -> DialControl<Model> {
        DialControl<Model>(
            node: .group(
                path: path,
                label: label ?? dialFormattedLabel(path),
                collapsed: collapsed,
                children: children.map(\.node)
            )
        )
    }

    public static func action(
        _ path: String,
        label: String? = nil
    ) -> DialControl<Model> {
        DialControl<Model>(
            node: .action(
                path: path,
                label: label ?? dialFormattedLabel(path)
            )
        )
    }
}

package extension DialControlNode where Model: Codable & Equatable {
    func normalize(current: inout Model, fallback: Model) {
        switch self {
        case let .slider(_, _, range, step, _, _, getter, setter):
            let currentValue = getter(current)
            setter(&current, dialRound(currentValue, step: step, within: range))
        case .toggle:
            break
        case .text:
            break
        case let .color(_, _, getter, setter):
            let currentValue = getter(current)
            guard !currentValue.isEmpty, dialIsValidHexColor(currentValue) else {
                setter(&current, getter(fallback))
                return
            }
        case let .select(_, _, options, getter, setter):
            let currentValue = getter(current)
            let valid = Set(options.map(\.value))
            guard valid.contains(currentValue) else {
                let fallbackValue = getter(fallback)
                if valid.contains(fallbackValue) {
                    setter(&current, fallbackValue)
                } else if let first = options.first {
                    setter(&current, first.value)
                }
                return
            }
        case .spring, .transition:
            normalizeMotion(current: &current, fallback: fallback)
        case let .group(_, _, _, children):
            for child in children {
                child.normalize(current: &current, fallback: fallback)
            }
        case .action:
            break
        }
    }

    /// Keep local rendering, presets, and remote snapshots on the same valid
    /// motion value. A malformed initial value falls back to the public default.
    func normalizeMotion(current: inout Model, fallback: Model) {
        switch self {
        case let .spring(_, _, getter, setter):
            guard !DialKitSpringValue(getter(current)).isValid else { return }
            let previous = getter(fallback)
            setter(&current, DialKitSpringValue(previous).isValid ? previous : .default)
        case let .transition(_, _, getter, setter):
            guard !DialKitTransitionValue(getter(current)).isValid else { return }
            let previous = getter(fallback)
            setter(&current, DialKitTransitionValue(previous).isValid ? previous : .default)
        case let .group(_, _, _, children):
            for child in children { child.normalizeMotion(current: &current, fallback: fallback) }
        default: break
        }
    }

    func resolve(state: DialPanelState<Model>, prefix: String = "") -> [DialResolvedControl] {
        switch self {
        case let .slider(path, label, range, step, unit, numericType, getter, setter):
            let resolvedPath = dialResolvedPath(prefix: prefix, path: path)
            return [
                DialResolvedControl(
                    path: resolvedPath,
                    label: label,
                    kind: .slider(
                        DialResolvedSlider(
                            range: range,
                            step: step,
                            unit: unit,
                            numericType: numericType,
                            get: { getter(state.values) },
                            set: { newValue in
                                var updated = dialCopyModel(state.values)
                                setter(&updated, dialRound(newValue, step: step, within: range))
                                state.values = updated
                            }
                        )
                    )
                )
            ]
        case let .toggle(path, label, getter, setter):
            let resolvedPath = dialResolvedPath(prefix: prefix, path: path)
            return [
                DialResolvedControl(
                    path: resolvedPath,
                    label: label,
                    kind: .toggle(
                        DialResolvedToggle(
                            get: { getter(state.values) },
                            set: { newValue in
                                var updated = dialCopyModel(state.values)
                                setter(&updated, newValue)
                                state.values = updated
                            }
                        )
                    )
                )
            ]
        case let .text(path, label, placeholder, getter, setter):
            let resolvedPath = dialResolvedPath(prefix: prefix, path: path)
            return [
                DialResolvedControl(
                    path: resolvedPath,
                    label: label,
                    kind: .text(
                        DialResolvedText(
                            placeholder: placeholder,
                            get: { getter(state.values) },
                            set: { newValue in
                                var updated = dialCopyModel(state.values)
                                setter(&updated, newValue)
                                state.values = updated
                            }
                        )
                    )
                )
            ]
        case let .color(path, label, getter, setter):
            let resolvedPath = dialResolvedPath(prefix: prefix, path: path)
            return [
                DialResolvedControl(
                    path: resolvedPath,
                    label: label,
                    kind: .color(
                        DialResolvedColor(
                            get: { getter(state.values) },
                            set: { newValue in
                                var updated = dialCopyModel(state.values)
                                setter(&updated, newValue)
                                state.values = updated
                            }
                        )
                    )
                )
            ]
        case let .select(path, label, options, getter, setter):
            let resolvedPath = dialResolvedPath(prefix: prefix, path: path)
            return [
                DialResolvedControl(
                    path: resolvedPath,
                    label: label,
                    kind: .select(
                        DialResolvedSelect(
                            options: options,
                            get: { getter(state.values) },
                            set: { newValue in
                                var updated = dialCopyModel(state.values)
                                setter(&updated, newValue)
                                state.values = updated
                            }
                        )
                    )
                )
            ]
        case let .spring(path, label, getter, setter):
            let resolvedPath = dialResolvedPath(prefix: prefix, path: path)
            return [
                DialResolvedControl(
                    path: resolvedPath,
                    label: label,
                    kind: .spring(
                        DialResolvedSpring(
                            get: { getter(state.values) },
                            set: { newValue in
                                var updated = dialCopyModel(state.values)
                                setter(&updated, newValue)
                                state.values = updated
                            }
                        )
                    )
                )
            ]
        case let .transition(path, label, getter, setter):
            let resolvedPath = dialResolvedPath(prefix: prefix, path: path)
            return [
                DialResolvedControl(
                    path: resolvedPath,
                    label: label,
                    kind: .transition(
                        DialResolvedTransition(
                            get: { getter(state.values) },
                            set: { newValue in
                                var updated = dialCopyModel(state.values)
                                setter(&updated, newValue)
                                state.values = updated
                            }
                        )
                    )
                )
            ]
        case let .group(path, label, collapsed, children):
            let resolvedPath = dialResolvedPath(prefix: prefix, path: path)
            return [
                DialResolvedControl(
                    path: resolvedPath,
                    label: label,
                    kind: .group(
                        DialResolvedGroup(
                            collapsed: collapsed,
                            children: children.flatMap { $0.resolve(state: state, prefix: resolvedPath) }
                        )
                    )
                )
            ]
        case let .action(path, label):
            let resolvedPath = dialResolvedPath(prefix: prefix, path: path)
            return [
                DialResolvedControl(
                    path: resolvedPath,
                    label: label,
                    kind: .action(
                        DialResolvedAction(
                            trigger: {
                                state.triggerAction(path: resolvedPath)
                            }
                        )
                    )
                )
            ]
        }
    }
}
