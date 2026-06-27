# DialKit macOS

DialKit macOS is the companion-inspector version of DialKit. It lets an iOS Simulator, Xcode Preview, or local macOS app expose live `DialPanelState` values to a standalone Mac inspector window.

This package is separate from [`dialkit-ios`](https://github.com/mikelikesdesign/dialkit-ios). The iOS package renders the DialKit drawer inside the app with `import DialKit`. This package uses `import DialkitmacOS` and keeps the control UI outside the tuned app.

There is no app download to install. Add this repository as a Swift Package dependency, link the debug agent into the app you are tuning, then run the inspector from this package checkout with SwiftPM.

## Install

Add this repository as a Swift Package dependency in Xcode:

```text
https://github.com/mikelikesdesign/dialkit-macos
```

Link these package products to the app target you want to tune:

- `DialkitmacOS`
- `DialkitmacOSAgent`

Start the agent only in debug builds:

```swift
import SwiftUI

#if DEBUG
import DialkitmacOSAgent
#endif

@main
struct MyApp: App {
    init() {
        #if DEBUG
        DialKitAgent.shared.start(appName: "MyApp")
        #endif
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
```

For isolated Xcode Previews, start the agent inside the preview too, because `App.init()` may not run:

```swift
#Preview {
    ContentView()
        .task {
            #if DEBUG
            DialKitAgent.shared.start(appName: "ContentView Preview")
            #endif
        }
}
```

## Define Tunable Values

Use `DialPanelState` as the source of truth for the values you want to tune. Do not add `DialRoot`, a floating button, or an in-app drawer for the macOS workflow.

```swift
import DialkitmacOS
import SwiftUI

struct CardModel: Codable, Equatable {
    var title = "Card"
    var cornerRadius = 24.0
    var opacity = 1.0
    var isEnabled = true
    var fill = "#F97316"
}

struct CardPreview: View {
    @StateObject private var dial = DialPanelState(
        name: "Card",
        initial: CardModel(),
        controls: [
            .text("title", keyPath: \.title),
            .slider("cornerRadius", keyPath: \.cornerRadius, range: 0...48, step: 1, unit: "pt"),
            .slider("opacity", keyPath: \.opacity, range: 0...1, step: 0.05),
            .toggle("isEnabled", keyPath: \.isEnabled),
            .color("fill", keyPath: \.fill)
        ]
    )

    var body: some View {
        RoundedRectangle(cornerRadius: dial.values.cornerRadius)
            .fill(dial.values.isEnabled ? Color.orange : Color.gray)
            .opacity(dial.values.opacity)
            .overlay {
                Text(dial.values.title)
                    .foregroundStyle(.white)
            }
            .padding(40)
    }
}
```

When the app or preview is running, the agent publishes active panels to the Mac inspector. Edits in the inspector update `dial.values` in the running app.

## Run The Inspector

From this package checkout:

```sh
swift run dialkit run
```

You can also run the inspector executable directly:

```sh
swift run dialkit-macos
```

Then launch the app or resume the Xcode Preview that starts `DialKitAgent`. The inspector listens locally and updates when the app connects.

Current transport:

- host: `127.0.0.1`
- port: `44777`
- debug agent reconnects automatically
- intended for iOS Simulator, Xcode Preview, and local macOS app tuning
- physical-device discovery is not implemented yet

## CLI Preflight

The helper CLI can validate that an Xcode target exists and print the debug-only setup:

```sh
swift run dialkit install --project MyApp.xcodeproj --target MyApp
```

Today this command does not mutate the Xcode project. The next step is automatic project patching for package linking, debug bootstrap code, and an optional inspector launch phase.

## Package Products

- `DialkitmacOS`: public tuning API, including `DialPanelState`, `DialControl`, presets, actions, colors, springs, and transitions
- `DialkitmacOSAgent`: debug-only agent that connects the running app to the Mac inspector
- `dialkit`: helper executable for `run` and `install`
- `dialkit-macos`: standalone Mac inspector executable

The package also exposes lower-level support products for internal integration and tests: `DialkitmacOSCore` and `DialkitmacOSProtocol`.

## Controls

Controls are defined with writable key paths into a `Codable & Equatable` model:

```swift
[
    .slider("cornerRadius", keyPath: \.cornerRadius, range: 0...48, step: 1),
    .toggle("isEnabled", keyPath: \.isEnabled),
    .text("title", keyPath: \.title),
    .color("fill", keyPath: \.fill),
    .select("style", keyPath: \.style, options: ["glass", "solid"]),
    .spring("spring", keyPath: \.spring),
    .transition("transition", keyPath: \.transition),
    .group("motion", children: [...]),
    .action("shuffle")
]
```

Supported controls:

- `slider`: numeric values backed by `Double`, `Float`, `CGFloat`, or `Int`
- `toggle`: `Bool`
- `text`: `String`
- `color`: hex color strings such as `#RGB`, `#RRGGBB`, or `#RRGGBBAA`
- `select`: `String` values with either `[String]` or `[DialOption]`
- `spring`: `DialSpring`
- `transition`: `DialTransition`
- `group`: nested controls
- `action`: callback-only controls routed through `onAction`

## Multiple Panels

Each `DialPanelState` registers automatically while it is alive. Keep panel state in `@StateObject` for SwiftUI views, or hold it from a longer-lived owner when tuning app-level values.

```swift
@StateObject private var cardDial = DialPanelState(
    name: "Card",
    initial: CardModel(),
    controls: CardModel.controls
)

@StateObject private var shadowDial = DialPanelState(
    name: "Shadow",
    initial: ShadowModel(),
    controls: ShadowModel.controls
)
```

If more than one panel is active, the Mac inspector lets you switch between panels.

## Actions

Action controls are useful when the inspector should trigger app logic that is not a direct key-path write.

```swift
let dial = DialPanelState(
    name: "Card",
    initial: CardModel(),
    controls: [
        .group(
            "actions",
            children: [
                .action("shuffle"),
                .action("resetLayout")
            ]
        )
    ],
    onAction: { path in
        switch path {
        case "actions.shuffle":
            shuffleCard()
        case "actions.resetLayout":
            resetLayout()
        default:
            break
        }
    }
)
```

Nested action paths are dot-separated, so `action("shuffle")` inside `group("actions")` arrives as `actions.shuffle`.

## Presets And Copy

Each panel supports in-memory presets:

- `savePreset(named:)`
- `loadPreset(id:)`
- `clearActivePreset()`
- `deletePreset(id:)`
- `copyInstructionText()`

When no preset is selected, edits update the base values. When a preset is active, edits update that preset.

## Requirements

- macOS 14 or later for local package builds, tests, and the inspector
- iOS 17 or later for iOS Simulator apps using the debug agent
- Swift 5.10 or later
- SwiftUI
- Tuned model types must conform to `Codable` and `Equatable`

## Current Limits

- The inspector is local-only.
- Physical-device discovery is not implemented yet.
- The install command prints setup instructions but does not patch Xcode projects yet.
- The agent should be debug-only; do not ship it in release builds.

## Credit

This Swift package is based on the original [DialKit repository](https://github.com/joshpuckett/dialkit) by [Josh Puckett](https://github.com/joshpuckett).

## License

MIT License. See [LICENSE](LICENSE).
