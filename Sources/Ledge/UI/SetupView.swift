import LedgeCore
import SwiftUI

/// First-run guide: grant Accessibility, then try a slide with live feedback.
struct SetupView: View {
    @ObservedObject var prefs: Preferences
    @ObservedObject var model: AppModel
    let requestAccessibility: () -> Void
    let done: () -> Void
    @State private var triedSlide = false

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 12) {
                LedgeMark(size: 34)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Welcome to Ledge").font(.system(size: 20, weight: .semibold))
                    Text("Your trackpad's edges become volume and brightness sliders.")
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            step(1, title: "Allow Accessibility",
                 detail: "Lets Ledge hold the pointer still while you slide, send media keys and swallow corner taps.",
                 done: model.accessibilityGranted) {
                if !model.accessibilityGranted {
                    Button("Open Settings", action: requestAccessibility)
                }
            }

            step(2, title: "Try a slide",
                 detail: "Rest a finger on the right edge of the trackpad and slide it up or down.",
                 done: triedSlide) { EmptyView() }

            TrackpadMapView(settings: prefs.settings, model: model, width: 412)

            HStack {
                Text("Ledge lives in your menu bar. Click its icon any time to change settings.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                Spacer()
                Button(triedSlide ? "Done" : "Skip", action: done)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(width: 460)
        .onAppear { model.menuIsOpen = true }
        .onDisappear { model.menuIsOpen = false }
        .onChange(of: model.activeEdge) { _, edge in
            if edge != nil { triedSlide = true }
        }
    }

    private func step<Accessory: View>(_ number: Int, title: String, detail: String, done: Bool,
                                       @ViewBuilder accessory: () -> Accessory) -> some View {
        HStack(alignment: .top, spacing: 12) {
            ZStack {
                Circle().fill(done ? AnyShapeStyle(Color.green.gradient) : AnyShapeStyle(.quaternary))
                if done {
                    Image(systemName: "checkmark").font(.system(size: 11, weight: .bold)).foregroundStyle(.white)
                } else {
                    Text("\(number)").font(.system(size: 12, weight: .semibold))
                }
            }
            .frame(width: 24, height: 24)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 13, weight: .semibold))
                Text(detail).font(.system(size: 12)).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
            accessory()
        }
    }
}
