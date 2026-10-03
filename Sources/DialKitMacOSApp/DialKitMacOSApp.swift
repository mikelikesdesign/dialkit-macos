import SwiftUI
import DialkitmacOSProtocol
#if canImport(AppKit)
import AppKit
#endif

@main
struct DialKitMacOSApp: App {
    #if canImport(AppKit)
    @NSApplicationDelegateAdaptor(DialKitAppDelegate.self) private var appDelegate
    #endif
    @StateObject private var service = DialKitInspectorService()

    var body: some Scene {
        WindowGroup("Dialkit macOS") {
            InspectorView()
                .environmentObject(service)
                .frame(minWidth: 320, minHeight: 420)
                .background(DialTheme.panelBackground)
                .toolbarBackground(DialTheme.panelBackground, for: .windowToolbar)
                .toolbarBackground(.visible, for: .windowToolbar)
                .preferredColorScheme(.dark)
        }
        .defaultSize(width: 390, height: 720)
    }
}

#if canImport(AppKit)
private final class DialKitAppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Copies in Downloads and the build folder share a bundle identifier.
        // Reuse the oldest inspector instead of opening a second dead window.
        if let bundleID = Bundle.main.bundleIdentifier,
           let existing = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID)
            .filter({ $0.processIdentifier != ProcessInfo.processInfo.processIdentifier && !$0.isTerminated })
            .min(by: { $0.processIdentifier < $1.processIdentifier }),
           existing.processIdentifier < ProcessInfo.processInfo.processIdentifier {
            existing.activate(options: [.activateAllWindows])
            NSApp.terminate(nil)
            return
        }

        if let iconURL = Bundle.module.url(forResource: "AppIcon", withExtension: "icns"),
           let icon = NSImage(contentsOf: iconURL) {
            NSApp.applicationIconImage = icon
        }
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)

        DispatchQueue.main.async {
            NSApp.windows.first?.makeKeyAndOrderFront(nil)
        }
    }
}
#endif

private enum DialTheme {
    static let panelBackground = color(from: "#212121")
    static let border = Color.white.opacity(0.10)
    static let borderSoft = Color.white.opacity(0.06)
    static let surface = Color.white.opacity(0.05)
    static let surfaceActive = Color.white.opacity(0.11)
    static let textRoot = Color.white
    static let textSection = Color.white.opacity(0.70)
    static let textLabel = Color.white.opacity(0.70)
    static let textMuted = Color.white.opacity(0.40)
    static let shadow = Color.black.opacity(0.45)
}

private struct InspectorView: View {
    @EnvironmentObject private var service: DialKitInspectorService
    @State private var selectedPanelID: UUID?

    var body: some View {
        ZStack {
            DialTheme.panelBackground.ignoresSafeArea()

            if let snapshot = service.snapshot,
               let panel = selectedPanel(in: snapshot) {
                ScrollView(showsIndicators: false) {
                    StandalonePanelInspectorView(
                        snapshot: snapshot,
                        panel: panel,
                        selectedPanelID: $selectedPanelID
                    )
                    .padding(8)
                }
            } else {
                emptyState
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            connectionFooter
                .frame(maxWidth: .infinity)
                .padding(.top, 8)
                .background(DialTheme.panelBackground)
        }
        .onChange(of: service.snapshot?.panels.map(\.id) ?? []) { _, panelIDs in
            guard !panelIDs.isEmpty else {
                selectedPanelID = nil
                return
            }

            if let selectedPanelID, panelIDs.contains(selectedPanelID) {
                return
            }

            selectedPanelID = panelIDs.first
        }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "slider.horizontal.3")
                .font(.system(size: 28, weight: .semibold))
                .foregroundStyle(DialTheme.textLabel)
                .frame(width: 56, height: 56)
                .background(DialRowBackground(cornerRadius: 16))

            Text(service.snapshot == nil ? "No App Connected" : "No Panels Available")
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(DialTheme.textRoot)

            Text(service.snapshot == nil
                 ? "Run an app or Preview that starts DialKitAgent."
                 : "Open a view that contains a DialPanelState.")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(DialTheme.textMuted)
                .multilineTextAlignment(.center)

            Button {
                service.requestSnapshot()
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 13, weight: .semibold))
                    Text("Refresh")
                        .font(.system(size: 13, weight: .medium))
                }
                .foregroundStyle(DialTheme.textLabel)
                .frame(height: 36)
                .padding(.horizontal, 12)
                .background(DialRowBackground(cornerRadius: 8))
            }
            .buttonStyle(.plain)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(24)
    }

    private var connectionFooter: some View {
        VStack(spacing: 4) {
            Text(service.status)
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .foregroundStyle(DialTheme.textMuted)
                .lineLimit(2)
                .multilineTextAlignment(.center)

            if let lastLog = service.lastLog {
                Text(lastLog)
                    .font(.system(size: 11, weight: .regular, design: .monospaced))
                    .foregroundStyle(DialTheme.textMuted.opacity(0.8))
                    .lineLimit(3)
                    .multilineTextAlignment(.center)
            }
        }
        .textSelection(.enabled)
        .padding(.horizontal, 16)
        .padding(.bottom, 12)
    }

    private func selectedPanel(in snapshot: DialKitSessionSnapshot) -> DialKitPanelSnapshot? {
        if let selectedPanelID,
           let selected = snapshot.panels.first(where: { $0.id == selectedPanelID }) {
            return selected
        }

        return snapshot.panels.first
    }
}

private struct StandalonePanelInspectorView: View {
    let snapshot: DialKitSessionSnapshot
    let panel: DialKitPanelSnapshot
    @Binding var selectedPanelID: UUID?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            panelHeader
                .padding(.horizontal, 12)
                .padding(.top, 12)
                .padding(.bottom, 8)

            PanelControlsView(panel: panel)
                .id(panel.id)
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background {
            DialPanelBackground(cornerRadius: 16)
        }
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(DialTheme.border, lineWidth: 1)
        }
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .shadow(color: DialTheme.shadow, radius: 22, y: 8)
    }

    @ViewBuilder
    private var panelHeader: some View {
        if snapshot.panels.count > 1 {
            Menu {
                ForEach(snapshot.panels) { candidate in
                    Button(candidate.name) {
                        selectedPanelID = candidate.id
                    }
                }
            } label: {
                HStack(spacing: 8) {
                    Text(panel.name)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(DialTheme.textRoot)
                        .lineLimit(1)

                    Spacer(minLength: 0)

                    Image(systemName: "chevron.down")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(DialTheme.textLabel.opacity(0.8))
                }
                .frame(maxWidth: .infinity)
                .frame(height: 32)
                .padding(.horizontal, 10)
                .background(DialRowBackground(cornerRadius: 8))
            }
            .buttonStyle(.plain)
            .frame(maxWidth: .infinity)
        } else {
            HStack(spacing: 12) {
                Text(panel.name)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(DialTheme.textRoot)
                    .lineLimit(1)

                Spacer(minLength: 0)
            }
            .frame(height: 24)
        }
    }
}

