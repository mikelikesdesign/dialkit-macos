import XCTest
@testable import DialkitmacOSApp

final class SpringResponseTests: XCTestCase {
    func testMatchesKnownUnderdampedCriticalAndOverdampedResponses() {
        for time in [0.0, 0.01, 0.1, 0.5, 1, 2] {
            XCTAssertEqual(SpringResponse.position(at: time, stiffness: 2, damping: 2, mass: 1),
                           1 - exp(-time) * (cos(time) + sin(time)), accuracy: 1e-12)
            XCTAssertEqual(SpringResponse.position(at: time, stiffness: 1, damping: 2, mass: 1),
                           1 - exp(-time) * (1 + time), accuracy: 1e-12)
            XCTAssertEqual(SpringResponse.position(at: time, stiffness: 2, damping: 3, mass: 1),
                           1 - 2 * exp(-time) + exp(-2 * time), accuracy: 1e-12)
        }
        XCTAssertEqual(SpringResponse.position(at: .pi, stiffness: 1, damping: 0, mass: 1), 2, accuracy: 1e-12)
    }

    func testPreviouslyUnstableSpringsSettleMonotonically() {
        let frequency = 2 * Double.pi / 0.1
        for (stiffness, damping, mass) in [(200.0, 25.0, 0.1), (frequency * frequency, 2 * frequency, 1.0)] {
            var previous = 0.0
            for index in 0...100 {
                let value = SpringResponse.position(at: Double(index) * 0.02, stiffness: stiffness, damping: damping, mass: mass)
                XCTAssertTrue(value.isFinite)
                XCTAssertGreaterThanOrEqual(value, previous - 1e-12)
                XCTAssertLessThanOrEqual(value, 1 + 1e-12)
                previous = value
            }
            XCTAssertEqual(previous, 1, accuracy: 1e-6)
        }
    }

    func testEditorParameterExtremesStayFiniteAndBounded() {
        for stiffness in [1.0, 200, 1000] {
            for damping in [1.0, 25, 100] {
                for mass in [0.1, 1, 10] {
                    for index in 0...100 {
                        let value = SpringResponse.position(at: Double(index) * 0.02, stiffness: stiffness, damping: damping, mass: mass)
                        XCTAssertTrue(value.isFinite)
                        XCTAssertGreaterThanOrEqual(value, -1e-12)
                        XCTAssertLessThanOrEqual(value, 2 + 1e-12)
                    }
                }
            }
        }
    }

    func testNearCriticalDampingIsContinuous() {
        let critical = SpringResponse.position(at: 0.2, stiffness: 100, damping: 20, mass: 1)
        for damping in [20 - 1e-6, 20 - 1e-9, 20 + 1e-9, 20 + 1e-6] {
            XCTAssertEqual(SpringResponse.position(at: 0.2, stiffness: 100, damping: damping, mass: 1), critical, accuracy: 1e-7)
        }
    }
}
