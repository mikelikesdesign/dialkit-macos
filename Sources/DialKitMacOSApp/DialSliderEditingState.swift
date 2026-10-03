import Foundation
import DialkitmacOSProtocol

/// The pointer owns the displayed value during a drag. Older network echoes
/// cannot move it backwards, including while the final edit is in flight.
struct DialSliderEditingState {
    private(set) var isDragging = false
    private(set) var startValue: Double?
    private(set) var pendingValue: Double?
    private var step = 0.0
    private var pendingAcknowledged = false
    private var hasScrubbed = false
    private var numericType: DialKitSliderValueType

    init(numericType: DialKitSliderValueType = .double) {
        self.numericType = numericType
    }

    func displayedValue(remote: Double) -> Double { pendingValue ?? remote }

    mutating func resetForConfigurationChange() {
        self = Self(numericType: numericType)
    }

    mutating func configure(numericType: DialKitSliderValueType) {
        guard self.numericType != numericType else { return }
        self = Self(numericType: numericType)
    }

    mutating func begin(remote: Double) {
        guard !isDragging else { return }
        startValue = displayedValue(remote: remote)
        hasScrubbed = false
        isDragging = true
    }

    /// Wait for pointer intent before changing the value. Once a drag starts,
    /// returning to the original position must not turn it into a click.
    func isClick(translation: CGSize) -> Bool {
        isDragging && !hasScrubbed && hypot(translation.width, translation.height) <= 3
    }

    mutating func updatePointer(translation: CGSize, width: Double, range: ClosedRange<Double>, step: Double) -> Double? {
        guard isDragging else { return nil }
        if hypot(translation.width, translation.height) > 3 { hasScrubbed = true }
        guard hasScrubbed else { return nil }
        return update(translation: Double(translation.width), width: width, range: range, step: step)
    }

    mutating func endPointer(at position: Double, translation: CGSize, width: Double, remote: Double, range: ClosedRange<Double>, step: Double) -> Double? {
        guard isDragging else { return nil }
        let scrubbedValue = updatePointer(translation: translation, width: width, range: range, step: step)
        let next: Double?
        if hasScrubbed {
            next = scrubbedValue
        } else {
            let fraction = min(max(position / max(width, 1), 0), 1)
            let raw = range.lowerBound + fraction * (range.upperBound - range.lowerBound)
            let clickedValue = DialNumber.round(raw, step: step, within: range)
            next = commit(clickedValue, remote: remote, step: step) ? clickedValue : nil
        }
        end(remote: remote)
        return next
    }

    mutating func update(translation: Double, width: Double, range: ClosedRange<Double>, step: Double) -> Double? {
        guard let startValue else { return nil }
        self.step = step
        let raw = startValue + translation / max(width, 1) * (range.upperBound - range.lowerBound)
        let next = DialNumber.round(raw, step: step, within: range)
        guard next != (pendingValue ?? startValue) else { return nil }
        pendingValue = next
        pendingAcknowledged = false
        return next
    }

    /// An unchanged value needs no network round-trip or pending acknowledgement.
    @discardableResult
    mutating func commit(_ value: Double, remote: Double, step: Double) -> Bool {
        self.step = step
        let hadPendingEdit = pendingValue != nil
        pendingValue = matches(value, remote) ? nil : value
        pendingAcknowledged = false
        // Still send a revert when an earlier edit is in flight.
        return hadPendingEdit || pendingValue != nil
    }

    mutating func receive(_ value: Double, acknowledgingEdit: Bool = false) {
        // Computed setters can adjust or reject an edit. Its explicit response
        // is authoritative even when the resulting value differs from ours.
        guard let pendingValue, acknowledgingEdit || matches(pendingValue, value) else { return }
        // Keep the pointer's value visible until mouse-up, but remember the
        // acknowledgement even if the app sends newer values during the drag.
        pendingAcknowledged = isDragging
        if !isDragging { self.pendingValue = nil }
    }

    mutating func end(remote: Double) {
        isDragging = false
        hasScrubbed = false
        startValue = nil
        if pendingAcknowledged {
            pendingValue = nil
            pendingAcknowledged = false
        } else {
            receive(remote)
        }
    }

    private func matches(_ expected: Double, _ actual: Double) -> Bool {
        if expected == actual { return true }
        guard expected.isFinite, actual.isFinite, step.isFinite, step >= 0 else { return false }
        guard numericType == .float else { return false }
        let converted = Float(expected)
        guard converted.isFinite else { return false }
        // Match the app's actual Float wire representation, even when the step
        // is smaller than a Float ULP. Double controls always require equality.
        let echoed = step > 0 ? Double(String(converted)) : Double(converted)
        return actual == echoed
    }
}
