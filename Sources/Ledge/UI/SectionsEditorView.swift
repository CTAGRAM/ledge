import AppKit
import LedgeCore
import SwiftUI
import UniformTypeIdentifiers

/// Assigns an action to each of the six double-tap sections.
struct SectionsEditorView: View {
    @ObservedObject var prefs: Preferences
    @ObservedObject var model: AppModel
    @State private var selected: TapZone = .topRight
    @State private var shortcuts: [String] = []

    private var action: Binding<TapAction> {
        Binding(get: { prefs.settings.tapAction(for: selected) },
                set: { prefs.settings.tapActions[selected] = $0 })
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 3) {
                Text("Tap Sections").font(.system(size: 20, weight: .semibold))
                Text("Double-tap one of these areas of your trackpad to run anything you like.")
                    .foregroundStyle(.secondary)
            }

            HStack(alignment: .top, spacing: 22) {
                SectionPad(settings: prefs.settings, surface: model.primarySurface, selected: $selected)
                editor
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            Divider()
            Label {
                Text("For alarms, pick **Open App → Clock**, or **Run Shortcut** with a Clock action such as *Create Alarm* or *Start Timer*. **Start Timer** works on its own; double-tap again to cancel it.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } icon: {
                Image(systemName: "lightbulb").foregroundStyle(.yellow)
            }
        }
        .padding(24)
        .frame(width: 640)
        .onAppear { ShortcutsLibrary.list { shortcuts = $0 } }
    }

    private var editor: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(selected.title).font(.system(size: 15, weight: .semibold))

            Picker("Action", selection: Binding(
                get: { action.wrappedValue.kind },
                set: { kind in if kind != action.wrappedValue.kind { action.wrappedValue = TapAction(kind: kind) } })) {
                Label(TapAction.Kind.none.title, systemImage: TapAction.Kind.none.symbol).tag(TapAction.Kind.none)
                ForEach(TapAction.Kind.groups, id: \.title) { group in
                    Section(group.title) {
                        ForEach(group.kinds) { kind in
                            Label(kind.title, systemImage: kind.symbol).tag(kind)
                        }
                    }
                }
            }
            .pickerStyle(.menu)
            .frame(maxWidth: 300)

            ActionOptions(action: action, shortcuts: $shortcuts)

            HStack {
                Button {
                    if action.wrappedValue == .mute {
                        Volume.setMuted(!Volume.isMuted)
                    } else {
                        ActionRunner.run(action.wrappedValue)
                    }
                } label: {
                    Label("Try It", systemImage: "play.fill")
                }
                .disabled(action.wrappedValue == .none)
                Button("Clear") { action.wrappedValue = .none }
                    .disabled(action.wrappedValue == .none)
            }
            .padding(.top, 4)

            if !selected.isTop, action.wrappedValue != .none {
                Text("Clicks pressed near the bottom edge never count as taps.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
        }
    }
}

/// A trackpad drawing with the six sections as buttons.
private struct SectionPad: View {
    let settings: Settings
    let surface: SurfaceSize
    @Binding var selected: TapZone
    private let width: CGFloat = 280

    var body: some View {
        let height = (width * surface.heightMM / surface.widthMM).rounded()
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 16, style: .continuous).fill(.quaternary.opacity(0.6))
            RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(.primary.opacity(0.1))
            ForEach(TapZone.allCases) { zone in
                let r = EdgeGestureRecognizer.rect(of: zone, on: surface)
                // Sections are drawn a little larger than their touch area so they are easy to click.
                let w = max(54, (r.maxX - r.minX) * width)
                let h = max(42, (r.maxY - r.minY) * height)
                let x = min(width - w, max(0, ((r.minX + r.maxX) / 2) * width - w / 2))
                let y = zone.isTop ? 0 : height - h
                cell(zone)
                    .frame(width: w, height: h)
                    .offset(x: x, y: y)
            }
        }
        .frame(width: width, height: height)
    }

    private func cell(_ zone: TapZone) -> some View {
        let action = settings.tapAction(for: zone)
        let isSelected = zone == selected
        return Button {
            selected = zone
        } label: {
            ZStack {
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .fill(isSelected ? AnyShapeStyle(Color.accentColor.opacity(0.25)) : AnyShapeStyle(.primary.opacity(0.06)))
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .strokeBorder(isSelected ? Color.accentColor : .clear, lineWidth: 2)
                if action == .none {
                    Image(systemName: "plus").font(.system(size: 12, weight: .semibold)).foregroundStyle(.tertiary)
                } else {
                    ActionIcon(action: action, size: 15).foregroundStyle(isSelected ? Color.accentColor : .primary)
                }
            }
            .padding(4)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(action == .none ? zone.title : "\(zone.title): \(action.summary)")
    }
}

/// The settings each kind of action needs.
private struct ActionOptions: View {
    @Binding var action: TapAction
    @Binding var shortcuts: [String]

