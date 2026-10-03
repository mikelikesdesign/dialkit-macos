import Foundation

/// Shared by the local controls and the remote inspector. Editor text uses a
/// decimal point and no grouping so formatting and parsing always round-trip.
package enum DialNumber {
    package static func precision(_ value: Double) -> Int {
        guard value.isFinite else { return 0 }
        let parts = String(abs(value)).lowercased().split(separator: "e")
        let fraction = parts[0].split(separator: ".").dropFirst().first ?? ""
        let digits = fraction.replacingOccurrences(of: "0+$", with: "", options: .regularExpression).count
        let exponent = parts.count == 2 ? Int(parts[1]) ?? 0 : 0
        return max(0, digits - exponent)
    }

    package static func format(_ value: Double, step: Double) -> String {
        var text = String(value)
        guard value.isFinite, !text.lowercased().contains("e") else { return text }
        if text.hasSuffix(".0") { text.removeLast(2) }
        let minimumDigits = min(precision(step), 12)
        let digits = text.split(separator: ".").dropFirst().first?.count ?? 0
        if digits < minimumDigits {
            if !text.contains(".") { text += "." }
            text += String(repeating: "0", count: minimumDigits - digits)
        }
        return text
    }

    package static func parse(_ text: String) -> Double? {
        guard let value = Double(text.trimmingCharacters(in: .whitespacesAndNewlines)),
              value.isFinite else { return nil }
        return value
    }

    package static func round(_ value: Double, step: Double, within range: ClosedRange<Double>) -> Double {
        guard value.isFinite else { return range.lowerBound }
        let clamped = min(max(value, range.lowerBound), range.upperBound)
        guard step.isFinite, step > 0 else { return clamped }

        // Decimal arithmetic preserves the step's offset from the lower bound,
        // without rounding that bound away or introducing binary step noise.
        let locale = Locale(identifier: "en_US_POSIX")
        guard let current = Decimal(string: String(clamped), locale: locale),
              let lower = Decimal(string: String(range.lowerBound), locale: locale),
              let increment = Decimal(string: String(step), locale: locale),
              increment > 0 else { return clamped }
        var offset = (current - lower) / increment
        var rounded = Decimal()
        NSDecimalRound(&rounded, &offset, 0, .plain)
        let decimalText = NSDecimalNumber(decimal: rounded * increment + lower).stringValue
        guard let result = Double(decimalText), result.isFinite else { return clamped }
        return min(max(result, range.lowerBound), range.upperBound)
    }
}