private struct PanelControlsView: View {
    @EnvironmentObject private var service: DialKitInspectorService
    let panel: DialKitPanelSnapshot

    @State private var copiedState = false
    @State private var expandedGroups: [String: Bool] = [:]

    var body: some View {
        let accordionIDs = accordionIDs(in: panel.controls)

        VStack(alignment: .leading, spacing: 0) {
            toolbar
                .padding(.horizontal, 12)
                .padding(.bottom, 8)

            controlsContent
        }
        .onAppear {
            expandedGroups = expandedGroups.filter { accordionIDs.contains($0.key) }
        }
        .onChange(of: accordionIDs) { _, newValue in
            expandedGroups = expandedGroups.filter { newValue.contains($0.key) }
        }
    }

    private var controlsContent: some View {
        VStack(spacing: 6) {
            controlList(panel.controls)
        }
        .padding(.horizontal, 12)
        .padding(.bottom, 12)
    }

    private func controlList(_ controls: [DialKitControlSnapshot]) -> some View {
        ForEach(Array(controls.enumerated()), id: \.element.id) { index, control in
            ControlInspectorView(
                panelID: panel.id,
                control: control,
                dividerVisibility: sectionDividerVisibility(at: index, in: controls),
                expansionBinding: expansionBinding
            )
        }
    }

    private var toolbar: some View {
        HStack(spacing: 6) {
            Button {
                // Resolve the automatic name in the app so rapid saves cannot
                // reuse a name from a snapshot that is still in flight.
                service.savePreset(panelID: panel.id, name: "")
            } label: {
                Image(systemName: "slider.horizontal.below.square.and.square.filled")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(DialTheme.textLabel)
                    .frame(width: 36, height: 36)
                    .background(DialRowBackground(cornerRadius: 8))
            }
            .buttonStyle(.plain)
            .help("Save \(panel.nextPresetName)")

            Menu {
                Picker("Preset", selection: presetSelection) {
                    Text("Version 1")
                        .tag(Optional<UUID>.none)

                    ForEach(panel.presets) { preset in
                        Text(preset.name)
                            .tag(Optional(preset.id))
                    }
                }

                if let activePresetID = panel.activePresetID {
                    Divider()
                    Button("Delete Current Preset", role: .destructive) {
                        service.deletePreset(panelID: panel.id, presetID: activePresetID)
                    }
                }
            } label: {
                HStack(spacing: 8) {
                    Text(activePresetName)
                        .lineLimit(1)

                    Spacer(minLength: 0)

                    Image(systemName: "chevron.down")
                        .font(.system(size: 11, weight: .semibold))
                        .opacity(0.6)
                }
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(DialTheme.textLabel)
                .frame(height: 36)
                .padding(.horizontal, 12)
                .background(DialRowBackground(cornerRadius: 8))
            }
            .buttonStyle(.plain)

            Button {
                copyTextToPasteboard(copyInstructionText(for: panel))
                copiedState = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.4) {
                    copiedState = false
                }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: copiedState ? "checkmark" : "doc.on.doc")
                        .font(.system(size: 13, weight: .semibold))
                    Text("Copy")
                        .font(.system(size: 13, weight: .medium))
                }
                .foregroundStyle(DialTheme.textLabel)
                .frame(height: 36)
                .padding(.horizontal, 12)
                .background(DialRowBackground(cornerRadius: 8))
            }
            .buttonStyle(.plain)
        }
    }

    private var presetSelection: Binding<UUID?> {
        Binding {
            panel.activePresetID
        } set: { selection in
            if let selection {
                service.loadPreset(panelID: panel.id, presetID: selection)
            } else {
                service.clearActivePreset(panelID: panel.id)
            }
        }
    }

    private var activePresetName: String {
        panel.presets.first(where: { $0.id == panel.activePresetID })?.name ?? "Version 1"
    }

    private func expansionBinding(id: String, defaultOpen: Bool) -> Binding<Bool> {
        Binding {
            expandedGroups[id] ?? defaultOpen
        } set: { newValue in
            expandedGroups[id] = newValue
        }
    }

    private func accordionIDs(in controls: [DialKitControlSnapshot]) -> Set<String> {
        controls.reduce(into: Set<String>()) { ids, control in
            switch control.kind {
            case .spring, .transition:
                ids.insert(control.id)
            case let .group(_, children):
                ids.insert(control.id)
                ids.formUnion(accordionIDs(in: children))
            default:
                break
            }
        }
    }
}

private struct DialSectionDividerVisibility: Equatable {
    let showsTopDivider: Bool
    let showsBottomDivider: Bool
}

private func controlUsesSectionDivider(_ control: DialKitControlSnapshot) -> Bool {
    switch control.kind {
    case .spring, .transition, .group:
        return true
    default:
        return false
    }
}

private func sectionDividerVisibility(at index: Int, in controls: [DialKitControlSnapshot]) -> DialSectionDividerVisibility {
    guard controls.indices.contains(index), controlUsesSectionDivider(controls[index]) else {
        return DialSectionDividerVisibility(showsTopDivider: false, showsBottomDivider: false)
    }

    return DialSectionDividerVisibility(
        showsTopDivider: controls[..<index].contains(where: controlUsesSectionDivider),
        showsBottomDivider: false
    )
}

private struct ControlInspectorView: View {
    @EnvironmentObject private var service: DialKitInspectorService
    let panelID: UUID
    let control: DialKitControlSnapshot
    let dividerVisibility: DialSectionDividerVisibility
    let expansionBinding: (String, Bool) -> Binding<Bool>

