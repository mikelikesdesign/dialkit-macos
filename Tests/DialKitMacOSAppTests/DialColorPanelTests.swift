import AppKit
import XCTest
@testable import DialkitmacOSApp

@MainActor
final class DialColorPanelTests: XCTestCase {
    func testDisappearingRowReleasesPickerCallback() {
        let panel = NSColorPanel()
        let picker = DialNativeColorPanel(panel: panel)
        let owner = UUID()
        var edits = 0
        picker.beginEditing(owner: owner, hexValue: "#FF0000") { _ in edits += 1 }
        NotificationCenter.default.post(name: NSColorPanel.colorDidChangeNotification, object: panel)
        XCTAssertEqual(edits, 1)
        picker.endEditing(owner: owner)
        NotificationCenter.default.post(name: NSColorPanel.colorDidChangeNotification, object: panel)
        XCTAssertEqual(edits, 1)
    }

    func testChangingRowsDoesNotSendInitializationToPreviousRowOrCloseNewSession() {
        let panel = NSColorPanel()
        let picker = DialNativeColorPanel(panel: panel)
        let first = UUID(), second = UUID()
        var oldEdits = 0, newEdits = 0
        picker.beginEditing(owner: first, hexValue: "#FF0000") { _ in oldEdits += 1 }
        picker.beginEditing(owner: second, hexValue: "#0000FF") { _ in newEdits += 1 }
        XCTAssertEqual(oldEdits, 0)
        XCTAssertEqual(newEdits, 0)
        picker.endEditing(owner: first)
        NotificationCenter.default.post(name: NSColorPanel.colorDidChangeNotification, object: panel)
        XCTAssertEqual(oldEdits, 0)
        XCTAssertEqual(newEdits, 1)
        NotificationCenter.default.post(name: NSWindow.willCloseNotification, object: panel)
        NotificationCenter.default.post(name: NSColorPanel.colorDidChangeNotification, object: panel)
        XCTAssertEqual(newEdits, 1)
    }
}
