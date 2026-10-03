import CoreGraphics
import Foundation
import DialkitmacOSProtocol

public protocol DialNumericValue: Comparable {
    var dialDoubleValue: Double { get }
    init(dialDoubleValue: Double)
}

extension Double: DialNumericValue {
    public var dialDoubleValue: Double { self }

    public init(dialDoubleValue: Double) {
        self = dialDoubleValue
    }
}

extension Float: DialNumericValue {
    public var dialDoubleValue: Double { Double(self) }

    public init(dialDoubleValue: Double) {
        self = Float(dialDoubleValue)
    }
}

extension CGFloat: DialNumericValue {
    public var dialDoubleValue: Double { Double(self) }

    public init(dialDoubleValue: Double) {
        self = CGFloat(dialDoubleValue)
    }
}

extension Int: DialNumericValue {
    public var dialDoubleValue: Double { Double(self) }

    public init(dialDoubleValue: Double) {
        // Double(Int.max) rounds up beyond Int's representable range.
        // Saturate before converting so endpoint edits cannot trap.
        let rounded = dialDoubleValue.rounded()
        if rounded.isNaN {
            self = 0
        } else if rounded >= Double(Int.max) {
            self = Int.max
        } else if rounded <= Double(Int.min) {
            self = Int.min
        } else {
            self = Int(rounded)
        }
    }
}

public struct DialOption: Hashable, Codable, Identifiable {
    public let value: String
    public let label: String

    public var id: String { value }

    public init(_ value: String, label: String? = nil) {
        self.value = value
        self.label = label ?? dialFormattedLabel(value)
    }

    public init(value: String, label: String) {
        self.value = value
        self.label = label
    }
}

public struct DialBezier: Hashable, Codable {
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

    public static let standard = DialBezier(x1: 0.25, y1: 0.1, x2: 0.25, y2: 1)
}

public struct ResolvedSpringPhysics: Equatable {
    public let stiffness: Double
    public let damping: Double
    public let mass: Double

    public init(stiffness: Double, damping: Double, mass: Double) {
        self.stiffness = stiffness
        self.damping = damping
        self.mass = mass
    }
}

package enum DialSpringEditorMode: String, CaseIterable {
    case simple
    case advanced
}

public enum DialSpring: Equatable, Codable {
    case time(duration: Double, bounce: Double)
    case physics(stiffness: Double, damping: Double, mass: Double)

    public static let `default` = DialSpring.time(duration: 0.35, bounce: 0.24)

    package var editorMode: DialSpringEditorMode {
        switch self {
        case .time:
            return .simple
        case .physics:
            return .advanced
        }
    }

    public var resolvedPhysics: ResolvedSpringPhysics {
        let value: DialKitSpringValue
        switch self {
        case let .time(duration, bounce):
            value = .time(duration: duration, bounce: bounce)
        case let .physics(stiffness, damping, mass):
            value = .physics(stiffness: stiffness, damping: damping, mass: mass)
        }
        let physics = value.resolvedPhysics
        return ResolvedSpringPhysics(stiffness: physics.stiffness, damping: physics.damping, mass: physics.mass)
    }

    package var durationHint: Double {
        switch self {
        case let .time(duration, _):
            return duration
        case .physics:
            return 0.3
        }
    }

    public func updatingTime(duration: Double? = nil, bounce: Double? = nil) -> DialSpring {
        switch self {
        case let .time(currentDuration, currentBounce):
            return .time(duration: duration ?? currentDuration, bounce: bounce ?? currentBounce)
        case .physics:
            return .time(duration: duration ?? 0.3, bounce: bounce ?? 0.2)
        }
    }

    public func updatingPhysics(stiffness: Double? = nil, damping: Double? = nil, mass: Double? = nil) -> DialSpring {
        switch self {
        case .time:
            return .physics(stiffness: stiffness ?? 200, damping: damping ?? 25, mass: mass ?? 1)
        case let .physics(currentStiffness, currentDamping, currentMass):
            return .physics(
                stiffness: stiffness ?? currentStiffness,
                damping: damping ?? currentDamping,
                mass: mass ?? currentMass
            )
        }
    }
}

