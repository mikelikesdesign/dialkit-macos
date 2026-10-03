import Combine
import XCTest
@testable import DialkitmacOSCore

@MainActor
final class DialKitValuePublicationTests: XCTestCase {
    struct Model: Codable, Equatable {
        var spring: DialSpring = .default
        var transition: DialTransition = .default
        var value = 0.0
        static var controls: [DialControl<Self>] {
            [.group("motion", children: [.spring("spring", keyPath: \.spring), .transition("transition", keyPath: \.transition)]),
             .slider("value", keyPath: \.value, range: 0...100)]
        }
    }

    func testInvalidMotionAssignmentsPublishOnlyNormalizedValues() {
        let panel = DialPanelState(name: "Validated", initial: Model(), controls: Model.controls)
        var published: [Model] = []
        let subscription = panel.$values.sink { published.append($0) }
        defer { subscription.cancel() }
        panel.values.spring = .physics(stiffness: -200, damping: 25, mass: 0)
        panel.values.transition = .easing(duration: -1, bezier: .standard)
        XCTAssertEqual(published, [Model(), Model(), Model()])
        XCTAssertEqual(panel.values, Model())
    }

    func testNormalizedReplacementKeepsValidEditsAndNotifiesTheStore() {
        let panel = DialPanelState(name: "Validated", initial: Model(), controls: Model.controls)
        var published: [Model] = []
        var storeNotifications = 0
        let valuesObserver = panel.$values.dropFirst().sink { published.append($0) }
        let storeObserver = DialStore.shared.objectWillChange.sink { storeNotifications += 1 }
        defer { valuesObserver.cancel(); storeObserver.cancel() }
        var replacement = Model()
        replacement.value = 42
        replacement.spring = .time(duration: 0, bounce: 0.2)
        replacement.transition = .easing(duration: 1, bezier: .init(x1: 2, y1: 0, x2: 1, y2: 1))
        panel.values = replacement
        XCTAssertEqual(published, [Model(value: 42)])
        XCTAssertEqual(panel.values, Model(value: 42))
        XCTAssertGreaterThan(storeNotifications, 0)
        panel.savePreset(named: "Valid")
        XCTAssertEqual(panel.presets.first?.values, Model(value: 42))
    }

    func testMainQueueSubscribersNeverReceiveInvalidMotion() async throws {
        let panel = DialPanelState(name: "Queued", initial: Model(), controls: Model.controls)
        var published: [Model] = []
        let delivered = expectation(description: "Normalized value delivered")
        let subscription = panel.$values.dropFirst().receive(on: DispatchQueue.main).sink {
            published.append($0)
            delivered.fulfill()
        }
        defer { subscription.cancel() }
        panel.values.spring = .physics(stiffness: 0, damping: 1, mass: 1)
        await fulfillment(of: [delivered], timeout: 2)
        XCTAssertEqual(published, [Model()])
    }

    func testValidMemberEditsKeepPublisherAndPresetBehavior() throws {
        let panel = DialPanelState(name: "Valid", initial: Model(), controls: Model.controls)
        var published: [Model] = []
        let subscription = panel.$values.sink { published.append($0) }
        defer { subscription.cancel() }
        panel.values.value = 20
        panel.savePreset(named: "A")
        let presetID = try XCTUnwrap(panel.activePresetID)
        panel.values.value = 40
        panel.clearActivePreset()
        panel.loadPreset(id: presetID)
        XCTAssertEqual(published.map(\.value), [0, 20, 40, 20, 40])
        XCTAssertEqual(panel.presets.first?.values.value, 40)
    }

    func testCombineAssignAcceptsImmediateValuesAndNotifiesSubscribers() {
        let panel = DialPanelState(name: "Combine", initial: Model(), controls: Model.controls)
        var published: [Model] = []
        var notifications = 0
        let valuesObserver = panel.$values.sink { published.append($0) }
        let changes = panel.objectWillChange.sink { notifications += 1 }
        defer { valuesObserver.cancel(); changes.cancel() }
        Just(Model(value: 42)).assign(to: &panel.$values)
        XCTAssertEqual(panel.values.value, 42)
        XCTAssertEqual(published, [Model(), Model(value: 42)])
        XCTAssertGreaterThan(notifications, 0)
    }

    func testCombineAssignValidatesMotionAndKeepsPresetChanges() throws {
        let panel = DialPanelState(name: "Combine", initial: Model(), controls: Model.controls)
        let input = PassthroughSubject<Model, Never>()
        input.assign(to: &panel.$values)
        var published: [Model] = []
        let observer = panel.$values.dropFirst().sink { published.append($0) }
        defer { observer.cancel() }
        panel.savePreset(named: "Preset")
        let presetID = try XCTUnwrap(panel.activePresetID)
        input.send(Model(spring: .physics(stiffness: -200, damping: 25, mass: 0),
                         transition: .easing(duration: -1, bezier: .standard), value: 42))
        XCTAssertEqual(published, [Model(value: 42)])
        XCTAssertEqual(panel.presets.first?.values, Model(value: 42))
        panel.clearActivePreset()
        XCTAssertEqual(panel.values.value, 0)
        panel.loadPreset(id: presetID)
        XCTAssertEqual(panel.values.value, 42)
        input.send(Model(value: 70))
        XCTAssertEqual(panel.values.value, 70)
        XCTAssertEqual(published.last, Model(value: 70))
    }

    func testCombineAssignCancelsWhenPanelIsReleased() {
        var panel: DialPanelState<Model>? = DialPanelState(name: "Lifetime", initial: Model(), controls: Model.controls)
        weak var weakPanel = panel
        let input = PassthroughSubject<Model, Never>()
        var cancelled = false
        input.handleEvents(receiveCancel: { cancelled = true }).assign(to: &panel!.$values)
        // Keeping a publisher must not keep its panel or input subscription alive.
        let output = panel!.$values
        panel = nil
        XCTAssertNil(weakPanel)
        XCTAssertTrue(cancelled)
        input.send(Model(value: 99))
        withExtendedLifetime(output) {}
    }
}