    var body: some View {
        switch action {
        case .openApp(let path):
            HStack(spacing: 10) {
                if !path.isEmpty {
                    Image(nsImage: NSWorkspace.shared.icon(forFile: path)).resizable().frame(width: 28, height: 28)
                    Text(ActionRunner.appName(at: path)).font(.system(size: 13, weight: .medium))
                } else {
                    Text("No app chosen").foregroundStyle(.secondary)
                }
                Spacer()
                Button("Choose…") { chooseApp() }
            }
            HStack(spacing: 6) {
                Text("Quick picks:").font(.system(size: 11)).foregroundStyle(.secondary)
                ForEach(["Clock", "Calculator", "Notes", "Reminders", "Terminal"], id: \.self) { name in
                    if let path = Self.systemAppPath(name) {
                        Button { action = .openApp(path: path) } label: {
                            Image(nsImage: NSWorkspace.shared.icon(forFile: path)).resizable().frame(width: 24, height: 24)
                        }
                        .buttonStyle(.plain)
                        .help(name)
                    }
                }
            }
        case .runShortcut(let name):
            HStack {
                Picker("Shortcut", selection: Binding(get: { name }, set: { action = .runShortcut(name: $0) })) {
                    Text("Choose…").tag("")
                    ForEach(shortcuts, id: \.self) { Text($0).tag($0) }
                    if !name.isEmpty, !shortcuts.contains(name) { Text(name).tag(name) }
                }
                .frame(maxWidth: 260)
                Button {
                    ShortcutsLibrary.list { shortcuts = $0 }
                } label: { Image(systemName: "arrow.clockwise") }
                .help("Reload shortcuts")
            }
            HStack {
                Text("Make one in Shortcuts, e.g. with Clock’s “Create Alarm”.")
                    .font(.system(size: 11)).foregroundStyle(.secondary)
                Button("Open Shortcuts") {
                    NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/Shortcuts.app"))
                }
                .controlSize(.small)
            }
        case .openURL(let text):
            TextField("https://example.com or ~/Documents/file.pdf",
                      text: Binding(get: { text }, set: { action = .openURL($0) }))
                .textFieldStyle(.roundedBorder)
        case .keyboardShortcut(let combo):
            HStack {
                KeyRecorder(combo: Binding(get: { combo }, set: { action = .keyboardShortcut($0) }))
                Text("Pressed as if you typed it.").font(.system(size: 11)).foregroundStyle(.secondary)
            }
        case .shellCommand(let command):
            TextField("say hello", text: Binding(get: { command }, set: { action = .shellCommand($0) }))
                .textFieldStyle(.roundedBorder)
                .font(.system(size: 12, design: .monospaced))
            Text("Runs in zsh in the background.").font(.system(size: 11)).foregroundStyle(.secondary)
        case .timer(let minutes):
            HStack {
                Stepper(value: Binding(get: { minutes }, set: { action = .timer(minutes: $0) }), in: 1...240) {
                    Text("\(minutes) minute\(minutes == 1 ? "" : "s")").monospacedDigit()
                }
                ForEach([1, 5, 10, 25, 60], id: \.self) { preset in
                    Button("\(preset)") { action = .timer(minutes: preset) }.controlSize(.small)
                }
            }
            Text("Rings with a sound and a banner. Double-tap again while it runs to cancel.")
                .font(.system(size: 11)).foregroundStyle(.secondary)
        default:
            EmptyView()
        }
    }

    private static func systemAppPath(_ name: String) -> String? {
        ["/System/Applications/\(name).app", "/System/Applications/Utilities/\(name).app", "/Applications/\(name).app"]
            .first { FileManager.default.fileExists(atPath: $0) }
    }

    private func chooseApp() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.application]
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.canChooseDirectories = false
        panel.prompt = "Choose"
        panel.begin { response in
            if response == .OK, let url = panel.url { action = .openApp(path: url.path) }
        }
    }
}

/// Click, then type a key combination to record it.
private struct KeyRecorder: View {
    @Binding var combo: KeyCombo
    @State private var recording = false
    @State private var monitor: Any?

    var body: some View {
        Button {
            recording ? stop() : start()
        } label: {
            Text(recording ? "Type the keys…" : (combo.display.isEmpty ? "Record Keys" : combo.display))
                .font(.system(size: 13, weight: .medium, design: .rounded))
                .frame(minWidth: 120)
        }
        .onDisappear(perform: stop)
    }

    private func start() {
        recording = true
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            combo = Self.combo(from: event)
            stop()
            return nil
        }
    }

    private func stop() {
        recording = false
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
    }

    private static func combo(from event: NSEvent) -> KeyCombo {
        let flags = event.modifierFlags
        var cgFlags = CGEventFlags()
        var symbols = ""
        if flags.contains(.control) { cgFlags.insert(.maskControl); symbols += "⌃" }
        if flags.contains(.option) { cgFlags.insert(.maskAlternate); symbols += "⌥" }
        if flags.contains(.shift) { cgFlags.insert(.maskShift); symbols += "⇧" }
        if flags.contains(.command) { cgFlags.insert(.maskCommand); symbols += "⌘" }
        return KeyCombo(keyCode: event.keyCode, modifiers: cgFlags.rawValue, display: symbols + keyName(event))
    }

    private static func keyName(_ event: NSEvent) -> String {
        let special: [UInt16: String] = [
            36: "↩", 48: "⇥", 49: "Space", 51: "⌫", 53: "⎋", 117: "⌦",
            123: "←", 124: "→", 125: "↓", 126: "↑", 115: "Home", 119: "End", 116: "Page Up", 121: "Page Down",
            122: "F1", 120: "F2", 99: "F3", 118: "F4", 96: "F5", 97: "F6", 98: "F7", 100: "F8",
            101: "F9", 109: "F10", 103: "F11", 111: "F12",
        ]
        if let name = special[event.keyCode] { return name }
        return (event.charactersIgnoringModifiers ?? "?").uppercased()
    }
}