public enum DialTransitionMode: String, CaseIterable, Codable {
    case easing
    case simple
    case advanced
}

public enum DialTransition: Equatable, Codable {
    case easing(duration: Double, bezier: DialBezier)
    case spring(DialSpring)

    public static let `default` = DialTransition.spring(.default)

    public var mode: DialTransitionMode {
        switch self {
        case .easing:
            return .easing
        case let .spring(spring):
            return spring.editorMode == .simple ? .simple : .advanced
        }
    }

    public func switching(to mode: DialTransitionMode) -> DialTransition {
        switch mode {
        case .easing:
            switch self {
            case let .easing(duration, bezier):
                return .easing(duration: duration, bezier: bezier)
            case let .spring(spring):
                return .easing(duration: spring.durationHint, bezier: .standard)
            }
        case .simple:
            switch self {
            case let .easing(duration, _):
                return .spring(.time(duration: DialMotionDefaults.springDuration(from: duration), bounce: 0.2))
            case let .spring(spring):
                switch spring {
                case let .time(duration, bounce):
                    return .spring(.time(duration: duration, bounce: bounce))
                case .physics:
                    return .spring(.time(duration: spring.durationHint, bounce: 0.2))
                }
            }
        case .advanced:
            switch self {
            case .easing:
                return .spring(.physics(stiffness: 200, damping: 25, mass: 1))
            case let .spring(spring):
                switch spring {
                case let .physics(stiffness, damping, mass):
                    return .spring(.physics(stiffness: stiffness, damping: damping, mass: mass))
                case .time:
                    return .spring(.physics(stiffness: 200, damping: 25, mass: 1))
                }
            }
        }
    }
}

public struct DialPreset<Model: Codable & Equatable>: Identifiable, Equatable, Codable {
    public let id: UUID
    public var name: String
    public var values: Model

    public init(id: UUID = UUID(), name: String, values: Model) {
        self.id = id
        self.name = name
        self.values = values
    }
}

package struct DialPresetSummary: Identifiable, Equatable {
    package let id: UUID
    package let name: String

    package init(id: UUID, name: String) {
        self.id = id
        self.name = name
    }
}

package func dialFormattedLabel(_ path: String) -> String {
    let token = path.split(separator: ".").last.map(String.init) ?? path
    return token
        .replacingOccurrences(of: "([A-Z])", with: " $1", options: .regularExpression)
        .replacingOccurrences(of: "[_-]+", with: " ", options: .regularExpression)
        .trimmingCharacters(in: .whitespacesAndNewlines)
        .capitalized
}

package func dialResolvedPath(prefix: String, path: String) -> String {
    guard !prefix.isEmpty else { return path }
    if path.contains(".") {
        return path
    }
    return "\(prefix).\(path)"
}

package func dialIsValidHexColor(_ value: String) -> Bool {
    let pattern = "^#([0-9A-Fa-f]{3}|[0-9A-Fa-f]{6}|[0-9A-Fa-f]{8})$"
    return value.range(of: pattern, options: .regularExpression) != nil
}

package func dialStepPrecision(_ step: Double) -> Int {
    DialNumber.precision(step)
}

package func dialRound(_ value: Double, step: Double, within range: ClosedRange<Double>) -> Double {
    DialNumber.round(value, step: step, within: range)
}

package func dialFormattedNumber(_ value: Double, step: Double) -> String {
    DialNumber.format(value, step: step)
}

package func dialInferredStep(for range: ClosedRange<Double>) -> Double {
    let width = range.upperBound - range.lowerBound
    if width <= 1 {
        return 0.01
    }
    if width <= 10 {
        return 0.1
    }
    if width <= 100 {
        return 1
    }
    return 10
}
