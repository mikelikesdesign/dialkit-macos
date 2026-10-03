import Foundation

package extension DialKitSpringValue {
    var isValid: Bool {
        switch self {
        case let .time(duration, bounce):
            return duration.isFinite && duration > 0 && bounce.isFinite && (0...1).contains(bounce)
        case let .physics(stiffness, damping, mass):
            return stiffness.isFinite && stiffness > 0 && damping.isFinite && damping >= 0 && mass.isFinite && mass > 0
        }
    }
}

package extension DialKitBezierValue {
    var isValid: Bool {
        x1.isFinite && y1.isFinite && x2.isFinite && y2.isFinite && (0...1).contains(x1) && (0...1).contains(x2)
    }
}

package extension DialKitTransitionValue {
    var isValid: Bool {
        switch self {
        case let .spring(spring): return spring.isValid
        case let .easing(duration, bezier): return duration.isFinite && duration >= 0 && bezier.isValid
        }
    }
}

package extension DialKitControlKind {
    var isValid: Bool {
        switch self {
        case let .slider(value, lower, upper, step, _):
            return value.isFinite && lower.isFinite && upper.isFinite && lower <= upper && step.isFinite && step >= 0
        case let .spring(value): return value.isValid
        case let .transition(value): return value.isValid
        case let .group(_, controls): return controls.allSatisfy { $0.kind.isValid }
        default: return true
        }
    }
}

package extension DialKitSessionSnapshot {
    func removingInvalidControls() -> (snapshot: DialKitSessionSnapshot, paths: [String]) {
        var paths: [String] = []
        func clean(_ controls: [DialKitControlSnapshot], panelName: String) -> [DialKitControlSnapshot] {
            controls.compactMap { control in
                var control = control
                if case let .group(collapsed, children) = control.kind {
                    control.kind = .group(collapsed: collapsed, controls: clean(children, panelName: panelName))
                    return control
                }
                guard control.kind.isValid else {
                    paths.append("\(panelName).\(control.path)")
                    return nil
                }
                return control
            }
        }
        var snapshot = self
        snapshot.panels = panels.map { panel in
            var panel = panel
            panel.controls = clean(panel.controls, panelName: panel.name)
            return panel
        }
        return (snapshot, paths)
    }
}