    var body: some View {
        switch control.kind {
        case let .slider(value, lowerBound, upperBound, step, unit):
            DialSliderRow(
                title: control.label,
                value: value,
                range: lowerBound...upperBound,
                step: step,
                unit: unit
            ) {
                service.setControlValue(panelID: panelID, path: control.path, value: .number($0))
            }
        case let .toggle(value):
            DialToggleRow(title: control.label, isOn: value) {
                service.setControlValue(panelID: panelID, path: control.path, value: .bool($0))
            }
        case let .text(value, placeholder):
            DialTextRow(title: control.label, value: value, placeholder: placeholder ?? "") {
                service.setControlValue(panelID: panelID, path: control.path, value: .string($0))
            }
        case let .color(value):
            DialColorRow(title: control.label, hexValue: value) {
                service.setControlValue(panelID: panelID, path: control.path, value: .string($0))
            }
        case let .select(value, options):
            DialSelectRow(title: control.label, options: options, selection: value) {
                service.setControlValue(panelID: panelID, path: control.path, value: .string($0))
            }
        case let .spring(value):
            DialSpringControl(
                title: control.label,
                value: value,
                isExpanded: expansionBinding(control.id, true),
                dividerVisibility: dividerVisibility,
                onComponentChange: {
                    service.setMotionComponent(panelID: panelID, path: control.path, component: $0)
                }
            ) {
                service.setControlValue(panelID: panelID, path: control.path, value: .spring($0))
            }
        case let .transition(value):
            DialTransitionControl(
                title: control.label,
                value: value,
                isExpanded: expansionBinding(control.id, true),
                dividerVisibility: dividerVisibility,
                onComponentChange: {
                    service.setMotionComponent(panelID: panelID, path: control.path, component: $0)
                }
            ) {
                service.setControlValue(panelID: panelID, path: control.path, value: .transition($0))
            }
        case let .group(collapsed, controls):
            DialFolderSection(
                title: control.label,
                isExpanded: expansionBinding(control.id, !collapsed),
                showsTopDivider: dividerVisibility.showsTopDivider,
                showsBottomDivider: dividerVisibility.showsBottomDivider
            ) {
                ForEach(Array(controls.enumerated()), id: \.element.id) { index, child in
                    ControlInspectorView(
                        panelID: panelID,
                        control: child,
                        dividerVisibility: sectionDividerVisibility(at: index, in: controls),
                        expansionBinding: expansionBinding
                    )
                }
            }
        case .action:
            DialActionButton(title: control.label) {
                service.triggerAction(panelID: panelID, path: control.path)
            }
        }
    }
}

private struct DialRowBackground: View {
    let cornerRadius: CGFloat

    var body: some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(DialTheme.surface)
    }
}

private struct DialPanelBackground: View {
    let cornerRadius: CGFloat

    var body: some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(DialTheme.panelBackground.opacity(0.94))
            .background {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(.ultraThinMaterial.opacity(0.45))
            }
    }
}

private let dialFolderIconAnimation = Animation.spring(duration: 0.35, bounce: 0.15)
private let dialFolderContentAnimation = Animation.spring(duration: 0.35, bounce: 0.1)

private struct DialFolderSection<Content: View>: View {
    let title: String
    @Binding var isExpanded: Bool
    let showsTopDivider: Bool
    let showsBottomDivider: Bool
    let content: Content


    init(
        title: String,
        isExpanded: Binding<Bool>,
        showsTopDivider: Bool = false,
        showsBottomDivider: Bool = false,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self._isExpanded = isExpanded
        self.showsTopDivider = showsTopDivider
        self.showsBottomDivider = showsBottomDivider
        self.content = content()
    }

    var body: some View {
        VStack(spacing: 0) {
            Button {
                withAnimation(dialFolderContentAnimation) {
                    isExpanded.toggle()
                }
            } label: {
                HStack(spacing: 8) {
                    Text(title)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(DialTheme.textSection)

                    Spacer(minLength: 0)

                    Image(systemName: "chevron.down")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(DialTheme.textLabel.opacity(0.8))
                        .rotationEffect(.degrees(isExpanded ? 0 : 180))
                        .animation(dialFolderIconAnimation, value: isExpanded)
                }
                .frame(height: 36)
            }
            .buttonStyle(.plain)

            if isExpanded {
                VStack(spacing: 6) {
                    content
                }
                .padding(.bottom, 10)
                .transition(.opacity)
            }
        }
        .overlay(alignment: .top) {
            if showsTopDivider {
                Rectangle()
                    .fill(DialTheme.borderSoft)
                    .frame(height: 1)
            }
        }
        .overlay(alignment: .bottom) {
            if showsBottomDivider {
                Rectangle()
                    .fill(DialTheme.borderSoft)
                    .frame(height: 1)
            }
        }
        .padding(.vertical, 4)
    }
}

private struct DialSegmentOption<Value: Hashable>: Identifiable {
    let value: Value
    let label: String

    var id: String { label }
}

private let dialSegmentedControlAnimation = Animation.timingCurve(0.25, 1, 0.5, 1, duration: 0.2)

private struct DialSegmentedControl<Value: Hashable>: View {
    let options: [DialSegmentOption<Value>]
    let selection: Value
    let onSelect: (Value) -> Void

    var body: some View {
        GeometryReader { proxy in
            let inset: CGFloat = 2
            let segmentWidth = max((proxy.size.width - inset * 2) / CGFloat(max(options.count, 1)), 0)
            let segmentHeight = max(proxy.size.height - inset * 2, 0)
            let selectedIndex = CGFloat(options.firstIndex(where: { $0.value == selection }) ?? 0)

            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.clear)

                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(DialTheme.surfaceActive)
                    .frame(width: segmentWidth, height: segmentHeight)
                    .offset(x: selectedIndex * segmentWidth + inset)
                    .animation(dialSegmentedControlAnimation, value: selection)

                HStack(spacing: 0) {
                    ForEach(options) { option in
                        Text(option.label)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(selection == option.value ? Color.white.opacity(0.82) : DialTheme.textLabel)
                            .frame(width: segmentWidth, height: segmentHeight)
                            .contentShape(Rectangle())
                            .onTapGesture {
                                guard selection != option.value else {
                                    return
                                }

                                withAnimation(.spring(response: 0.22, dampingFraction: 0.84)) {
                                    onSelect(option.value)
                                }
                            }
                            .accessibilityAddTraits(selection == option.value ? .isSelected : [])
                            .accessibilityLabel(option.label)
                            .accessibilityAction {
                                onSelect(option.value)
                            }
                    }
                }
                .padding(inset)
            }
        }
        .frame(width: CGFloat(max(options.count, 2)) * 56, height: 32)
        .background(DialRowBackground(cornerRadius: 8))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

private struct DialSegmentedRow<Value: Hashable>: View {
    let title: String
    let options: [DialSegmentOption<Value>]
    let selection: Value
    let onSelect: (Value) -> Void

