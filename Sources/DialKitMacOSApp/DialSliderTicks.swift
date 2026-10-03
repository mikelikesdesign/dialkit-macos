import Foundation
import DialkitmacOSProtocol

enum DialSliderTicks {
    /// Interior tick positions in the same 0...1 coordinate space as the fill.
    static func positions(range: ClosedRange<Double>, step: Double) -> [Double] {
        let span = range.upperBound - range.lowerBound
        guard span.isFinite, span > 0, step.isFinite, step >= 0 else { return [] }

        // Coarse controls mark actual selectable values, including when the
        // step doesn't divide the range evenly. Endpoints need no interior tick.
        if step > 0, span / step <= 10 {
            var positions: [Double] = []
            for index in 1...10 {
                let value = DialNumber.round(range.lowerBound + Double(index) * step, step: step, within: range)
                let position = (value - range.lowerBound) / span
                if position > 0, position < 1, !positions.contains(position) {
                    positions.append(position)
                }
            }
            return positions
        }

        return (1...9).map { Double($0) / 10 }
    }
}
