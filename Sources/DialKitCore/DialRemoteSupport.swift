import Foundation
import DialkitmacOSProtocol

package extension AnyDialPanelBox {
    var remoteSnapshot: DialKitPanelSnapshot {
        DialKitPanelSnapshot(
            id: id,
            name: name,
            controls: controls.map(DialKitControlSnapshot.init(resolved:)),
            presets: presets.map { DialKitPresetSnapshot(id: $0.id, name: $0.name) },
            activePresetID: activePresetID,
            nextPresetName: nextPresetName
        )
    }

    func setRemoteControlValue(path: String, value: DialKitControlValue) -> Bool {
        applyRemoteControlValue(in: controls, path: path, value: value)
    }

    func triggerRemoteAction(path: String) -> Bool {
        performRemoteAction(in: controls, path: path)
    }

    func setRemoteMotionComponent(path: String, component: DialKitMotionComponent) -> Bool {
        applyMotionComponent(in: controls, path: path, component: component)
    }
}

private extension DialKitControlSnapshot {
    init(resolved control: DialResolvedControl) {
        let numericType: DialKitSliderValueType?
        if case let .slider(slider) = control.kind { numericType = slider.numericType }
        else { numericType = nil }
        self.init(
            path: control.path,
            label: control.label,
            kind: DialKitControlKind(resolved: control.kind),
            numericType: numericType
        )
    }
}

private extension DialKitControlKind {
    init(resolved kind: DialResolvedControlKind) {
        switch kind {
        case let .slider(slider):
            self = .slider(
                value: slider.get(),
                lowerBound: slider.range.lowerBound,
                upperBound: slider.range.upperBound,
                step: slider.step,
                unit: slider.unit
            )
        case let .toggle(toggle):
            self = .toggle(value: toggle.get())
        case let .text(text):
            self = .text(value: text.get(), placeholder: text.placeholder)
        case let .color(color):
            self = .color(value: color.get())
        case let .select(select):
            self = .select(
                value: select.get(),
                options: select.options.map { DialKitOptionSnapshot(value: $0.value, label: $0.label) }
            )
        case let .spring(spring):
            self = .spring(value: DialKitSpringValue(spring.get()))
        case let .transition(transition):
            self = .transition(value: DialKitTransitionValue(transition.get()))
        case let .group(group):
            self = .group(
                collapsed: group.collapsed,
                controls: group.children.map(DialKitControlSnapshot.init(resolved:))
            )
        case .action:
            self = .action
        }
    }
}

extension DialKitSpringValue {
    init(_ spring: DialSpring) {
        switch spring {
        case let .time(duration, bounce):
            self = .time(duration: duration, bounce: bounce)
        case let .physics(stiffness, damping, mass):
            self = .physics(stiffness: stiffness, damping: damping, mass: mass)
        }
    }
}

private extension DialSpring {
    init(_ value: DialKitSpringValue) {
        switch value {
        case let .time(duration, bounce):
            self = .time(duration: duration, bounce: bounce)
        case let .physics(stiffness, damping, mass):
            self = .physics(stiffness: stiffness, damping: damping, mass: mass)
        }
    }
}

private extension DialKitBezierValue {
    init(_ bezier: DialBezier) {
        self.init(x1: bezier.x1, y1: bezier.y1, x2: bezier.x2, y2: bezier.y2)
    }
}

private extension DialBezier {
    init(_ value: DialKitBezierValue) {
        self.init(x1: value.x1, y1: value.y1, x2: value.x2, y2: value.y2)
    }
}

extension DialKitTransitionValue {
    init(_ transition: DialTransition) {
        switch transition {
        case let .easing(duration, bezier):
            self = .easing(duration: duration, bezier: DialKitBezierValue(bezier))
        case let .spring(spring):
            self = .spring(DialKitSpringValue(spring))
        }
    }
}

private extension DialTransition {
    init(_ value: DialKitTransitionValue) {
        switch value {
        case let .easing(duration, bezier):
            self = .easing(duration: duration, bezier: DialBezier(bezier))
        case let .spring(spring):
            self = .spring(DialSpring(spring))
        }
    }
}

private func applyRemoteControlValue(
    in controls: [DialResolvedControl],
    path: String,
    value: DialKitControlValue
) -> Bool {
    for control in controls {
        if control.path == path {
            return setRemoteControlValue(control: control, value: value)
        }

        if case let .group(group) = control.kind,
           applyRemoteControlValue(in: group.children, path: path, value: value) {
            return true
        }
    }

    return false
}

private func setRemoteControlValue(control: DialResolvedControl, value: DialKitControlValue) -> Bool {
    switch (control.kind, value) {
    case let (.slider(slider), .number(number)):
        slider.set(number)
        return true
    case let (.toggle(toggle), .bool(bool)):
        toggle.set(bool)
        return true
    case let (.text(text), .string(string)):
        text.set(string)
        return true
    case let (.color(color), .string(string)):
        guard dialIsValidHexColor(string) else {
            return false
        }

        color.set(string)
        return true
    case let (.select(select), .string(string)):
        guard select.options.contains(where: { $0.value == string }) else {
            return false
        }

        select.set(string)
        return true
    case let (.spring(spring), .spring(value)):
        guard value.isValid else { return false }
        spring.set(DialSpring(value))
        return true
    case let (.transition(transition), .transition(value)):
        guard value.isValid else { return false }
        transition.set(DialTransition(value))
        return true
    default:
        return false
    }
}

private func applyMotionComponent(in controls: [DialResolvedControl], path: String, component: DialKitMotionComponent) -> Bool {
    for control in controls {
        if control.path == path {
            switch control.kind {
            case let .spring(spring):
                guard let next = component.applying(to: DialKitSpringValue(spring.get())) else { return false }
                spring.set(DialSpring(next))
                return true
            case let .transition(transition):
                guard let next = component.applying(to: DialKitTransitionValue(transition.get())) else { return false }
                transition.set(DialTransition(next))
                return true
            default: return false
            }
        }
        if case let .group(group) = control.kind,
           applyMotionComponent(in: group.children, path: path, component: component) {
            return true
        }
    }
    return false
}

private func performRemoteAction(in controls: [DialResolvedControl], path: String) -> Bool {
    for control in controls {
        if control.path == path,
           case let .action(action) = control.kind {
            action.trigger()
            return true
        }

        if case let .group(group) = control.kind,
           performRemoteAction(in: group.children, path: path) {
            return true
        }
    }

    return false
}
