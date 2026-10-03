import Foundation
import DialkitmacOSProtocol

/// The pointer owns the displayed value during a drag. Older network echoes
/// cannot move it backwards, including while the final edit is in flight.
struct DialSliderEditingState {
    private(set) var isDragging = false
    private(set) var startValue: Double?
    private(set) var pendingValue: Double?
    private var step = 0.0

    func displayedValue(remote: Double) -> Double { pendingValue ?? remote }

    mutating func begin(remote: Double) {
        guard !isDragging else { return }
        startValue = displayedValue(remote: remote)
        isDragging = true
    }

    mutating func update(translation: Double, width: Double, range: ClosedRange<Double>, step: Double) -> Double? {
        guard let startValue else { return nil }
        self.step = step
        let raw = startValue + translation / max(width, 1) * (range.upperBound - range.lowerBound)
        let next = DialNumber.round(raw, step: step, within: range)
        guard next != (pendingValue ?? startValue) else { return nil }
        pendingValue = next
        return next
    }

    /// An unchanged value will not trigger the view's onChange observer, so it
    /// must not leave an edit waiting for an acknowledgement that cannot arrive.
    @discardableResult
    mutating func commit(_ value: Double, remote: Double, step: Double) -> Bool {
        self.step = step
        let hadPendingEdit = pendingValue != nil
        pendingValue = matches(value, remote) ? nil : value
        // Still send a revert when an earlier edit is in flight.
        return hadPendingEdit || pendingValue != nil
    }

    mutating func receive(_ value: Double) {
        if !isDragging, let pendingValue, matches(pendingValue, value) {
            self.pendingValue = nil
        }
    }

    mutating func end(remote: Double) {
        isDragging = false
        startValue = nil
        receive(remote)
    }

    private func matches(_ expected: Double, _ actual: Double) -> Bool {
        if expected == actual { return true }
        guard expected.isFinite, actual.isFinite, step.isFinite, step > 0 else { return false }
        // Float-backed models round the Double sent over the wire. Bound the
        // tolerance below a step so a delayed neighbouring value cannot clear it.
        let floatError = max(abs(expected), abs(actual)) * Double(Float.ulpOfOne)
        return abs(expected - actual) <= min(step / 4, floatError)
    }
}
