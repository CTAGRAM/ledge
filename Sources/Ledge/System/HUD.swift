import AppKit
import LedgeCore
import LedgePrivate
import SwiftUI

/// What a HUD shows: which control and its level.
struct HUDContent: Equatable {
    var action: EdgeAction
    var value: Double
    var muted = false

    var symbol: String {
        switch action {
        case .brightness: return "sun.max.fill"
        case .volume:
            if muted || value == 0 { return "speaker.slash.fill" }
            return value < 0.34 ? "speaker.wave.1.fill" : value < 0.67 ? "speaker.wave.2.fill" : "speaker.wave.3.fill"
        case .keyboardBacklight: return value == 0 ? "light.min" : "light.max"
        case .off: return "circle"
        }
    }

    var tint: Color {
        switch action {
        case .brightness: return .orange
        case .volume: return .blue
        case .keyboardBacklight: return .purple
        case .off: return .gray
        }
    }
}

/// Shows level changes with the system HUD, a matching Ledge HUD, or the edge bar.
final class HUDPresenter {
    var style: HUDStyle = .system
    private lazy var edgeHUD = FloatingHUD(placement: .edge) { EdgeHUDView(model: $0) }
    private lazy var nativeHUD = FloatingHUD(placement: .topCenter) { NativeStyleHUDView(model: $0) }
    private lazy var toastHUD = FloatingHUD(placement: .topCenter) { ToastView(model: $0) }

    /// A short confirmation, e.g. after a section double-tap opens an app.
    func toast(_ text: String, symbol: String) {
        guard style != .off else { return }
        toastHUD.showToast(text, symbol: symbol)
    }

    /// macOS 26 only draws the volume HUD for other apps; brightness requests are silently dropped.
    private let systemDrawsBrightness = ProcessInfo.processInfo.operatingSystemVersion.majorVersion < 26

    /// `steps` is 16 for normal slides and 64 for quarter steps, so the system HUD fills partial blocks.
    func show(_ content: HUDContent, on edge: Side?, steps: Int) {
        switch style {
        case .off:
            return
        case .system:
            let systemCanDraw = content.action == .volume || (content.action == .brightness && systemDrawsBrightness)
            if systemCanDraw, showSystemHUD(content, steps: steps) { return }
            nativeHUD.show(content, edge: edge ?? .right, steps: steps)
        case .edge:
            edgeHUD.show(content, edge: edge ?? .right, steps: steps)
        }
    }

    private func showSystemHUD(_ content: HUDContent, steps: Int) -> Bool {
        let image: LGOSDImage
        switch content.action {
        case .brightness: image = LGOSDImageBrightness
        case .volume: image = content.muted ? LGOSDImageSpeakerMuted : LGOSDImageSpeaker
        case .keyboardBacklight, .off: return false
        }
        let filled = content.muted ? 0 : UInt32((content.value * Double(steps)).rounded())
        return LGShowSystemHUD(image, CGMainDisplayID(), filled, UInt32(steps))
    }
}

// MARK: - Floating HUD windows

final class HUDModel: ObservableObject {
    @Published var content = HUDContent(action: .volume, value: 0)
    @Published var edge: Side = .right
    @Published var steps = 16
    @Published var toastText = ""
    @Published var toastSymbol = "checkmark"
}

/// A click-through panel that fades in, follows updates, and fades out after a moment.
private final class FloatingHUD {
    enum Placement { case edge, topCenter }

    private let model = HUDModel()
    private let panel: NSPanel
    private let host: NSView
    private let placement: Placement
    private var hideWork: DispatchWorkItem?

    init<Content: View>(placement: Placement, @ViewBuilder content: (HUDModel) -> Content) {
        self.placement = placement
        panel = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.ignoresMouseEvents = true
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        host = NSHostingView(rootView: content(model))
        host.setFrameSize(host.fittingSize)
        panel.contentView = host
        panel.setContentSize(host.fittingSize)
        panel.alphaValue = 0
    }

    func show(_ content: HUDContent, edge: Side, steps: Int) {
        model.content = content
        model.edge = edge
        model.steps = steps
        present(edge: edge)
    }

    func showToast(_ text: String, symbol: String) {
        model.toastText = text
        model.toastSymbol = symbol
        host.layoutSubtreeIfNeeded()
        panel.setContentSize(host.fittingSize)
        present(edge: .right)
    }

