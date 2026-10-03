import XCTest
@testable import DialkitmacOSApp

final class DialSliderPointerTests: XCTestCase {
    func testClickJumpsOnReleaseWithoutChangingValueOnMouseDown() {
        var editing = DialSliderEditingState()
        editing.begin(remote: 20)
        XCTAssertNil(editing.updatePointer(translation: .zero, width: 200, range: 0...100, step: 1))
        XCTAssertEqual(editing.displayedValue(remote: 20), 20)
        XCTAssertTrue(editing.isClick(translation: .zero))
        XCTAssertEqual(editing.endPointer(at: 150, translation: .zero, width: 200, remote: 20, range: 0...100, step: 1), 75)
        XCTAssertFalse(editing.isDragging)
        XCTAssertEqual(editing.displayedValue(remote: 20), 75)
        editing.receive(75)
        XCTAssertNil(editing.pendingValue)
    }

    func testSmallPointerJitterStillClicksAtItsPosition() {
        var editing = DialSliderEditingState()
        editing.begin(remote: 20)
        let jitter = CGSize(width: 2, height: 1)
        XCTAssertNil(editing.updatePointer(translation: jitter, width: 100, range: 0...100, step: 1))
        XCTAssertEqual(editing.endPointer(at: 82, translation: jitter, width: 100, remote: 20, range: 0...100, step: 1), 82)
    }

    func testDragStaysRelativeEvenWhenPressedFarFromCurrentValue() {
        var editing = DialSliderEditingState()
        editing.begin(remote: 20)
        // Press at x=80, then move ten points right: scrub 20 -> 30, not 90.
        let translation = CGSize(width: 10, height: 0)
        XCTAssertEqual(editing.updatePointer(translation: translation, width: 100, range: 0...100, step: 1), 30)
        XCTAssertFalse(editing.isClick(translation: translation))
        XCTAssertNil(editing.endPointer(at: 90, translation: translation, width: 100, remote: 20, range: 0...100, step: 1))
        XCTAssertEqual(editing.displayedValue(remote: 20), 30)
    }

    func testDragReturningToStartDoesNotBecomeClick() {
        var editing = DialSliderEditingState()
        editing.begin(remote: 20)
        XCTAssertEqual(editing.updatePointer(translation: CGSize(width: 10, height: 0), width: 100, range: 0...100, step: 1), 30)
        XCTAssertFalse(editing.isClick(translation: .zero))
        XCTAssertEqual(editing.endPointer(at: 80, translation: .zero, width: 100, remote: 20, range: 0...100, step: 1), 20)
        XCTAssertEqual(editing.displayedValue(remote: 20), 20)
    }

    func testClickUsesConfiguredStepAndClampsEndpoints() {
        for (position, expected) in [(-10.0, -5.0), (0, -5), (37, -1), (100, 5), (120, 5)] {
            var editing = DialSliderEditingState()
            editing.begin(remote: 1)
            XCTAssertEqual(editing.endPointer(at: position, translation: .zero, width: 100, remote: 1, range: -5...5, step: 2), expected)
        }
    }

    func testClickAcknowledgesAdjustedValueAndNextScrubUsesPendingClick() {
        var editing = DialSliderEditingState()
        editing.begin(remote: 0)
        XCTAssertEqual(editing.endPointer(at: 30, translation: .zero, width: 100, remote: 0, range: 0...1, step: 0), 0.3)
        editing.begin(remote: 0)
        XCTAssertEqual(editing.updatePointer(translation: CGSize(width: 10, height: 0), width: 100, range: 0...1, step: 0), 0.4)
        editing.receive(0.5, acknowledgingEdit: true)
        editing.end(remote: 0.5)
        XCTAssertNil(editing.pendingValue)
        XCTAssertEqual(editing.displayedValue(remote: 0.5), 0.5)
    }
}
