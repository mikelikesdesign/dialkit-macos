import Foundation

/// Exact unit-step response from rest. Unlike a fixed-step Euler simulation,
/// this remains stable for stiff, highly damped, and low-mass springs.
enum SpringResponse {
    static func position(at time: Double, stiffness: Double, damping: Double, mass: Double) -> Double {
        guard time.isFinite, time > 0,
              stiffness.isFinite, stiffness > 0,
              damping.isFinite, damping >= 0,
              mass.isFinite, mass > 0 else { return 0 }

        let frequency = sqrt(stiffness / mass)
        let decay = damping / (2 * mass)
        guard frequency.isFinite, decay.isFinite else { return 0 }

        if abs(decay - frequency) <= frequency * 1e-8 {
            // Critical damping, including the limit from either side.
            return 1 - exp(-decay * time) * (1 + decay * time)
        }
        if decay < frequency {
            let dampedFrequency = sqrt((frequency - decay) * (frequency + decay))
            let phase = dampedFrequency * time
            let sinc = abs(phase) < 1e-8 ? 1 : sin(phase) / phase
            return 1 - exp(-decay * time) * (cos(phase) + decay * time * sinc)
        }

        let root = sqrt((decay - frequency) * (decay + frequency))
        let fast = decay + root
        // Avoid subtracting nearly equal numbers for the slow decay rate.
        let slow = frequency * frequency / fast
        return 1 - (fast * exp(-slow * time) - slow * exp(-fast * time)) / (fast - slow)
    }
}