    var body: some View {
        HStack(spacing: 12) {
            Text(title)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(DialTheme.textLabel)

            Spacer(minLength: 8)

            DialSegmentedControl(options: options, selection: selection, onSelect: onSelect)
        }
        .frame(height: 36)
        .padding(.leading, 12)
        .padding(.trailing, 10)
        .background(DialRowBackground(cornerRadius: 8))
    }
}

private struct DialToggleRow: View {
    let title: String
    let isOn: Bool
    let onChange: (Bool) -> Void

    var body: some View {
        DialSegmentedRow(
            title: title,
            options: [
                .init(value: false, label: "Off"),
                .init(value: true, label: "On")
            ],
            selection: isOn,
            onSelect: onChange
        )
    }
}

private struct DialSelectRow: View {
    let title: String
    let options: [DialKitOptionSnapshot]
    let selection: String
    let onChange: (String) -> Void

    private var selectedLabel: String {
        options.first(where: { $0.value == selection })?.label ?? selection
    }

    var body: some View {
        Menu {
            ForEach(options) { option in
                Button(option.label) {
                    onChange(option.value)
                }
            }
        } label: {
            HStack(spacing: 8) {
                Text(title)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(DialTheme.textLabel)

                Spacer(minLength: 10)

                Text(selectedLabel)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(DialTheme.textLabel)
                    .lineLimit(1)

                Image(systemName: "chevron.down")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(DialTheme.textLabel.opacity(0.7))
            }
            .frame(height: 36)
            .padding(.horizontal, 12)
            .background(DialRowBackground(cornerRadius: 8))
        }
        .buttonStyle(.plain)
    }
}

private struct DialTextRow: View {
    let title: String
    let value: String
    let placeholder: String
    let onChange: (String) -> Void

    // Edit a local draft so each keystroke does not wait for the app's snapshot
    // round-trip before appearing. Changes are sent while typing, but the field
    // only re-syncs from the remote value when it is not focused.
    @State private var draft: String
    @FocusState private var isFocused: Bool

    init(title: String, value: String, placeholder: String, onChange: @escaping (String) -> Void) {
        self.title = title
        self.value = value
        self.placeholder = placeholder
        self.onChange = onChange
        self._draft = State(initialValue: value)
    }

    var body: some View {
        HStack(spacing: 12) {
            Text(title)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(DialTheme.textLabel)

            TextField(placeholder, text: $draft)
                .textFieldStyle(.plain)
                .multilineTextAlignment(.trailing)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(DialTheme.textLabel)
                .tint(.white)
                .focused($isFocused)
                .onChange(of: draft) { _, newValue in
                    guard isFocused, newValue != value else { return }
                    onChange(newValue)
                }
                .onChange(of: value) { _, newValue in
                    guard !isFocused else { return }
                    draft = newValue
                }
                .onChange(of: isFocused) { _, focused in
                    if focused {
                        draft = value
                    } else if draft != value {
                        onChange(draft)
                    }
                }
        }
        .frame(height: 36)
        .padding(.horizontal, 12)
        .background(DialRowBackground(cornerRadius: 8))
    }
}

private struct DialColorRow: View {
    let title: String
    let hexValue: String
    let onChange: (String) -> Void

    @State private var draft: String
    @FocusState private var isFocused: Bool

    init(title: String, hexValue: String, onChange: @escaping (String) -> Void) {
        self.title = title
        self.hexValue = hexValue
        self.onChange = onChange
        self._draft = State(initialValue: hexValue.uppercased())
    }

    var body: some View {
        HStack(spacing: 12) {
            Text(title)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(DialTheme.textLabel)

            Spacer(minLength: 8)

            TextField("#FFFFFF", text: $draft)
                .textFieldStyle(.plain)
                .multilineTextAlignment(.trailing)
                .font(.system(size: 13, weight: .medium, design: .monospaced))
                .foregroundStyle(DialTheme.textLabel)
                .frame(width: 96)
                .focused($isFocused)
                .onSubmit(commitDraft)
                .onChange(of: isFocused) { _, focused in
                    if !focused { commitDraft() }
                }
                .onChange(of: hexValue) { _, newValue in
                    guard !isFocused else { return }
                    draft = newValue.uppercased()
                }

            DialColorSwatchPicker(hexValue: hexValue) { hex in
                draft = hex.uppercased()
                onChange(hex)
            }
        }
        .frame(height: 36)
        .padding(.horizontal, 12)
        .background(DialRowBackground(cornerRadius: 8))
    }

    private func commitDraft() {
        let next = InspectorDraft.color(draft, fallback: hexValue)
        draft = next
        if next != hexValue.uppercased() { onChange(next) }
    }

}

private struct DialColorSwatchPicker: View {
    let hexValue: String
    let onChange: (String) -> Void

    private var displayColor: Color {
        color(from: hexValue)
    }

    var body: some View {
        Button {
            #if canImport(AppKit)
            DialNativeColorPanel.shared.open(hexValue: hexValue, onChange: onChange)
            #endif
        } label: {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(displayColor)
                .overlay {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .stroke(Color.white.opacity(0.18), lineWidth: 1)
                }
        }
        .buttonStyle(.plain)
        .frame(width: 24, height: 24)
        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        .accessibilityLabel("Choose color")
    }
}

#if canImport(AppKit)
private final class DialNativeColorPanel: NSObject {
    static let shared = DialNativeColorPanel()

    private var onChange: ((String) -> Void)?
    private var colorChangeObserver: NSObjectProtocol?

    deinit {
        if let colorChangeObserver {
            NotificationCenter.default.removeObserver(colorChangeObserver)
        }
    }

    func open(hexValue: String, onChange: @escaping (String) -> Void) {
        self.onChange = onChange

        let panel = NSColorPanel.shared
        panel.showsAlpha = true
        panel.isContinuous = true
        panel.color = nsColor(from: hexValue)

        if let colorChangeObserver {
            NotificationCenter.default.removeObserver(colorChangeObserver)
        }

        colorChangeObserver = NotificationCenter.default.addObserver(
            forName: NSColorPanel.colorDidChangeNotification,
            object: panel,
            queue: .main
        ) { [weak self] notification in
            guard let panel = notification.object as? NSColorPanel,
                  let hex = hexString(from: panel.color) else {
                return
            }

            self?.onChange?(hex)
        }

        panel.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}
#endif

private struct DialSliderRow: View {
    let title: String
    let value: Double
    let range: ClosedRange<Double>
    let step: Double
    let unit: String?
    let onChange: (Double) -> Void

    @State private var interaction = DialSliderEditingState()
    @State private var draftValue = ""
    @State private var isValueEditing = false

