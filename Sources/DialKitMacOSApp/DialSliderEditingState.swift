import Foundation
import DialkitmacOSProtocol

/// The pointer owns the displayed value during a drag. Older network echoes
/// cannot move it backwards, including while the final edit is in flight.
struct DialSliderEditingState {
    private(set) var isDragging = false
    private(set) var startValue: Double?
    private(set) var pendingValue: Double?

    func displayedValue(remote: Double) -> Double { pendingValue ?? remote }

    mutating func begin(remote: Double) {
        guard !isDragging else { return }
        startValue = displayedValue(remote: remote)
        isDragging = true
    }

    mutating func update(translation: Double, width: Double, range: ClosedRange<Double>, step: Double) -> Double? {
        guard let startValue else { return nil }
        let raw = startValue + translation / max(width, 1) * (range.upperBound - range.lowerBound)
        let next = DialNumber.round(raw, step: step, within: range)
        guard next != (pendingValue ?? startValue) else { return nil }
        pendingValue = next
        return next
    }

    mutating func commit(_ value: Double) { pendingValue = value }

    mutating func receive(_ value: Double) {
        if !isDragging, pendingValue == value { pendingValue = nil }
    }

    mutating func end(remote: Double) {
        isDragging = false
        startValue = nil
        receive(remote)
    }
}
