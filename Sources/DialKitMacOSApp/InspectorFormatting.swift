import Foundation
import DialkitmacOSProtocol

func formatted(_ value: Double, step: Double, unit: String?) -> String {
    DialNumber.format(value, step: step) + (unit ?? "")
}

/// Return a validated value or the current value so invalid drafts visibly revert
/// on both Return and focus loss.
enum InspectorDraft {
    static func color(_ draft: String, fallback: String) -> String {
        var normalized = draft.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        if !normalized.hasPrefix("#") { normalized = "#" + normalized }
        let pattern = "^#([0-9A-F]{3}|[0-9A-F]{6}|[0-9A-F]{8})$"
        return normalized.range(of: pattern, options: .regularExpression) != nil
            ? normalized : fallback.uppercased()
    }

    static func bezier(_ draft: String, fallback: DialKitBezierValue) -> DialKitBezierValue {
        let parts = draft.split(separator: ",", omittingEmptySubsequences: false)
        guard parts.count == 4 else { return fallback }
        let values = parts.compactMap { DialNumber.parse(String($0)) }
        guard values.count == 4, (0...1).contains(values[0]), (0...1).contains(values[2]) else {
            return fallback
        }
        return DialKitBezierValue(x1: values[0], y1: values[1], x2: values[2], y2: values[3])
    }
}

func copyInstructionText(for panel: DialKitPanelSnapshot) -> String {
    let values = copyLines(for: panel.controls, indent: "")
    guard !values.isEmpty else {
        return panel.name
    }

    return ([panel.name] + values).joined(separator: "\n")
}

func copyLines(for controls: [DialKitControlSnapshot], indent: String) -> [String] {
    controls.flatMap { control -> [String] in
        switch control.kind {
        case let .group(_, children):
            return ["\(indent)\(control.label):"] + copyLines(for: children, indent: "\(indent)  ")
        case let .slider(value, _, _, step, unit):
            return ["\(indent)\(control.label): \(formatted(value, step: step, unit: unit))"]
        case let .toggle(value):
            return ["\(indent)\(control.label): \(value ? "On" : "Off")"]
        case let .text(value, _), let .color(value), let .select(value, _):
            return ["\(indent)\(control.label): \(value)"]
        case let .spring(value):
            return ["\(indent)\(control.label): \(copyDescription(for: value))"]
        case let .transition(value):
            return ["\(indent)\(control.label): \(copyDescription(for: value))"]
        case .action:
            return []
        }
    }
}

func copyDescription(for spring: DialKitSpringValue) -> String {
    switch spring {
    case let .time(duration, bounce):
        return "time(duration: \(formatted(duration, step: 0.01, unit: "s")), bounce: \(formatted(bounce, step: 0.01, unit: nil)))"
    case let .physics(stiffness, damping, mass):
        return "physics(stiffness: \(formatted(stiffness, step: 1, unit: nil)), damping: \(formatted(damping, step: 1, unit: nil)), mass: \(formatted(mass, step: 0.1, unit: nil)))"
    }
}

func copyDescription(for transition: DialKitTransitionValue) -> String {
    switch transition {
    case let .easing(duration, bezier):
        let points = [bezier.x1, bezier.y1, bezier.x2, bezier.y2]
            .map { formatted($0, step: 0.01, unit: nil) }
            .joined(separator: ", ")
        return "easing(duration: \(formatted(duration, step: 0.01, unit: "s")), bezier: \(points))"
    case let .spring(spring):
        return "spring(\(copyDescription(for: spring)))"
    }
}