    private func present(edge: Side) {
        position(edge: edge)
        hideWork?.cancel()
        if panel.alphaValue < 1 {
            panel.orderFrontRegardless()
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.12
                panel.animator().alphaValue = 1
            }
        }
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            NSAnimationContext.runAnimationGroup({ context in
                context.duration = 0.35
                self.panel.animator().alphaValue = 0
            }, completionHandler: { [weak self] in
                if self?.panel.alphaValue == 0 { self?.panel.orderOut(nil) }
            })
        }
        hideWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2, execute: work)
    }

    private func position(edge: Side) {
        let screen = NSScreen.screens.first { $0.frame.contains(NSEvent.mouseLocation) } ?? NSScreen.main
        guard let screen else { return }
        let size = panel.frame.size
        let visible = screen.visibleFrame
        switch placement {
        case .edge:
            let x = edge == .left ? visible.minX + 14 : visible.maxX - size.width - 14
            panel.setFrameOrigin(NSPoint(x: x, y: visible.midY - size.height / 2))
        case .topCenter:
            // Just under the menu bar, where macOS 26 puts its own volume HUD.
            panel.setFrameOrigin(NSPoint(x: screen.frame.midX - size.width / 2, y: visible.maxY - size.height - 6))
        }
    }
}

/// Slim vertical level bar on the side of the screen that matches the trackpad edge.
private struct EdgeHUDView: View {
    @ObservedObject var model: HUDModel

    var body: some View {
        let content = model.content
        let level = content.muted ? 0 : content.value
        VStack(spacing: 10) {
            Text("\(Int((level * 100).rounded()))")
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .monospacedDigit()
            GeometryReader { proxy in
                ZStack(alignment: .bottom) {
                    Capsule().fill(.primary.opacity(0.12))
                    Capsule()
                        .fill(content.tint.gradient)
                        .frame(height: max(proxy.size.width, proxy.size.height * level))
                        .opacity(level == 0 ? 0 : 1)
                }
            }
            .frame(width: 10)
            .animation(.interactiveSpring(response: 0.18, dampingFraction: 0.9), value: level)
            Image(systemName: content.symbol)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(content.tint)
                .frame(height: 18)
        }
        .padding(.vertical, 16)
        .frame(width: 48, height: 244)
        .background(.regularMaterial, in: Capsule())
        .overlay(Capsule().strokeBorder(.primary.opacity(0.08)))
        .padding(8)
    }
}

/// Matches the look of the macOS volume HUD: a title and a dotted level track.
private struct NativeStyleHUDView: View {
    @ObservedObject var model: HUDModel

    private var title: String {
        switch model.content.action {
        case .brightness: return "Display"
        case .keyboardBacklight: return "Keyboard Brightness"
        case .volume: return "Volume"
        case .off: return ""
        }
    }

    private var symbols: (low: String, high: String) {
        switch model.content.action {
        case .brightness: return ("sun.min.fill", "sun.max.fill")
        case .keyboardBacklight: return ("light.min", "light.max")
        default: return ("speaker.fill", "speaker.wave.3.fill")
        }
    }

    var body: some View {
        let level = model.content.muted ? 0 : model.content.value
        VStack(alignment: .leading, spacing: 9) {
            Text(title).font(.system(size: 14, weight: .semibold))
            HStack(spacing: 10) {
                Image(systemName: symbols.low).font(.system(size: 12, weight: .semibold))
                GeometryReader { proxy in
                    ZStack(alignment: .leading) {
                        HStack(spacing: 0) {
                            ForEach(1..<16) { _ in
                                Spacer()
                                Circle().fill(.primary.opacity(0.25)).frame(width: 2, height: 2)
                            }
                            Spacer()
                        }
                        .frame(height: 6)
                        .offset(y: 7)
                        Capsule().fill(.primary.opacity(0.12)).frame(height: 5)
                        Capsule().fill(.primary).frame(width: max(5, proxy.size.width * level), height: 5)
                            .opacity(level == 0 ? 0 : 1)
                    }
                    .frame(maxHeight: .infinity)
                }
                .frame(height: 16)
                .animation(.interactiveSpring(response: 0.18, dampingFraction: 0.9), value: level)
                Image(systemName: symbols.high).font(.system(size: 14, weight: .semibold))
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
        .frame(width: 300)
        .modifier(GlassPanel())
        .padding(8)
    }
}

/// Liquid Glass on macOS 26, a material pill before that.
private struct GlassPanel: ViewModifier {
    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: 22, style: .continuous)
        if #available(macOS 26.0, *) {
            content.glassEffect(.regular, in: shape)
        } else {
            content
                .background(.regularMaterial, in: shape)
                .overlay(shape.strokeBorder(.primary.opacity(0.1)))
        }
    }
}

/// A pill with an icon and a line of text.
private struct ToastView: View {
    @ObservedObject var model: HUDModel

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: model.toastSymbol)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Color.accentColor)
            Text(model.toastText)
                .font(.system(size: 14, weight: .semibold))
                .lineLimit(1)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
        .fixedSize()
        .modifier(GlassPanel())
        .padding(8)
    }
}
