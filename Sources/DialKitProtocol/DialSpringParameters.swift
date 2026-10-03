import Foundation

package enum DialMotionDefaults {
    package static func springDuration(from duration: Double) -> Double {
        duration.isFinite && duration > 0 ? duration : 0.1
    }
}

package extension DialKitSpringValue {
    /// Shared by the model API and inspector graph. Preserve all valid physics
    /// parameters; editor slider bounds must not change an animation's response.
    var resolvedPhysics: (stiffness: Double, damping: Double, mass: Double) {
        switch self {
        case let .time(duration, bounce):
            let resolvedDuration = max(DialMotionDefaults.springDuration(from: duration), 0.1)
            let stiffness = pow((2 * Double.pi) / resolvedDuration, 2)
            let resolvedBounce = bounce.isFinite ? min(max(bounce, 0), 1) : 0
            return (stiffness, 2 * (1 - resolvedBounce) * sqrt(stiffness), 1)
        case let .physics(stiffness, damping, mass):
            return (
                stiffness.isFinite && stiffness > 0 ? stiffness : 1,
                damping.isFinite && damping >= 0 ? damping : 1,
                mass.isFinite && mass > 0 ? mass : 0.1
            )
        }
    }
}
