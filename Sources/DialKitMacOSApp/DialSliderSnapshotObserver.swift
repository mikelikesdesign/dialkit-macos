import Combine
import SwiftUI
import DialkitmacOSProtocol

/// Identifies a numeric row independently of SwiftUI's rendered snapshot.
struct DialSliderValueSource {
    enum Field { case value, duration, bounce, stiffness, damping, mass, x1, y1, x2, y2 }

    let panelID: UUID
    let path: String
    var field: Field = .value

    func component(_ field: Field) -> Self {
        Self(panelID: panelID, path: path, field: field)
    }

    func value(in snapshot: DialKitSessionSnapshot?) -> Double? {
        guard let panel = snapshot?.panels.first(where: { $0.id == panelID }),
              let control = find(in: panel.controls) else { return nil }
        return value(in: control.kind)
    }

    private func find(in controls: [DialKitControlSnapshot]) -> DialKitControlSnapshot? {
        for control in controls {
            if control.path == path { return control }
            if case let .group(_, children) = control.kind, let found = find(in: children) { return found }
        }
        return nil
    }

    private func value(in kind: DialKitControlKind) -> Double? {
        switch kind {
        case let .slider(value, _, _, _, _) where field == .value: return value
        case let .spring(spring):
            switch (spring, field) {
            case let (.time(duration, _), .duration): return duration
            case let (.time(_, bounce), .bounce): return bounce
            case let (.physics(stiffness, _, _), .stiffness): return stiffness
            case let (.physics(_, damping, _), .damping): return damping
            case let (.physics(_, _, mass), .mass): return mass
            default: return nil
            }
        case let .transition(transition):
            switch transition {
            case let .spring(spring): return value(in: .spring(value: spring))
            case let .easing(duration, bezier):
                switch field {
                case .duration: return duration
                case .x1: return bezier.x1
                case .y1: return bezier.y1
                case .x2: return bezier.x2
                case .y2: return bezier.y2
                default: return nil
                }
            }
        default: return nil
        }
    }
}

struct DialSliderSnapshotObserver: ViewModifier {
    @EnvironmentObject private var service: DialKitInspectorService
    let source: DialSliderValueSource
    let receive: (Double, Bool) -> Void

    func body(content: Content) -> some View {
        // onChange observes rendered values and can skip an acknowledgement
        // when several snapshots arrive in one main-queue turn. onReceive
        // delivers each snapshot, including values that never reach a redraw.
        content.onReceive(service.$snapshot.compactMap { $0 }) { snapshot in
            guard let value = source.value(in: snapshot) else { return }
            receive(value, service.acknowledgesLatestEdit(snapshot, panelID: source.panelID, path: source.path))
        }
    }
}