    private var displayedValue: Double { interaction.displayedValue(remote: value) }

    private var progress: CGFloat {
        guard range.upperBound > range.lowerBound else { return 0 }
        return CGFloat((displayedValue - range.lowerBound) / (range.upperBound - range.lowerBound))
    }

    var body: some View {
        GeometryReader { proxy in
            let width = max(proxy.size.width, 1)

            ZStack(alignment: .leading) {
                DialRowBackground(cornerRadius: 8)

                HStack(spacing: 0) {
                    ForEach(0..<11, id: \.self) { _ in
                        Capsule()
                            .fill(Color.white.opacity(interaction.isDragging ? 0.15 : 0))
                            .frame(width: 1, height: 8)
                            .frame(maxWidth: .infinity)
                    }
                }
                .padding(.horizontal, 8)

                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.white.opacity(interaction.isDragging ? 0.14 : 0.10))
                    .frame(width: width * max(0, min(progress, 1)))

                RoundedRectangle(cornerRadius: 99, style: .continuous)
                    .fill(Color.white.opacity(0.8))
                    .frame(width: 3, height: 20)
                    .offset(x: max(width * max(0, min(progress, 1)) - 2, 6))

                Color.clear
                    .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .allowsHitTesting(!isValueEditing)
                    .gesture(sliderDragGesture(width: width))

                HStack(spacing: 12) {
                    Text(title)
                        .allowsHitTesting(false)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(DialTheme.textLabel)

                    Spacer(minLength: 0)

                    valueEditor
                }
                .padding(.horizontal, 10)
            }
        }
        .frame(height: 36)
        .onAppear {
            draftValue = formatted(displayedValue, step: step, unit: nil)
        }
        .onChange(of: value) { _, newValue in
            interaction.receive(newValue)
            guard !isValueEditing else {
                return
            }

            draftValue = formatted(displayedValue, step: step, unit: nil)
        }
        .onChange(of: range) { _, _ in resetForConfigurationChange() }
        .onChange(of: step) { _, _ in resetForConfigurationChange() }
    }

    @ViewBuilder
    private var valueEditor: some View {
        if isValueEditing {
            HStack(spacing: 2) {
                DialInlineNumberTextField(
                    text: $draftValue,
                    onCommit: {
                        commitDraftValue()
                        isValueEditing = false
                    },
                    onBlur: {
                        commitDraftValue()
                        isValueEditing = false
                    },
                    onCancel: {
                        draftValue = formatted(displayedValue, step: step, unit: nil)
                        isValueEditing = false
                    }
                )
                    .frame(width: valueEditorWidth)
                    .background {
                        RoundedRectangle(cornerRadius: 5, style: .continuous)
                            .fill(Color.white.opacity(0.10))
                            .padding(.horizontal, -4)
                            .padding(.vertical, -2)
                    }

                if let unit {
                    Text(unit)
                        .font(.system(size: 13, weight: .medium, design: .monospaced))
                        .foregroundStyle(Color.white)
                }
            }
        } else {
            Text(formatted(displayedValue, step: step, unit: unit))
                .font(.system(size: 13, weight: .medium, design: .monospaced))
                .foregroundStyle(interaction.isDragging ? Color.white : DialTheme.textLabel)
                .frame(minWidth: valueEditorWidth, alignment: .trailing)
                .contentShape(Rectangle())
                .onTapGesture {
                    draftValue = formatted(displayedValue, step: step, unit: nil)
                    isValueEditing = true
                }
        }
    }

    private var valueEditorWidth: CGFloat {
        let longestCount = [
            formatted(range.lowerBound, step: step, unit: nil).count,
            formatted(range.upperBound, step: step, unit: nil).count,
            formatted(displayedValue, step: step, unit: nil).count,
            draftValue.count
        ].max() ?? 4

        return max(CGFloat(longestCount) * 9 + 18, 54)
    }

    private func sliderDragGesture(width: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { gesture in
                interaction.begin(remote: value)
                updateValue(translation: gesture.translation.width, width: width)
            }
            .onEnded { gesture in
                updateValue(translation: gesture.translation.width, width: width)
                interaction.end(remote: value)
            }
    }

    private func updateValue(translation: CGFloat, width: CGFloat) {
        if let next = interaction.update(translation: Double(translation), width: Double(width), range: range, step: step) {
            onChange(next)
        }
    }

    private func commitDraftValue() {
        let normalized = draftValue
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: unit ?? "", with: "")

        guard let rawValue = DialNumber.parse(normalized) else {
            draftValue = formatted(displayedValue, step: step, unit: nil)
            return
        }

        let nextValue = snappedValue(rawValue)
        draftValue = formatted(nextValue, step: step, unit: nil)
        if interaction.commit(nextValue, remote: value, step: step) {
            onChange(nextValue)
        }
    }

    private func snappedValue(_ rawValue: Double) -> Double {
        DialNumber.round(rawValue, step: step, within: range)
    }

    private func resetForConfigurationChange() {
        interaction.resetForConfigurationChange()
        draftValue = formatted(value, step: step, unit: nil)
        isValueEditing = false
    }

}

#if canImport(AppKit)
struct DialInlineNumberTextField: NSViewRepresentable {
    @Binding var text: String
    let onCommit: () -> Void
    let onBlur: () -> Void
    let onCancel: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeNSView(context: Context) -> NSTextField {
        let textField = NSTextField()
        textField.delegate = context.coordinator
        textField.isBordered = false
        textField.drawsBackground = false
        textField.focusRingType = .none
        textField.alignment = .right
        textField.usesSingleLineMode = true
        textField.lineBreakMode = .byClipping
        textField.font = .monospacedSystemFont(ofSize: 13, weight: .medium)
        textField.textColor = .white
        textField.stringValue = text
        textField.cell?.isScrollable = true
        context.coordinator.installClickAwayMonitor(for: textField)
        return textField
    }

    func updateNSView(_ textField: NSTextField, context: Context) {
        context.coordinator.parent = self
        context.coordinator.installClickAwayMonitor(for: textField)

        if textField.stringValue != text {
            textField.stringValue = text
        }

        guard !context.coordinator.didRequestFocus else { return }
        context.coordinator.didRequestFocus = true
        DispatchQueue.main.async {
            guard !context.coordinator.isFinishing, let window = textField.window,
                  window.firstResponder !== textField.currentEditor() else {
                return
            }

            window.makeFirstResponder(textField)
            textField.currentEditor()?.selectAll(nil)
        }
    }

