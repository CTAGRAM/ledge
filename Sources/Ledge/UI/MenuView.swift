import LedgeCore
import ServiceManagement
import SwiftUI

/// Root of the menu bar window: the main page, or Settings.
struct MenuRootView: View {
    @ObservedObject var prefs: Preferences
    @ObservedObject var model: AppModel
    let actions: AppActions
    @State var showingSettings = false

    var body: some View {
        Group {
            if showingSettings {
                SettingsView(prefs: prefs, model: model, actions: actions) { showingSettings = false }
            } else {
                MainMenuView(prefs: prefs, model: model, actions: actions) { showingSettings = true }
            }
        }
        .frame(width: 340)
        .onAppear {
            model.menuIsOpen = true
            model.refreshLevels()
        }
        .onDisappear {
            model.menuIsOpen = false
            model.touches = []
        }
        .onReceive(Timer.publish(every: 0.5, on: .main, in: .common).autoconnect()) { _ in
            // Picks up changes made with the keyboard keys or Control Centre.
            if model.menuIsOpen { model.refreshLevels() }
        }
    }
}

/// Callbacks into the app that views can't do themselves.
struct AppActions {
    var requestAccessibility: () -> Void
    var showSetup: () -> Void
    var showAbout: () -> Void
    var showSections: () -> Void
}

struct MainMenuView: View {
    @ObservedObject var prefs: Preferences
    @ObservedObject var model: AppModel
    let actions: AppActions
    let openSettings: () -> Void
    @State private var mediaExpanded = false

    var body: some View {
        let settings = prefs.settings
        VStack(spacing: 12) {
            header

            if !model.accessibilityGranted {
                AccessBanner(action: actions.requestAccessibility)
            }

            TrackpadMapView(settings: settings, model: model)
                .opacity(settings.enabled ? 1 : 0.45)

            VStack(spacing: 6) {
                SettingRow(symbol: "hand.tap.fill", title: "Haptic Feedback", subtitle: "A tick for every step", active: settings.haptics != .off) {
                    RowPicker(selection: $prefs.settings.haptics, options: HapticStrength.allCases, title: \.title)
                }
                SettingRow(symbol: "speaker.slash.fill", title: "Quick Mute", subtitle: "Double-tap the top-right corner",
                           active: settings.tapAction(for: .topRight) == .mute) {
                    Toggle("", isOn: tapBinding(.topRight, .mute))
                        .labelsHidden().toggleStyle(.switch).controlSize(.small)
                }
                SettingRow(symbol: "square.grid.3x2.fill", title: "Tap Sections",
                           subtitle: sectionsSummary(settings), active: settings.tapActions.values.contains { $0 != .none }) {
                    Button("Edit…", action: actions.showSections).controlSize(.small)
                }
                SettingRow(symbol: "forward.fill", title: "Media Strip", subtitle: "Swipe the bottom edge to skip", active: settings.mediaStrip) {
                    HStack(spacing: 6) {
                        Button {
                            withAnimation(.snappy(duration: 0.2)) { mediaExpanded.toggle() }
                        } label: {
                            Image(systemName: "chevron.down")
                                .font(.system(size: 10, weight: .bold))
                                .rotationEffect(.degrees(mediaExpanded ? 180 : 0))
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                        .help("More media strip options")
                        Toggle("", isOn: $prefs.settings.mediaStrip)
                            .labelsHidden().toggleStyle(.switch).controlSize(.small)
                    }
                }
                if mediaExpanded {
                    VStack(spacing: 6) {
                        SubToggle(title: "Double-tap to Play/Pause", subtitle: "Taps the bottom middle of the trackpad",
                                  isOn: tapBinding(.bottomCenter, .playPause))
                        SubToggle(title: "Reverse Swipe", subtitle: "Swipe left for the next track",
                                  isOn: $prefs.settings.reverseMediaSwipe)
                    }
                    .disabled(!settings.mediaStrip)
                    .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }

            Divider()

            VStack(spacing: 10) {
                ValueSlider(symbol: "gauge.with.dots.needle.67percent", title: "Sensitivity",
                            value: $prefs.settings.sensitivity, range: 0.5...3, step: 0.25) {
                    String(format: "%g×", $0)
                }
                ValueSlider(symbol: "arrow.left.and.right", title: "Edge Width",
                            value: $prefs.settings.edgeWidth, range: 0.03...0.15, step: 0.01) {
                    "\(Int(($0 * 100).rounded()))%"
                }
            }

            Divider()
            footer
        }
        .padding(16)
    }

    /// On when `zone` runs `action`; switching it off clears the section.
    private func tapBinding(_ zone: TapZone, _ action: TapAction) -> Binding<Bool> {
        Binding(get: { prefs.settings.tapAction(for: zone) == action },
                set: { prefs.settings.tapActions[zone] = $0 ? action : TapAction.none })
    }

    private func sectionsSummary(_ settings: Settings) -> String {
        let count = settings.tapActions.values.filter { $0 != .none }.count
        return count == 0 ? "Double-tap a section to open apps, timers…" : "\(count) of 6 sections in use"
    }

    private var header: some View {
        HStack(spacing: 10) {
            LedgeMark()
            Text("Ledge").font(.system(size: 15, weight: .semibold))
            Spacer()
            StatusPill(status: model.status(enabled: prefs.settings.enabled))
        }
    }

    private var footer: some View {
        HStack(spacing: 14) {
            Button(action: openSettings) {
                Label("Settings", systemImage: "gearshape")
            }
            .buttonStyle(.plain)
            Spacer()
            Menu {
                Button("Tap Sections…", action: actions.showSections)
                Button("Setup Guide…", action: actions.showSetup)
                Button("About Ledge", action: actions.showAbout)
                Divider()
                Button("Quit Ledge") { NSApp.terminate(nil) }
            } label: {
                Image(systemName: "ellipsis.circle").font(.system(size: 15))
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            Button {
                prefs.settings.enabled.toggle()
            } label: {
                Image(systemName: prefs.settings.enabled ? "pause.circle" : "play.circle.fill")
                    .font(.system(size: 15))
            }
            .buttonStyle(.plain)
            .help(prefs.settings.enabled ? "Pause edge gestures" : "Resume edge gestures")
        }
        .font(.system(size: 13))
    }
}

struct SubToggle: View {
    let title: String
    let subtitle: String
    @Binding var isOn: Bool

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.system(size: 12, weight: .medium))
                Text(subtitle).font(.system(size: 11)).foregroundStyle(.secondary)
            }
            Spacer()
            Toggle("", isOn: $isOn).labelsHidden().toggleStyle(.switch).controlSize(.mini)
        }
        .padding(.leading, 42)
    }
}

struct AccessBanner: View {
    let action: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "hand.raised.fill").foregroundStyle(.orange)
            VStack(alignment: .leading, spacing: 1) {
                Text("Accessibility access needed").font(.system(size: 12, weight: .semibold))
                Text("For the pointer freeze, media keys and corner taps.")
                    .font(.system(size: 11)).foregroundStyle(.secondary)
            }
            Spacer()
            Button("Grant", action: action).controlSize(.small)
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.orange.opacity(0.12)))
    }
}
