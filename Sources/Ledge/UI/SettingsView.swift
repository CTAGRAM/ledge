import LedgeCore
import ServiceManagement
import SwiftUI

struct SettingsView: View {
    @ObservedObject var prefs: Preferences
    @ObservedObject var model: AppModel
    let actions: AppActions
    let back: () -> Void
    @State private var opensAtLogin = SMAppService.mainApp.status == .enabled

    private var edgeOptions: [EdgeAction] {
        EdgeAction.allCases.filter { $0 != .keyboardBacklight || KeyboardLight.isAvailable }
    }

    var body: some View {
        let settings = prefs.settings
        VStack(spacing: 10) {
            HStack(spacing: 10) {
                LedgeMark()
                Text("Settings").font(.system(size: 15, weight: .semibold))
                Spacer()
            }

            ScrollView {
                VStack(spacing: 10) {
                    rows(settings)
                }
                .padding(.horizontal, 16)
            }
            .frame(height: 560)
            .padding(.horizontal, -16)

            Divider().padding(.top, 4)
            HStack {
                Button(action: back) {
                    Label("Back", systemImage: "chevron.left")
                }
                .buttonStyle(.plain)
                Spacer()
                Text("Version \(Bundle.main.shortVersion)")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            .font(.system(size: 13))
        }
        .padding(16)
    }

    @ViewBuilder
    private func rows(_ settings: Settings) -> some View {
        SectionHeader(title: "Edges")
        SettingRow(symbol: "rectangle.lefthalf.inset.filled", title: "Left Edge") {
            RowPicker(selection: $prefs.settings.leftAction, options: edgeOptions, title: \.title)
        }
        SettingRow(symbol: "rectangle.righthalf.inset.filled", title: "Right Edge") {
            RowPicker(selection: $prefs.settings.rightAction, options: edgeOptions, title: \.title)
        }
        SettingRow(symbol: "arrow.left.arrow.right", title: "Swap Sides",
                   subtitle: "\(settings.leftAction.title) left · \(settings.rightAction.title) right", active: false) {
            Button("Swap") {
                let left = prefs.settings.leftAction
                prefs.settings.leftAction = prefs.settings.rightAction
                prefs.settings.rightAction = left
            }
            .controlSize(.small)
        }
        SettingRow(symbol: "rectangle.bottomhalf.inset.filled", title: "Active Area",
                   subtitle: "Where a slide may start", active: settings.activeArea != .full) {
            RowPicker(selection: $prefs.settings.activeArea, options: ActiveArea.allCases, title: \.title)
        }
        SettingRow(symbol: "option", title: "Require Fn or ⌥", subtitle: "Only react while holding a modifier",
                   active: settings.requireModifier) {
            Toggle("", isOn: $prefs.settings.requireModifier).labelsHidden().toggleStyle(.switch).controlSize(.small)
        }
        SettingRow(symbol: "square.grid.3x2.fill", title: "Tap Sections", subtitle: "Double-tap actions for six areas",
                   active: settings.tapActions.values.contains { $0 != .none }) {
            Button("Edit…", action: actions.showSections).controlSize(.small)
        }

        SectionHeader(title: "While Sliding")
        SettingRow(symbol: "cursorarrow", title: "Freeze Pointer", subtitle: "Pointer stays hidden and still",
                   active: settings.freezePointer) {
            Toggle("", isOn: $prefs.settings.freezePointer).labelsHidden().toggleStyle(.switch).controlSize(.small)
        }
        SettingRow(symbol: "scroll", title: "Stop Page Scrolling", subtitle: "Pages stay put under a slide",
                   active: settings.blockScrolling) {
            Toggle("", isOn: $prefs.settings.blockScrolling).labelsHidden().toggleStyle(.switch).controlSize(.small)
        }
        SettingRow(symbol: "ruler", title: "Steps", subtitle: "Smooth ticks like the keys every 1/16",
                   active: settings.stepSize != .smooth) {
            RowPicker(selection: $prefs.settings.stepSize, options: StepSize.allCases, title: \.title)
        }
        SettingRow(symbol: "dial.medium", title: "Fine Control", subtitle: "Hold ⇧⌥ to slide 4× finer",
                   active: settings.fineControl) {
            Toggle("", isOn: $prefs.settings.fineControl).labelsHidden().toggleStyle(.switch).controlSize(.small)
        }
        SettingRow(symbol: "rectangle.inset.filled", title: "On-Screen Display", active: settings.hudStyle != .off) {
            RowPicker(selection: $prefs.settings.hudStyle, options: HUDStyle.allCases, title: \.title)
        }

        SectionHeader(title: "General")
        SettingRow(symbol: "circle.lefthalf.filled", title: "Appearance") {
            Picker("", selection: $prefs.settings.appearance) {
                ForEach(AppearanceMode.allCases) { Text($0.title).tag($0) }
            }
            .labelsHidden().pickerStyle(.segmented).controlSize(.small).fixedSize()
        }
        SettingRow(symbol: "power", title: "Open at Login", active: opensAtLogin) {
            Toggle("", isOn: Binding(get: { opensAtLogin }, set: setOpensAtLogin))
                .labelsHidden().toggleStyle(.switch).controlSize(.small)
        }
        SettingRow(symbol: "hand.raised.fill", title: "Accessibility",
                   subtitle: model.accessibilityGranted ? "Granted" : "Needed for pointer freeze and taps",
                   active: model.accessibilityGranted) {
            if model.accessibilityGranted {
                Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
            } else {
                Button("Grant", action: actions.requestAccessibility).controlSize(.small)
            }
        }
    }

    private func setOpensAtLogin(_ enabled: Bool) {
        do {
            if enabled { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
        } catch {
            NSLog("Ledge: open at login failed: \(error.localizedDescription)")
        }
        opensAtLogin = SMAppService.mainApp.status == .enabled
    }
}

extension Bundle {
    var shortVersion: String {
        infoDictionary?["CFBundleShortVersionString"] as? String ?? "dev"
    }
}