    static func dismantleNSView(_ nsView: NSTextField, coordinator: Coordinator) {
        coordinator.removeClickAwayMonitor()
    }

    final class Coordinator: NSObject, NSTextFieldDelegate {
        private enum FinishAction { case commit, blur, cancel }
        var parent: DialInlineNumberTextField
        private var clickAwayMonitor: Any?
        fileprivate var isFinishing = false
        fileprivate var didRequestFocus = false

        init(parent: DialInlineNumberTextField) {
            self.parent = parent
        }

        func installClickAwayMonitor(for textField: NSTextField) {
            guard clickAwayMonitor == nil else {
                return
            }

            clickAwayMonitor = NSEvent.addLocalMonitorForEvents(
                matching: [.leftMouseDown, .rightMouseDown]
            ) { [weak self, weak textField] event in
                guard let self, let textField else {
                    return event
                }

                guard event.window === textField.window else {
                    self.finishEditing(text: textField.stringValue, action: .blur)
                    return event
                }

                let point = textField.convert(event.locationInWindow, from: nil)
                guard !textField.bounds.insetBy(dx: -6, dy: -6).contains(point) else {
                    return event
                }

                self.finishEditing(text: textField.stringValue, action: .blur)
                textField.window?.makeFirstResponder(nil)
                return event
            }
        }

        func removeClickAwayMonitor() {
            if let clickAwayMonitor {
                NSEvent.removeMonitor(clickAwayMonitor)
                self.clickAwayMonitor = nil
            }
        }

        func controlTextDidChange(_ notification: Notification) {
            guard let textField = notification.object as? NSTextField else {
                return
            }

            parent.text = textField.stringValue
        }

        func controlTextDidEndEditing(_ notification: Notification) {
            guard let textField = notification.object as? NSTextField else {
                return
            }

            finishEditing(text: textField.stringValue, action: .blur)
        }

        func control(
            _ control: NSControl,
            textView: NSTextView,
            doCommandBy commandSelector: Selector
        ) -> Bool {
            switch commandSelector {
            case #selector(NSResponder.insertNewline(_:)):
                finishEditing(text: textView.string, action: .commit)
                return true
            case #selector(NSResponder.cancelOperation(_:)):
                finishEditing(text: textView.string, action: .cancel)
                return true
            default:
                return false
            }
        }

        private func finishEditing(text: String, action: FinishAction) {
            guard !isFinishing else {
                return
            }

            isFinishing = true
            switch action {
            case .commit:
                parent.text = text
                parent.onCommit()
            case .blur:
                parent.text = text
                parent.onBlur()
            case .cancel:
                parent.onCancel()
            }

            removeClickAwayMonitor()
        }
    }
}
#endif

private struct DialActionButton: View {
    let title: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: "bolt.fill")
                    .font(.system(size: 13, weight: .semibold))
                Text(title)
                    .font(.system(size: 13, weight: .medium))
                Spacer(minLength: 0)
            }
            .foregroundStyle(DialTheme.textLabel)
            .frame(height: 36)
            .padding(.horizontal, 12)
            .background(DialRowBackground(cornerRadius: 8))
        }
        .buttonStyle(.plain)
    }
}

private struct DialSpringControl: View {
    let title: String
    let value: DialKitSpringValue
    @Binding var isExpanded: Bool
    let dividerVisibility: DialSectionDividerVisibility
    let onComponentChange: (DialKitMotionComponent) -> Void
    let onChange: (DialKitSpringValue) -> Void

    var body: some View {
        DialFolderSection(
            title: title,
            isExpanded: $isExpanded,
            showsTopDivider: dividerVisibility.showsTopDivider,
            showsBottomDivider: dividerVisibility.showsBottomDivider
        ) {
            SpringVisualization(spring: value)
                .frame(height: 140)

            DialSegmentedRow(
                title: "Type",
                options: SpringMode.allCases.map { .init(value: $0, label: $0.label) },
                selection: value.mode
            ) { mode in
                onChange(value.switching(to: mode))
            }

            switch value {
            case let .time(duration, bounce):
                DialSliderRow(title: "Duration", value: duration, range: 0.1...1, step: 0.05, unit: "s") {
                    onComponentChange(.duration($0))
                }
                DialSliderRow(title: "Bounce", value: bounce, range: 0...1, step: 0.05, unit: nil) {
                    onComponentChange(.bounce($0))
                }
            case let .physics(stiffness, damping, mass):
                DialSliderRow(title: "Stiffness", value: stiffness, range: InspectorMotionParameters.stiffnessRange, step: InspectorMotionParameters.stiffnessStep, unit: nil) {
                    onComponentChange(.stiffness($0))
                }
                DialSliderRow(title: "Damping", value: damping, range: 1...100, step: 1, unit: nil) {
                    onComponentChange(.damping($0))
                }
                DialSliderRow(title: "Mass", value: mass, range: 0.1...10, step: 0.1, unit: nil) {
                    onComponentChange(.mass($0))
                }
            }
        }
    }
}

private struct DialTransitionControl: View {
    let title: String
    let value: DialKitTransitionValue
    @Binding var isExpanded: Bool
    let dividerVisibility: DialSectionDividerVisibility
    let onComponentChange: (DialKitMotionComponent) -> Void
    let onChange: (DialKitTransitionValue) -> Void

