import LedgeCore
import SwiftUI

/// A live picture of the trackpad: the edge zones with their current levels,
/// the media strip and tap sections, and every contact on the surface (palms in red).
struct TrackpadMapView: View {
    let settings: Settings
    @ObservedObject var model: AppModel
    /// Menu windows size themselves to their content, so the map needs a definite size.
    var width: CGFloat = 308

    var body: some View {
        let surface = model.primarySurface
        let size = CGSize(width: width, height: (width * surface.heightMM / surface.widthMM).rounded())
        map(size: size, surface: surface)
            .frame(width: size.width, height: size.height)
            .animation(.easeOut(duration: 0.12), value: settings.edgeWidth)
    }

    private func map(size: CGSize, surface: SurfaceSize) -> some View {
        Group {
            let edgeWidth = max(10, settings.edgeWidth * size.width)
            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(.quaternary.opacity(0.55))
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(.primary.opacity(0.08))

                if settings.mediaStrip { mediaStrip(size: size, surface: surface) }
                sections(size: size, surface: surface)

                edgeZone(.left, width: edgeWidth, size: size)
                edgeZone(.right, width: edgeWidth, size: size)
                    .offset(x: size.width - edgeWidth)

                readouts(size: size, edgeWidth: edgeWidth)

                ForEach(model.touches, id: \.id) { touch in
                    contact(touch)
                        .position(x: touch.x * size.width, y: (1 - touch.y) * size.height)
                }
            }
        }
    }

    private func edgeZone(_ edge: Side, width: CGFloat, size: CGSize) -> some View {
        let action = settings.action(for: edge)
        let level = model.value(for: action) ?? 0
        let active = model.activeEdge == edge
        let usable = settings.activeArea.fraction
        return ZStack(alignment: .bottom) {
            Rectangle().fill(action.tint.opacity(action == .off ? 0 : 0.12))
            Rectangle()
                .fill(action.tint.gradient.opacity(action == .off ? 0 : (active ? 0.95 : 0.7)))
                .frame(height: size.height * level)
            if usable < 1 {
                // Slides can't start in the dimmed part.
                VStack(spacing: 0) {
                    Rectangle().fill(.background.opacity(0.55)).frame(height: size.height * (1 - usable))
                    Spacer(minLength: 0)
                }
            }
        }
        .frame(width: width, height: size.height)
        .clipShape(UnevenRoundedRectangle(
            topLeadingRadius: edge == .left ? 14 : 0, bottomLeadingRadius: edge == .left ? 14 : 0,
            bottomTrailingRadius: edge == .right ? 14 : 0, topTrailingRadius: edge == .right ? 14 : 0,
            style: .continuous))
        .animation(.interactiveSpring(response: 0.2, dampingFraction: 0.9), value: level)
    }

    private func mediaStrip(size: CGSize, surface: SurfaceSize) -> some View {
        let height = min(0.2, max(0.04, settings.edgeWidth * surface.widthMM / surface.heightMM)) * size.height
        return HStack {
            Image(systemName: settings.reverseMediaSwipe ? "forward.fill" : "backward.fill")
            Spacer()
            Spacer()
            Image(systemName: settings.reverseMediaSwipe ? "backward.fill" : "forward.fill")
        }
        .font(.system(size: 8, weight: .bold))
        .foregroundStyle(.secondary)
        .padding(.horizontal, size.width * 0.18)
        .frame(width: size.width, height: max(12, height))
        .background(Rectangle().fill(.primary.opacity(0.05)))
        .offset(y: size.height - max(12, height))
    }

    /// A finger dot sized by the sensor's contact ellipse; palms show as a red blob.
    private func contact(_ touch: Touch) -> some View {
        let tuning = EdgeGestureRecognizer.Tuning()
        let isPalm = touch.majorAxis >= tuning.palmMajorAxis || touch.size >= tuning.palmSize
        let diameter = max(14, min(44, touch.majorAxis * 1.7))
        let color: Color = isPalm ? .red : .accentColor
        return Circle()
            .fill(color.opacity(isPalm ? 0.35 : 0.85))
            .overlay(Circle().strokeBorder(.white.opacity(isPalm ? 0.3 : 0.8), lineWidth: 1.5))
            .frame(width: diameter, height: diameter)
            .shadow(color: color.opacity(0.5), radius: 6)
    }

    @ViewBuilder
    private func sections(size: CGSize, surface: SurfaceSize) -> some View {
        ForEach(TapZone.allCases) { zone in
            let action = settings.tapAction(for: zone)
            if action != .none {
                let r = EdgeGestureRecognizer.rect(of: zone, on: surface)
                ActionIcon(action: action, size: 9)
                    .foregroundStyle(.secondary)
                    .frame(width: (r.maxX - r.minX) * size.width, height: (r.maxY - r.minY) * size.height)
                    .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(.primary.opacity(0.07)).padding(2))
                    .offset(x: r.minX * size.width, y: (1 - r.maxY) * size.height)
            }
        }
    }

    private func readouts(size: CGSize, edgeWidth: CGFloat) -> some View {
        HStack(alignment: .top) {
            readout(.left, alignment: .leading)
            Spacer()
            readout(.right, alignment: .trailing)
        }
        .padding(.horizontal, edgeWidth + 12)
        .padding(.top, size.height * 0.22)
        .frame(width: size.width)
    }

    private func readout(_ edge: Side, alignment: HorizontalAlignment) -> some View {
        let action = settings.action(for: edge)
        let value = model.value(for: action)
        return VStack(alignment: alignment, spacing: 2) {
            Label(action.title, systemImage: action == .volume && model.muted ? "speaker.slash.fill" : action.symbol)
                .labelStyle(.titleAndIcon)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(action.tint)
            HStack(alignment: .firstTextBaseline, spacing: 1) {
                Text(value.map { "\(Int(($0 * 100).rounded()))" } ?? "–")
                    .font(.system(size: 30, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .contentTransition(.numericText())
                if value != nil {
                    Text("%").font(.system(size: 13, weight: .medium)).foregroundStyle(.secondary)
                }
            }
        }
        .opacity(action == .off ? 0 : 1)
        .animation(.snappy(duration: 0.18), value: value)
    }
}
