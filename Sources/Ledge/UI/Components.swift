import AppKit
import LedgeCore
import SwiftUI

extension EdgeAction {
    var symbol: String {
        switch self {
        case .brightness: return "sun.max.fill"
        case .volume: return "speaker.wave.2.fill"
        case .keyboardBacklight: return "light.max"
        case .off: return "nosign"
        }
    }

    var tint: Color {
        switch self {
        case .brightness: return .orange
        case .volume: return .blue
        case .keyboardBacklight: return .purple
        case .off: return .secondary
        }
    }
}

extension TapAction.Kind {
    var title: String {
        switch self {
        case .none: return "Nothing"
        case .mute: return "Mute / Unmute"
        case .playPause: return "Play / Pause"
        case .nextTrack: return "Next Track"
        case .previousTrack: return "Previous Track"
        case .missionControl: return "Mission Control"
        case .showDesktop: return "Show Desktop"
        case .lockScreen: return "Lock Screen"
        case .screenshot: return "Screenshot"
        case .openApp: return "Open App…"
        case .runShortcut: return "Run Shortcut…"
        case .openURL: return "Open Link or File…"
        case .keyboardShortcut: return "Press Keys…"
        case .shellCommand: return "Run Command…"
        case .timer: return "Start Timer…"
        }
    }

    var symbol: String {
        switch self {
        case .none: return "circle.dashed"
        case .mute: return "speaker.slash.fill"
        case .playPause: return "playpause.fill"
        case .nextTrack: return "forward.fill"
        case .previousTrack: return "backward.fill"
        case .missionControl: return "rectangle.3.group"
        case .showDesktop: return "menubar.dock.rectangle"
        case .lockScreen: return "lock.fill"
        case .screenshot: return "camera.viewfinder"
        case .openApp: return "app.badge"
        case .runShortcut: return "square.2.layers.3d"
        case .openURL: return "link"
        case .keyboardShortcut: return "command"
        case .shellCommand: return "terminal"
        case .timer: return "timer"
        }
    }

    /// Picker groups, in display order.
    static let groups: [(title: String, kinds: [TapAction.Kind])] = [
        ("Media", [.mute, .playPause, .nextTrack, .previousTrack]),
        ("System", [.missionControl, .showDesktop, .lockScreen, .screenshot]),
        ("Open & Run", [.openApp, .runShortcut, .openURL, .keyboardShortcut, .shellCommand, .timer]),
    ]
}

extension TapAction {
    var symbol: String { kind.symbol }

    /// One line describing the action with its settings, e.g. "Open Clock".
    var summary: String {
        switch self {
        case .openApp(let path): return path.isEmpty ? "Open App (none chosen)" : "Open \(ActionRunner.appName(at: path))"
        case .runShortcut(let name): return name.isEmpty ? "Run Shortcut (none chosen)" : "Run “\(name)”"
        case .openURL(let text): return text.isEmpty ? "Open Link (empty)" : "Open \(text)"
        case .keyboardShortcut(let combo): return combo.display.isEmpty ? "Press Keys (none)" : "Press \(combo.display)"
        case .shellCommand(let command): return command.isEmpty ? "Run Command (empty)" : command
        case .timer(let minutes): return "\(minutes)-minute timer"
        default: return kind.title
        }
    }

    /// The app's icon when the action opens an app.
    var appIcon: NSImage? {
        guard case .openApp(let path) = self, !path.isEmpty else { return nil }
        return NSWorkspace.shared.icon(forFile: path)
    }
}

/// An action's icon: the app icon for Open App, otherwise its symbol.
struct ActionIcon: View {
    let action: TapAction
    var size: CGFloat = 14

    var body: some View {
        if let icon = action.appIcon {
            Image(nsImage: icon).resizable().frame(width: size * 1.4, height: size * 1.4)
        } else {
            Image(systemName: action.symbol).font(.system(size: size, weight: .semibold))
        }
    }
}

/// Round icon badge used at the start of each row.
struct IconBadge: View {
    let symbol: String
    var active = true

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(active ? Color.white : Color.secondary)
            .frame(width: 30, height: 30)
            .background(Circle().fill(active ? AnyShapeStyle(Color.accentColor.gradient) : AnyShapeStyle(.quaternary)))
    }
}

/// Icon, title, subtitle and a trailing control.
struct SettingRow<Control: View>: View {
    let symbol: String
    let title: String
    var subtitle: String?
    var active = true
    @ViewBuilder var control: Control

    var body: some View {
        HStack(spacing: 12) {
            IconBadge(symbol: symbol, active: active)
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.system(size: 13, weight: .medium))
                if let subtitle {
                    Text(subtitle)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 8)
            control
        }
        .padding(.vertical, 3)
    }
}

/// A labelled slider with its value on the right.
struct ValueSlider: View {
    let symbol: String
    let title: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    let step: Double
    let format: (Double) -> String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Image(systemName: symbol)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
                    .frame(width: 18)
                Text(title).font(.system(size: 13, weight: .medium))
                Spacer()
                Text(format(value))
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
            Slider(value: $value, in: range, step: step)
                .controlSize(.small)
        }
    }
}

struct SectionHeader: View {
    let title: String

    var body: some View {
        Text(title.uppercased())
            .font(.system(size: 10, weight: .semibold))
            .tracking(0.6)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, 6)
    }
}

/// Small menu-style picker sized for a row.
struct RowPicker<Value: Hashable & Identifiable>: View {
    @Binding var selection: Value
    let options: [Value]
    let title: (Value) -> String

    var body: some View {
        Picker("", selection: $selection) {
            ForEach(options) { option in
                Text(title(option)).tag(option)
            }
        }
        .labelsHidden()
        .pickerStyle(.menu)
        .controlSize(.small)
        .fixedSize()
    }
}

struct StatusPill: View {
    let status: AppModel.Status

    private var color: Color {
        switch status {
        case .ready: return .green
        case .paused: return .secondary
        case .needsAccess: return .orange
        case .noTrackpad: return .red
        }
    }

    var body: some View {
        HStack(spacing: 5) {
            Circle().fill(color).frame(width: 7, height: 7)
            Text(status.title)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(Capsule().fill(.quaternary.opacity(0.6)))
    }
}

/// The app's mark: a trackpad outline with two lit edges.
struct LedgeMark: View {
    var size: CGFloat = 22

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.22, style: .continuous)
                .fill(.background)
                .overlay(RoundedRectangle(cornerRadius: size * 0.22, style: .continuous).strokeBorder(.primary.opacity(0.15)))
            HStack {
                Capsule().fill(Color.orange.gradient).frame(width: size * 0.13, height: size * 0.5)
                Spacer()
                Capsule().fill(Color.blue.gradient).frame(width: size * 0.13, height: size * 0.62)
            }
            .padding(.horizontal, size * 0.16)
        }
        .frame(width: size * 1.3, height: size)
    }
}
