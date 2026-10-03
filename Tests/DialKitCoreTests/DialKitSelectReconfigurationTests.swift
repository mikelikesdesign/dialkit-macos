import XCTest
@testable import DialkitmacOSCore

@MainActor
final class DialKitSelectReconfigurationTests: XCTestCase {
    struct Model: Codable, Equatable { var choice = "old" }

    private func controls(_ options: [String]) -> [DialControl<Model>] {
        [.group("appearance", children: [.select("choice", keyPath: \.choice, options: options)])]
    }

    func testReplacingOptionsRepairsCurrentBaseAndEveryPreset() throws {
        let panel = DialPanelState(name: "Select", initial: Model(), controls: controls(["old", "keep"]))
        panel.savePreset(named: "Removed")
        let removedID = try XCTUnwrap(panel.activePresetID)
        panel.savePreset(named: "Kept")
        let keptID = try XCTUnwrap(panel.activePresetID)
        panel.values.choice = "keep"
        panel.loadPreset(id: removedID)

        panel.configure(controls: controls(["new", "keep"]))

        XCTAssertEqual(panel.values.choice, "new")
        XCTAssertEqual(panel.activePresetID, removedID)
        XCTAssertEqual(panel.presets.map(\.values.choice), ["new", "keep"])
        panel.clearActivePreset()
        XCTAssertEqual(panel.values.choice, "new")
        panel.loadPreset(id: removedID)
        XCTAssertEqual(panel.values.choice, "new")
        panel.loadPreset(id: keptID)
        XCTAssertEqual(panel.values.choice, "keep")
    }

    func testValidConfiguredFallbackTakesPriorityOverFirstOption() {
        let panel = DialPanelState(name: "Select", initial: Model(), controls: controls(["old"]))
        panel.savePreset(named: "Old")
        panel.configure(initial: Model(choice: "preferred"), controls: controls(["first", "preferred"]))
        XCTAssertEqual(panel.values.choice, "preferred")
        XCTAssertEqual(panel.presets.first?.values.choice, "preferred")
        panel.clearActivePreset()
        XCTAssertEqual(panel.values.choice, "preferred")
    }

    func testInvalidInitialSelectionUsesFirstOptionAndEmptyOptionsPreserveValue() {
        let panel = DialPanelState(name: "Select", initial: Model(), controls: controls(["new"]))
        XCTAssertEqual(panel.values.choice, "new")
        panel.configure(controls: controls([]))
        XCTAssertEqual(panel.values.choice, "new")
        panel.configure(controls: controls(["replacement"]))
        XCTAssertEqual(panel.values.choice, "replacement")
    }
}
