import Combine
import DialkitmacOS
import SwiftUI

#if DEBUG
import DialkitmacOSAgent
#endif

struct CardModel: Codable, Equatable {
    var title = "Good evening"
    var subtitle = "Tune me from the Mac inspector"
    var cornerRadius = 28.0
    var padding = 24.0
    var opacity = 1.0
    var showsBadge = true
    var fill = "#F97316"
    var textColor = "#FFFFFF"
    var style = "solid"
    var spring: DialSpring = .default
    var transition: DialTransition = .default

    static var controls: [DialControl<CardModel>] {
        [
            .text("title", keyPath: \.title),
            .text("subtitle", keyPath: \.subtitle),
            .group(
                "layout",
                children: [
                    .slider("cornerRadius", keyPath: \.cornerRadius, range: 0...64, step: 1, unit: "pt"),
                    .slider("padding", keyPath: \.padding, range: 0...48, step: 1, unit: "pt"),
                    .slider("opacity", keyPath: \.opacity, range: 0...1, step: 0.05)
                ]
            ),
            .group(
                "appearance",
                children: [
                    .toggle("showsBadge", keyPath: \.showsBadge),
                    .color("fill", keyPath: \.fill),
                    .color("textColor", keyPath: \.textColor),
                    .select("style", keyPath: \.style, options: ["solid", "glass", "outline"])
                ]
            ),
            .group(
                "motion",
                children: [
                    .spring("spring", keyPath: \.spring),
                    .transition("transition", keyPath: \.transition),
                    .action("bounce"),
                    .action("shuffleColor")
                ]
            )
        ]
    }
}

/// Owns the panel state and handles action controls sent from the inspector.
@MainActor
final class CardDemoModel: ObservableObject {
    @Published var bounceTrigger = 0
    let dial: DialPanelState<CardModel>
    private var cancellable: AnyCancellable?

    init() {
        var handleAction: ((String) -> Void)?
        dial = DialPanelState(
            name: "Card",
            initial: CardModel(),
            controls: CardModel.controls,
            onAction: { handleAction?($0) }
        )
        handleAction = { [weak self] path in
            self?.perform(path)
        }
        // Re-render whenever the inspector changes a value.
        cancellable = dial.objectWillChange.sink { [weak self] _ in
            self?.objectWillChange.send()
        }
    }

    private func perform(_ path: String) {
        switch path {
        case "motion.bounce":
            bounceTrigger += 1
        case "motion.shuffleColor":
            let palette = ["#F97316", "#3B82F6", "#10B981", "#EC4899", "#8B5CF6"]
            dial.values.fill = palette.filter { $0 != dial.values.fill }.randomElement() ?? "#F97316"
        default:
            break
        }
    }
}

struct ContentView: View {
    @StateObject private var model = CardDemoModel()

    var body: some View {
        ZStack {
            Color(.systemGroupedBackground).ignoresSafeArea()

            VStack(spacing: 24) {
                card
                    .padding(.horizontal, 24)

                Text("Edit values in the Dialkit macOS inspector.\nChanges appear here live.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
    }

    private var card: some View {
        let values = model.dial.values
        let bounceTrigger = model.bounceTrigger
        let shape = RoundedRectangle(cornerRadius: values.cornerRadius, style: .continuous)

        return VStack(alignment: .leading, spacing: 8) {
            if values.showsBadge {
                Text("NEW")
                    .font(.caption2.weight(.heavy))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Capsule().fill(.white.opacity(0.25)))
                    .transition(.scale.combined(with: .opacity))
            }

            Text(values.title)
                .font(.title.weight(.bold))

            Text(values.subtitle)
                .font(.subheadline)
                .opacity(0.85)
        }
        .foregroundStyle(color(values.textColor))
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(values.padding)
        .background {
            switch values.style {
            case "glass":
                shape.fill(.ultraThinMaterial)
                    .overlay(shape.fill(color(values.fill).opacity(0.35)))
            case "outline":
                shape.stroke(color(values.fill), lineWidth: 3)
            default:
                shape.fill(color(values.fill))
            }
        }
        .opacity(values.opacity)
        .scaleEffect(bounceTrigger % 2 == 0 ? 1 : 1.06)
        .animation(animation(for: values.spring), value: bounceTrigger)
        .animation(animation(for: values.transition), value: values)
    }

    private func animation(for transition: DialTransition) -> Animation {
        switch transition {
        case let .easing(duration, bezier):
            return .timingCurve(bezier.x1, bezier.y1, bezier.x2, bezier.y2, duration: duration)
        case let .spring(spring):
            return animation(for: spring)
        }
    }

    private func animation(for spring: DialSpring) -> Animation {
        switch spring {
        case let .time(duration, bounce):
            return .spring(duration: duration, bounce: bounce)
        case let .physics(stiffness, damping, mass):
            return .interpolatingSpring(mass: mass, stiffness: stiffness, damping: damping)
        }
    }

    private func color(_ hex: String) -> Color {
        var cleaned = hex.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: "#", with: "")
        if cleaned.count == 3 {
            cleaned = cleaned.map { "\($0)\($0)" }.joined()
        }
        var value: UInt64 = 0
        guard Scanner(string: cleaned).scanHexInt64(&value) else { return .orange }
        switch cleaned.count {
        case 6:
            return Color(
                red: Double((value >> 16) & 0xFF) / 255,
                green: Double((value >> 8) & 0xFF) / 255,
                blue: Double(value & 0xFF) / 255
            )
        case 8:
            return Color(
                red: Double((value >> 24) & 0xFF) / 255,
                green: Double((value >> 16) & 0xFF) / 255,
                blue: Double((value >> 8) & 0xFF) / 255,
                opacity: Double(value & 0xFF) / 255
            )
        default:
            return .orange
        }
    }
}

#Preview {
    ContentView()
        .task {
            #if DEBUG
            DialKitAgent.shared.start(appName: "Dialkit Demo Preview")
            #endif
        }
}
