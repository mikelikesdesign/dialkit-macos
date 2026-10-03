import Foundation

/// Each edit changes only its own field in the app's current motion value.
public enum DialKitMotionComponent: Codable, Equatable {
    case duration(Double)
    case bounce(Double)
    case stiffness(Double)
    case damping(Double)
    case mass(Double)
    case x1(Double)
    case y1(Double)
    case x2(Double)
    case y2(Double)
    case bezier(DialKitBezierValue)

    package func applying(to spring: DialKitSpringValue) -> DialKitSpringValue? {
        let next: DialKitSpringValue
        switch (spring, self) {
        case let (.time(_, bounce), .duration(value)): next = .time(duration: value, bounce: bounce)
        case let (.time(duration, _), .bounce(value)): next = .time(duration: duration, bounce: value)
        case let (.physics(_, damping, mass), .stiffness(value)): next = .physics(stiffness: value, damping: damping, mass: mass)
        case let (.physics(stiffness, _, mass), .damping(value)): next = .physics(stiffness: stiffness, damping: value, mass: mass)
        case let (.physics(stiffness, damping, _), .mass(value)): next = .physics(stiffness: stiffness, damping: damping, mass: value)
        default: return nil
        }
        return next.isValid ? next : nil
    }

    package func applying(to transition: DialKitTransitionValue) -> DialKitTransitionValue? {
        switch transition {
        case let .spring(spring):
            return applying(to: spring).map(DialKitTransitionValue.spring)
        case let .easing(duration, bezier):
            var nextDuration = duration
            var nextBezier = bezier
            switch self {
            case let .duration(value): nextDuration = value
            case let .x1(value): nextBezier.x1 = value
            case let .y1(value): nextBezier.y1 = value
            case let .x2(value): nextBezier.x2 = value
            case let .y2(value): nextBezier.y2 = value
            case let .bezier(value): nextBezier = value
            default: return nil
            }
            let next = DialKitTransitionValue.easing(duration: nextDuration, bezier: nextBezier)
            return next.isValid ? next : nil
        }
    }
}
