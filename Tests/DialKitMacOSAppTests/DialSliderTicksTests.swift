import XCTest
@testable import DialkitmacOSApp

final class DialSliderTicksTests: XCTestCase {
    func testContinuousAndFineSlidersMarkExactTenths() {
        let expected = (1...9).map { Double($0) / 10 }
        XCTAssertEqual(DialSliderTicks.positions(range: 0...100, step: 0), expected)
        XCTAssertEqual(DialSliderTicks.positions(range: 0...100, step: 1), expected)
        XCTAssertEqual(DialSliderTicks.positions(range: -50...50, step: 0.1), expected)
    }

    func testCoarseTicksMatchClickValuesAtAnyTrackWidth() {
        let positions = DialSliderTicks.positions(range: -5...5, step: 2)
        XCTAssertEqual(positions, [0.2, 0.4, 0.6, 0.8])
        for width in [100.0, 280, 350] {
            for (position, expected) in zip(positions, [-3.0, -1, 1, 3]) {
                var editing = DialSliderEditingState()
                editing.begin(remote: -5)
                XCTAssertEqual(editing.endPointer(at: position * width, translation: .zero, width: width, remote: -5, range: -5...5, step: 2), expected)
            }
        }
    }

    func testUnevenStepKeepsLastInteriorTick() {
        XCTAssertEqual(DialSliderTicks.positions(range: 0...1, step: 0.3), [0.3, 0.6, 0.9])
        XCTAssertEqual(DialSliderTicks.positions(range: 0...10, step: 3), [0.3, 0.6, 0.9])
    }

    func testEndpointsAreNotDuplicatedAsTicks() {
        XCTAssertEqual(DialSliderTicks.positions(range: 0...1, step: 0.1), (1...9).map { Double($0) / 10 })
        XCTAssertTrue(DialSliderTicks.positions(range: 0...1, step: 1).isEmpty)
        XCTAssertTrue(DialSliderTicks.positions(range: 0...1, step: 2).isEmpty)
    }

    func testDegenerateRangesAndInvalidStepsHaveNoTicks() {
        XCTAssertTrue(DialSliderTicks.positions(range: 4...4, step: 0).isEmpty)
        XCTAssertTrue(DialSliderTicks.positions(range: 0...1, step: .nan).isEmpty)
        XCTAssertTrue(DialSliderTicks.positions(range: 0...1, step: -1).isEmpty)
    }
}
