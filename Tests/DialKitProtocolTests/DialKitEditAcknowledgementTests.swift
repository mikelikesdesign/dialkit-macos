import XCTest
@testable import DialkitmacOSProtocol

final class DialKitEditAcknowledgementTests: XCTestCase {
    // Match the wire shapes used before edit IDs were introduced.
    private enum LegacyInspectorMessage: Codable, Equatable {
        case setControlValue(panelID: UUID, path: String, value: DialKitControlValue)
        case setMotionComponent(panelID: UUID, path: String, component: DialKitMotionComponent)
    }
    private struct LegacySnapshot: Codable, Equatable {
        var id: UUID
        var appName: String
        var panels: [DialKitPanelSnapshot]
    }

    func testNewAndLegacyEditMessagesRemainWireCompatible() throws {
        let panelID = UUID()
        let editID = UUID()
        let pairs: [(LegacyInspectorMessage, DialKitInspectorMessage, DialKitInspectorMessage)] = [
            (.setControlValue(panelID: panelID, path: "value", value: .number(0.3)),
             .setControlValue(panelID: panelID, path: "value", value: .number(0.3)),
             .setControlValue(panelID: panelID, path: "value", value: .number(0.3), editID: editID)),
            (.setMotionComponent(panelID: panelID, path: "motion", component: .duration(0.3)),
             .setMotionComponent(panelID: panelID, path: "motion", component: .duration(0.3)),
             .setMotionComponent(panelID: panelID, path: "motion", component: .duration(0.3), editID: editID))
        ]
        for (legacy, withoutID, withID) in pairs {
            XCTAssertEqual(try JSONDecoder().decode(DialKitInspectorMessage.self, from: JSONEncoder().encode(legacy)), withoutID)
            XCTAssertEqual(try JSONDecoder().decode(LegacyInspectorMessage.self, from: JSONEncoder().encode(withID)), legacy)
            var wire = try DialKitWireCodec.encode(withID)
            XCTAssertEqual(try DialKitWireCodec.decodeAvailableMessages(from: &wire, as: DialKitInspectorMessage.self), [withID])
        }
    }

    func testSnapshotAcknowledgementIsOptionalAndRoundTrips() throws {
        let legacy = LegacySnapshot(id: UUID(), appName: "Test", panels: [])
        var snapshot = try JSONDecoder().decode(DialKitSessionSnapshot.self, from: JSONEncoder().encode(legacy))
        XCTAssertNil(snapshot.acknowledgedEditID)
        snapshot.acknowledgedEditID = UUID()
        let encoded = try JSONEncoder().encode(snapshot)
        XCTAssertEqual(try JSONDecoder().decode(LegacySnapshot.self, from: encoded), legacy)
        XCTAssertEqual(try JSONDecoder().decode(DialKitSessionSnapshot.self, from: encoded), snapshot)
    }
}
