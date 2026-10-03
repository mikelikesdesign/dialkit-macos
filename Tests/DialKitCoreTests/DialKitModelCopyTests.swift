import XCTest
@testable import DialkitmacOSCore

@MainActor
final class DialKitModelCopyTests: XCTestCase {
    final class ReferenceModel: Codable, Equatable {
        var value: Double
        init(value: Double) { self.value = value }
        static func == (lhs: ReferenceModel, rhs: ReferenceModel) -> Bool { lhs.value == rhs.value }
    }

    func testReferenceModelPresetsAndBaseStayIndependent() throws {
        let initial = ReferenceModel(value: 20)
        let panel = DialPanelState(name: "References", initial: initial, controls: [
            .slider("value", keyPath: \.value, range: 0...100, step: 1)
        ])
        XCTAssertFalse(panel.values === initial)
        panel.savePreset(named: "A")
        let aID = try XCTUnwrap(panel.activePresetID)
        XCTAssertTrue(DialStore.shared.setRemoteControlValue(panelID: panel.id, path: "value", value: .number(40)))
        panel.savePreset(named: "B")
        XCTAssertTrue(DialStore.shared.setRemoteControlValue(panelID: panel.id, path: "value", value: .number(60)))
        panel.clearActivePreset()
        XCTAssertEqual(panel.values.value, 20)
        panel.loadPreset(id: aID)
        XCTAssertEqual(panel.values.value, 40)
        XCTAssertEqual(initial.value, 20)
        XCTAssertEqual(panel.presets.map { $0.values.value }, [40, 60])
    }

    func testNestedReferencePropertiesAreCopied() throws {
        struct Nested: Codable, Equatable { var child = ReferenceModel(value: 20) }
        let panel = DialPanelState(name: "Nested", initial: Nested(), controls: [
            .slider("value", keyPath: \.child.value, range: 0...100, step: 1)
        ])
        panel.savePreset(named: "A")
        XCTAssertTrue(DialStore.shared.setRemoteControlValue(panelID: panel.id, path: "value", value: .number(40)))
        panel.clearActivePreset()
        XCTAssertEqual(panel.values.child.value, 20)
        XCTAssertEqual(panel.presets.first?.values.child.value, 40)
    }

    func testReferenceConfigurationDoesNotMutateInitialOrOtherPresets() {
        let initial = ReferenceModel(value: 80)
        let panel = DialPanelState(name: "Configure", initial: initial, controls: [
            .slider("value", keyPath: \.value, range: 0...100, step: 1)
        ])
        panel.savePreset(named: "A")
        panel.configure(controls: [.slider("value", keyPath: \.value, range: 0...50, step: 1)])
        XCTAssertEqual(panel.values.value, 50)
        XCTAssertEqual(panel.presets.first?.values.value, 50)
        XCTAssertEqual(initial.value, 80)
        XCTAssertFalse(panel.values === panel.presets.first?.values)
    }

    func testReferenceCopySupportsNonFiniteNumbers() {
        let original = ReferenceModel(value: .nan)
        let copy = dialCopyModel(original)
        XCTAssertFalse(copy === original)
        XCTAssertTrue(copy.value.isNaN)
        for value in [Double.infinity, -Double.infinity] {
            XCTAssertEqual(dialCopyModel(ReferenceModel(value: value)).value, value)
        }
    }

    func testValueModelsKeepPropertiesExcludedFromCodingKeys() {
        struct ValueModel: Codable, Equatable {
            var value = 20.0
            var transient = 99
            enum CodingKeys: String, CodingKey { case value }
        }
        let panel = DialPanelState(name: "Value model", initial: ValueModel(), controls: [
            .slider("value", keyPath: \.value, range: 0...100, step: 1)
        ])
        XCTAssertTrue(DialStore.shared.setRemoteControlValue(panelID: panel.id, path: "value", value: .number(40)))
        panel.savePreset(named: "A")
        XCTAssertEqual(panel.values.transient, 99)
        XCTAssertEqual(panel.presets.first?.values.transient, 99)
    }
}