    var body: some View {
        DialFolderSection(
            title: title,
            isExpanded: $isExpanded,
            showsTopDivider: dividerVisibility.showsTopDivider,
            showsBottomDivider: dividerVisibility.showsBottomDivider
        ) {
            switch value {
            case let .easing(_, bezier):
                EasingVisualization(bezier: bezier)
                    .frame(height: 140)
            case let .spring(spring):
                SpringVisualization(spring: spring)
                    .frame(height: 140)
            }

            DialSegmentedRow(
                title: "Type",
                options: TransitionMode.allCases.map { .init(value: $0, label: $0.label) },
                selection: value.mode
            ) { mode in
                onChange(value.switching(to: mode))
            }

            switch value {
            case let .easing(duration, bezier):
                DialSliderRow(title: "x1", value: bezier.x1, range: 0...1, step: 0.01, unit: nil) {
                    onComponentChange(.x1($0))
                }
                DialSliderRow(title: "y1", value: bezier.y1, range: -1...2, step: 0.01, unit: nil) {
                    onComponentChange(.y1($0))
                }
                DialSliderRow(title: "x2", value: bezier.x2, range: 0...1, step: 0.01, unit: nil) {
                    onComponentChange(.x2($0))
                }
                DialSliderRow(title: "y2", value: bezier.y2, range: -1...2, step: 0.01, unit: nil) {
                    onComponentChange(.y2($0))
                }
                DialSliderRow(title: "Duration", value: duration, range: 0.1...2, step: 0.05, unit: "s") {
                    onComponentChange(.duration($0))
                }
                DialBezierRow(bezier: bezier) {
                    onComponentChange(.bezier($0))
                }
            case let .spring(spring):
                switch spring {
                case let .time(duration, bounce):
                    DialSliderRow(title: "Duration", value: duration, range: 0.1...1, step: 0.05, unit: "s") {
                        onComponentChange(.duration($0))
                    }
                    DialSliderRow(title: "Bounce", value: bounce, range: 0...1, step: 0.05, unit: nil) {
                        onComponentChange(.bounce($0))
                    }
                case let .physics(stiffness, damping, mass):
                    DialSliderRow(title: "Stiffness", value: stiffness, range: InspectorMotionParameters.stiffnessRange, step: InspectorMotionParameters.stiffnessStep, unit: nil) {
                        onComponentChange(.stiffness($0))
                    }
                    DialSliderRow(title: "Damping", value: damping, range: 1...100, step: 1, unit: nil) {
                        onComponentChange(.damping($0))
                    }
                    DialSliderRow(title: "Mass", value: mass, range: 0.1...10, step: 0.1, unit: nil) {
                        onComponentChange(.mass($0))
                    }
                }
            }
        }
    }
}

private struct DialBezierRow: View {
    let bezier: DialKitBezierValue
    let onChange: (DialKitBezierValue) -> Void

    @State private var draft: String
    @FocusState private var isFocused: Bool

    init(bezier: DialKitBezierValue, onChange: @escaping (DialKitBezierValue) -> Void) {
        self.bezier = bezier
        self.onChange = onChange
        self._draft = State(initialValue: Self.format(bezier))
    }

    var body: some View {
        HStack(spacing: 12) {
            Text("Bezier")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(DialTheme.textLabel)

            TextField("0.25, 0.1, 0.25, 1", text: $draft)
                .textFieldStyle(.plain)
                .font(.system(size: 13, weight: .medium, design: .monospaced))
                .multilineTextAlignment(.trailing)
                .foregroundStyle(DialTheme.textLabel)
                .focused($isFocused)
                .onSubmit(commit)
                .onChange(of: isFocused) { _, focused in
                    if !focused { commit() }
                }
                .onChange(of: Self.format(bezier)) { _, newValue in
                    guard !isFocused else { return }
                    draft = newValue
                }
        }
        .frame(height: 36)
        .padding(.horizontal, 12)
        .background(DialRowBackground(cornerRadius: 8))
    }

    private func commit() {
        let next = InspectorDraft.bezier(draft, fallback: bezier)
        draft = Self.format(next)
        if next != bezier { onChange(next) }
    }

    private static func format(_ bezier: DialKitBezierValue) -> String {
        [bezier.x1, bezier.y1, bezier.x2, bezier.y2]
            .map { formatted($0, step: 0.01, unit: nil) }
            .joined(separator: ", ")
    }
}

private struct SpringVisualization: View {
    let spring: DialKitSpringValue

    var body: some View {
        Canvas { context, size in
            let width = size.width
            let height = size.height
            let points = generateCurve(in: width, height: height)

            drawGrid(in: size, context: &context)

            var midpoint = Path()
            midpoint.move(to: CGPoint(x: 0, y: height / 2))
            midpoint.addLine(to: CGPoint(x: width, y: height / 2))
            context.stroke(midpoint, with: .color(Color.white.opacity(0.15)), style: StrokeStyle(lineWidth: 1, dash: [4, 4]))

            var curve = Path()
            curve.addLines(points)
            context.stroke(curve, with: .color(Color.white.opacity(0.62)), lineWidth: 2)
        }
        .background(DialRowBackground(cornerRadius: 8))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private func generateCurve(in width: CGFloat, height: CGFloat) -> [CGPoint] {
        let physics = spring.resolvedPhysics
        let steps = 100
        let duration = 2.0
        let rawValues = (0...steps).map { index in
            let time = Double(index) * duration / Double(steps)
            return (time: time, value: SpringResponse.position(
                at: time, stiffness: physics.stiffness,
                damping: physics.damping, mass: physics.mass
            ))
        }

        let values = rawValues.map(\.value)
        let minValue = values.min() ?? 0
        let maxValue = values.max() ?? 1
        let valueRange = max(maxValue - minValue, 0.001)

        return rawValues.map { point in
            let x = CGFloat(point.time / duration) * width
            let normalized = (point.value - minValue) / valueRange
            let y = height - CGFloat(normalized) * height * 0.6 - height * 0.2
            return CGPoint(x: x, y: y)
        }
    }
}

private struct EasingVisualization: View {
    let bezier: DialKitBezierValue

    var body: some View {
        Canvas { context, size in
            drawGrid(in: size, context: &context)

            var axis = Path()
            axis.move(to: .init(x: 0, y: size.height))
            axis.addLine(to: .init(x: size.width, y: 0))
            context.stroke(axis, with: .color(Color.white.opacity(0.15)), style: StrokeStyle(lineWidth: 1, dash: [4, 4]))

            var curve = Path()
            curve.addLines(easingPoints(in: size))
            context.stroke(curve, with: .color(Color.white.opacity(0.62)), lineWidth: 2)
        }
        .background(DialRowBackground(cornerRadius: 8))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private func easingPoints(in size: CGSize) -> [CGPoint] {
        (0...80).map { index in
            let t = CGFloat(index) / 80
            let point = cubicPoint(for: t)
            return CGPoint(x: point.x * size.width, y: size.height - point.y * size.height)
        }
    }

    private func cubicPoint(for t: CGFloat) -> CGPoint {
        CGPoint(
            x: cubic(t, 0, CGFloat(bezier.x1), CGFloat(bezier.x2), 1),
            y: cubic(t, 0, CGFloat(bezier.y1), CGFloat(bezier.y2), 1)
        )
    }

    private func cubic(_ t: CGFloat, _ a: CGFloat, _ b: CGFloat, _ c: CGFloat, _ d: CGFloat) -> CGFloat {
        let mt = 1 - t
        return mt * mt * mt * a
            + 3 * mt * mt * t * b
            + 3 * mt * t * t * c
            + t * t * t * d
    }
}

private func drawGrid(in size: CGSize, context: inout GraphicsContext) {
    for index in 1..<4 {
        let horizontalY = (size.height / 4) * CGFloat(index)
        let verticalX = (size.width / 4) * CGFloat(index)

        var horizontal = Path()
        horizontal.move(to: CGPoint(x: 0, y: horizontalY))
        horizontal.addLine(to: CGPoint(x: size.width, y: horizontalY))
        context.stroke(horizontal, with: .color(Color.white.opacity(0.08)), lineWidth: 1)

        var vertical = Path()
        vertical.move(to: CGPoint(x: verticalX, y: 0))
        vertical.addLine(to: CGPoint(x: verticalX, y: size.height))
        context.stroke(vertical, with: .color(Color.white.opacity(0.08)), lineWidth: 1)
    }
}

enum SpringMode: String, CaseIterable, Hashable {
    case simple
    case advanced

    var label: String {
        switch self {
        case .simple:
            return "Time"
        case .advanced:
            return "Physics"
        }
    }
}

enum TransitionMode: String, CaseIterable, Hashable {
    case easing
    case simple
    case advanced

    var label: String {
        switch self {
        case .easing:
            return "Easing"
        case .simple:
            return "Time"
        case .advanced:
            return "Physics"
        }
    }
}

extension DialKitSpringValue {
    var mode: SpringMode {
        switch self {
        case .time:
            return .simple
        case .physics:
            return .advanced
        }
    }

    var durationHint: Double {
        switch self {
        case let .time(duration, _):
            return duration
        case .physics:
            return 0.3
        }
    }

    func switching(to mode: SpringMode) -> DialKitSpringValue {
        switch (self, mode) {
        case let (.time(duration, bounce), .simple):
            return .time(duration: duration, bounce: bounce)
        case let (.physics(stiffness, damping, mass), .advanced):
            return .physics(stiffness: stiffness, damping: damping, mass: mass)
        case (.time, .advanced):
            return .physics(stiffness: 200, damping: 25, mass: 1)
        case (.physics, .simple):
            return .time(duration: 0.3, bounce: 0.2)
        }
    }
}

extension DialKitTransitionValue {
    var mode: TransitionMode {
        switch self {
        case .easing:
            return .easing
        case let .spring(spring):
            return spring.mode == .simple ? .simple : .advanced
        }
    }

    func switching(to mode: TransitionMode) -> DialKitTransitionValue {
        switch mode {
        case .easing:
            switch self {
            case let .easing(duration, bezier):
                return .easing(duration: duration, bezier: bezier)
            case let .spring(spring):
                return .easing(duration: spring.durationHint, bezier: .standard)
            }
        case .simple:
            switch self {
            case let .easing(duration, _):
                return .spring(.time(duration: DialMotionDefaults.springDuration(from: duration), bounce: 0.2))
            case let .spring(spring):
                return .spring(spring.switching(to: .simple))
            }
        case .advanced:
            switch self {
            case .easing:
                return .spring(.physics(stiffness: 200, damping: 25, mass: 1))
            case let .spring(spring):
                return .spring(spring.switching(to: .advanced))
            }
        }
    }
}

private extension DialKitBezierValue {
    func updating(x1: Double? = nil, y1: Double? = nil, x2: Double? = nil, y2: Double? = nil) -> DialKitBezierValue {
        DialKitBezierValue(
            x1: x1 ?? self.x1,
            y1: y1 ?? self.y1,
            x2: x2 ?? self.x2,
            y2: y2 ?? self.y2
        )
    }
}

private func copyTextToPasteboard(_ text: String) {
    #if canImport(AppKit)
    NSPasteboard.general.clearContents()
    NSPasteboard.general.setString(text, forType: .string)
    #endif
}

private func color(from hex: String) -> Color {
    let cleaned = hex.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: "#", with: "")
    let expanded: String
    if cleaned.count == 3 {
        expanded = cleaned.map { "\($0)\($0)" }.joined()
    } else {
        expanded = cleaned
    }

    var hexValue: UInt64 = 0
    guard Scanner(string: expanded).scanHexInt64(&hexValue) else {
        return Color(.sRGB, white: 0.13, opacity: 1)
    }

    switch expanded.count {
    case 6:
        return Color(
            red: Double((hexValue >> 16) & 0xFF) / 255,
            green: Double((hexValue >> 8) & 0xFF) / 255,
            blue: Double(hexValue & 0xFF) / 255
        )
    case 8:
        return Color(
            red: Double((hexValue >> 24) & 0xFF) / 255,
            green: Double((hexValue >> 16) & 0xFF) / 255,
            blue: Double((hexValue >> 8) & 0xFF) / 255,
            opacity: Double(hexValue & 0xFF) / 255
        )
    default:
        return Color(.sRGB, white: 0.13, opacity: 1)
    }
}

#if canImport(AppKit)
private func nsColor(from hex: String) -> NSColor {
    let cleaned = hex.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: "#", with: "")
    let expanded: String
    if cleaned.count == 3 {
        expanded = cleaned.map { "\($0)\($0)" }.joined()
    } else {
        expanded = cleaned
    }

    var hexValue: UInt64 = 0
    guard Scanner(string: expanded).scanHexInt64(&hexValue) else {
        return NSColor(deviceWhite: 0.13, alpha: 1)
    }

    switch expanded.count {
    case 6:
        return NSColor(
            deviceRed: CGFloat((hexValue >> 16) & 0xFF) / 255,
            green: CGFloat((hexValue >> 8) & 0xFF) / 255,
            blue: CGFloat(hexValue & 0xFF) / 255,
            alpha: 1
        )
    case 8:
        return NSColor(
            deviceRed: CGFloat((hexValue >> 24) & 0xFF) / 255,
            green: CGFloat((hexValue >> 16) & 0xFF) / 255,
            blue: CGFloat((hexValue >> 8) & 0xFF) / 255,
            alpha: CGFloat(hexValue & 0xFF) / 255
        )
    default:
        return NSColor(deviceWhite: 0.13, alpha: 1)
    }
}

private func hexString(from color: NSColor) -> String? {
    guard let color = color.usingColorSpace(.deviceRGB) else {
        return nil
    }

    let red = Int(round(color.redComponent * 255))
    let green = Int(round(color.greenComponent * 255))
    let blue = Int(round(color.blueComponent * 255))
    let alpha = Int(round(color.alphaComponent * 255))
    if alpha < 255 {
        return String(format: "#%02X%02X%02X%02X", red, green, blue, alpha)
    }

    return String(format: "#%02X%02X%02X", red, green, blue)
}
#endif

private func hexString(from color: Color) -> String? {
#if canImport(AppKit)
    return hexString(from: NSColor(color))
#else
    return nil
#endif
}
