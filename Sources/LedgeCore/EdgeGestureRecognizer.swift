import Foundation

/// Which edge gestures are switched on and how big the zones are.
public struct GestureConfig: Equatable {
    public var layout: SliderLayout = .sides
    /// Thickness of the slide zones as a fraction of the surface width (the top strip is as thick in millimetres).
    public var edgeWidth: Double = 0.07
    /// Side edges only: how far up the edge a slide may start.
    public var activeArea: ActiveArea = .full
    public var leftEdge = true
    public var rightEdge = true
    public var mediaStrip = true
    /// Sections that react to a double-tap.
    public var tapZones: Set<TapZone> = [.topRight]
    /// Touches that land just after a key press are resting palms or thumbs, not gestures.
    public var ignoreWhileTyping = true

    public init() {}
}

public enum GestureEvent: Equatable {
    case slideBegan(Side)
    /// Travel along the slider since the previous event, in millimetres. Positive is up on the
    /// side edges and right on the top edge.
    case slideMoved(Side, deltaMM: Double)
    case slideEnded(Side)
    case mediaSwipe(forward: Bool)
    case doubleTap(TapZone)
}

/// Turns raw touch frames from one surface into edge gestures.
///
/// A gesture starts from a finger landing in a zone. Palms (recognised by their
/// contact size) are ignored completely, and fingers that were already resting on
/// the trackpad don't get in the way, nor do fingers that land while you type. Two
/// fingers landing together on the same side edge slide as one. Anything else –
/// pointing, scrolling, multi-finger gestures – is left alone.
public final class EdgeGestureRecognizer {
    public struct Tuning {
        public var slideStartMM = 1.0
        public var rejectMM = 3.5
        public var tapMaxMoveMM = 2.0
        public var tapMaxDuration = 0.3
        public var doubleTapWindow = 0.45
        public var swipeTriggerMM = 12.0
        public var cornerSizeMM = 15.0
        public var centerZoneWidthMM = 40.0
        public var zoneDepthMM = 12.0
        public var lostFingerGrace = 0.12
        public var reacquireMM = 15.0
        public var clickGuardAfterLift = 0.35
        /// A finger that has been down this long counts as resting, not as part of a new gesture.
        public var restingAfter = 0.25
        /// Fingertips measure roughly 6–12 on the sensor's contact ellipse; palms are much larger.
        public var palmMajorAxis = 16.0
        public var palmSize = 2.2
        /// Empty space between the two halves of the top strip.
        public var topGapMM = 24.0
        /// How long after a key press new touches are ignored.
        public var typingGuard = 0.75
        public init() {}
    }

    public var config: GestureConfig
    public var surface: SurfaceSize
    public var tuning = Tuning()
    /// Asked when a finger lands in a zone; return false to require a modifier key.
    public var gesturesAllowed: () -> Bool = { true }

    public init(config: GestureConfig = GestureConfig(), surface: SurfaceSize = .fallback) {
        self.config = config
        self.surface = surface
    }

    // MARK: State

    private enum Kind: Hashable {
        case slide(Side), swipe, tap(TapZone)
    }

    private enum Mode {
        case pending, sliding(Side), swiping(fired: Bool)
    }

    private struct Tracked {
        var id: Int32
        /// Other fingers on the same edge that move with this one.
        var siblings = Set<Int32>()
        var startX, startY: Double
        var lastX, lastY: Double
        var startTime: Double
        var kinds: Set<Kind>
        var mode: Mode
        var physicallyClicked = false
        /// When the sensor last lost firm contact (it often comes back within a frame or two).
        var hoverStart: Double?

        var isPending: Bool { if case .pending = mode { return true } else { return false } }
        var slideSides: [Side] { kinds.compactMap { if case .slide(let side) = $0 { return side } else { return nil } } }
        var tapZone: TapZone? { kinds.lazy.compactMap { if case .tap(let zone) = $0 { return zone } else { return nil } }.first }
    }

    private var tracked: Tracked?
    private var lost: (slide: Tracked, edge: Side, at: Double)?
    private var ignored = Set<Int32>()
    private var palms = Set<Int32>()
    private var firstSeen: [Int32: Double] = [:]
    private var lastTap: (zone: TapZone, time: Double)?
    private var clickGuardUntil = 0.0
    private var lastKeyDown = -Double.infinity

    /// True while a slide is running; the app freezes the pointer during that time.
    public var isSliding: Bool { slidingEdge != nil }

    /// The edge being slid, if any.
    public var slidingEdge: Side? {
        if let lost { return lost.edge }
        if case .sliding(let edge) = tracked?.mode { return edge }
        return nil
    }

    /// True while a finger that may become a gesture is down.
    public var isTracking: Bool { tracked != nil }

    /// True while scrolling should be held back: during a slide, or while a finger on a
    /// slider may still become one (otherwise two fingers on a side edge scroll the page).
    public var blocksScrolling: Bool {
        if isSliding { return true }
        guard let tracked, tracked.isPending else { return false }
        return !tracked.slideSides.isEmpty
    }

    /// True when a slide lost its finger and `tick` must be called to finish it.
    public var needsTick: Bool { lost != nil }

    /// Ids of the touches currently treated as palms.
    public var palmIDs: Set<Int32> { palms }

    // MARK: Clicks

    /// True while a finger is down in a top section; tap-to-click clicks from it are swallowed.
    public var clickGuardDown: Bool {
        guard let tracked, tracked.isPending, let zone = tracked.tapZone else { return false }
        return zone.isTop
    }

    /// Until when clicks caused by the last section tap should be swallowed.
    public var clickGuardDeadline: Double { clickGuardUntil }

    /// Whether a click arriving now came from tapping a section and should be swallowed.
    public func shouldSuppressClick(at time: Double) -> Bool {
        clickGuardDown || time <= clickGuardUntil
    }

    /// Called for every mouse-down; a physical press in a bottom section is never treated as a tap.
    public func noteMouseDown(at time: Double) {
        tracked?.physicallyClicked = true
    }

    /// Called for every key press. A finger waiting to become a gesture is only a resting thumb or
    /// palm, and fingers landing in the next moment are too.
    public func noteKeyDown(at time: Double) {
        lastKeyDown = time
        if config.ignoreWhileTyping, let tracked, tracked.isPending { abandon(tracked) }
    }

    // MARK: Frames

    /// Feeds one frame of touches (all contacts the sensor currently reports).
    public func process(_ touches: [Touch], at time: Double) -> [GestureEvent] {
        var events = tick(at: time)

        let present = Set(touches.filter { $0.phase != .lifted }.map(\.id))
        ignored.formIntersection(present)
        palms.formIntersection(present)
        firstSeen = firstSeen.filter { present.contains($0.key) }
        for touch in touches where touch.phase == .touching {
            if firstSeen[touch.id] == nil { firstSeen[touch.id] = time }
            if isPalm(touch) { palms.insert(touch.id) }
        }
        let fingers = touches.filter { $0.phase == .touching && !palms.contains($0.id) }

        if let current = tracked {
            events += follow(current, touches: touches, fingers: fingers, at: time)
        }
        events += handleNewFingers(fingers, at: time)
        return events
    }

    /// Finishes a slide whose finger vanished without lifting, once the grace period is over.
    public func tick(at time: Double) -> [GestureEvent] {
        guard let lostSlide = lost, time - lostSlide.at > tuning.lostFingerGrace else { return [] }
        lost = nil
        return [.slideEnded(lostSlide.edge)]
    }

    /// Drops all state, ending a running slide.
    public func reset() -> [GestureEvent] {
        let edge = slidingEdge
        tracked = nil
        lost = nil
        ignored.removeAll()
        return edge.map { [.slideEnded($0)] } ?? []
    }

    // MARK: Zones

    /// A tap section's rectangle in normalized coordinates (y up), shared with the UI's trackpad map.
    public static func rect(of zone: TapZone, on surface: SurfaceSize, tuning: Tuning = Tuning()) -> (minX: Double, minY: Double, maxX: Double, maxY: Double) {
        let cornerW = tuning.cornerSizeMM / surface.widthMM
        let cornerH = tuning.cornerSizeMM / surface.heightMM
        let depth = tuning.zoneDepthMM / surface.heightMM
        let halfCenter = tuning.centerZoneWidthMM / 2 / surface.widthMM
        switch zone {
        case .topLeft: return (0, 1 - cornerH, cornerW, 1)
        case .topCenter: return (0.5 - halfCenter, 1 - depth, 0.5 + halfCenter, 1)
        case .topRight: return (1 - cornerW, 1 - cornerH, 1, 1)
        case .bottomLeft: return (0, 0, cornerW, cornerH)
        case .bottomCenter: return (0.5 - halfCenter, 0, 0.5 + halfCenter, depth)
        case .bottomRight: return (1 - cornerW, 0, 1, cornerH)
        }
    }

    /// A slider's rectangle in normalized coordinates (y up), shared with the UI's trackpad map.
    public static func sliderRect(_ side: Side, config: GestureConfig, on surface: SurfaceSize,
                                  tuning: Tuning = Tuning()) -> (minX: Double, minY: Double, maxX: Double, maxY: Double) {
        switch config.layout {
        case .sides:
            let top = config.activeArea.fraction
            return side == .left ? (0, 0, config.edgeWidth, top) : (1 - config.edgeWidth, 0, 1, top)
        case .top:
            let depth = min(0.3, config.edgeWidth * surface.widthMM / surface.heightMM)
            let halfGap = tuning.topGapMM / 2 / surface.widthMM
            return side == .left ? (0, 1 - depth, 0.5 - halfGap, 1) : (0.5 + halfGap, 1 - depth, 1, 1)
        }
    }

    private func tapZone(at touch: Touch) -> TapZone? {
        TapZone.allCases.first { zone in
            let r = Self.rect(of: zone, on: surface, tuning: tuning)
            return touch.x >= r.minX && touch.x <= r.maxX && touch.y >= r.minY && touch.y <= r.maxY
        }
    }

    /// Whether a touch is on a slider's strip. On the side edges that is anywhere along the edge;
    /// the active area only limits where a slide may start.
    private func onSlider(_ side: Side, _ touch: Touch) -> Bool {
        switch config.layout {
        case .sides:
            return side == .left ? touch.x <= config.edgeWidth : touch.x >= 1 - config.edgeWidth
        case .top:
            let r = Self.sliderRect(side, config: config, on: surface, tuning: tuning)
            return touch.x >= r.minX && touch.x <= r.maxX && touch.y >= r.minY
        }
    }

    /// Travel along the slider's axis and across it, in millimetres.
    private func alongAndAcross(dx: Double, dy: Double) -> (along: Double, across: Double) {
        let dxMM = dx * surface.widthMM, dyMM = dy * surface.heightMM
        return config.layout == .top ? (dxMM, dyMM) : (dyMM, dxMM)
    }

    private func kinds(for touch: Touch) -> Set<Kind> {
        var kinds = Set<Kind>()
        let mayStart = config.layout == .top || touch.y <= config.activeArea.fraction
        if config.leftEdge, mayStart, onSlider(.left, touch) { kinds.insert(.slide(.left)) }
        if config.rightEdge, mayStart, onSlider(.right, touch) { kinds.insert(.slide(.right)) }
        let bottomStrip = min(0.2, max(0.04, config.edgeWidth * surface.widthMM / surface.heightMM))
        if config.mediaStrip, touch.y <= bottomStrip { kinds.insert(.swipe) }
        if let zone = tapZone(at: touch), config.tapZones.contains(zone) { kinds.insert(.tap(zone)) }
        return kinds
    }

    private func isPalm(_ touch: Touch) -> Bool {
        touch.majorAxis >= tuning.palmMajorAxis || touch.size >= tuning.palmSize
    }

    // MARK: Tracking

    private func follow(_ current: Tracked, touches: [Touch], fingers: [Touch], at time: Double) -> [GestureEvent] {
        let touch = touches.first { $0.id == current.id }

        if palms.contains(current.id), current.isPending {
            abandon(current)
            return []
        }
        if let touch, touch.phase == .touching {
            return update(current, with: touch, at: time)
        }
        if let touch, touch.phase == .hovering {
            // The sensor briefly lost firm contact; hold the gesture until the finger is back or gone.
            if tracked?.hoverStart == nil { tracked?.hoverStart = time }
            return []
        }
        // Lifted or gone. During a slide, a second finger on the same edge can carry on.
        if case .sliding = current.mode, let sibling = fingers.first(where: { current.siblings.contains($0.id) }) {
            var next = current
            next.id = sibling.id
            next.siblings.remove(sibling.id)
            next.lastX = sibling.x
            next.lastY = sibling.y
            next.hoverStart = nil
            tracked = next
            return []
        }
        return lift(current, at: time, definitive: touch?.phase == .lifted, lastTouch: touch)
    }

    private func update(_ current: Tracked, with touch: Touch, at time: Double) -> [GestureEvent] {
        var current = current
        current.hoverStart = nil
        var events: [GestureEvent] = []
        let dxMM = (touch.x - current.startX) * surface.widthMM
        let dyMM = (touch.y - current.startY) * surface.heightMM
        let moved = hypot(dxMM, dyMM)

        switch current.mode {
        case .pending:
            if time - current.startTime > tuning.tapMaxDuration {
                // Too slow to be a tap; only motion gestures remain possible.
                current.kinds = current.kinds.filter { if case .tap = $0 { return false } else { return true } }
                if current.kinds.isEmpty {
                    abandon(current)
                    return events
                }
            }
            let travel = alongAndAcross(dx: touch.x - current.startX, dy: touch.y - current.startY)
            if let side = current.slideSides.first, abs(travel.along) >= tuning.slideStartMM, abs(travel.along) >= abs(travel.across) {
                current.mode = .sliding(side)
                events += [.slideBegan(side), .slideMoved(side, deltaMM: travel.along)]
            } else if current.kinds.contains(.swipe), abs(dxMM) >= tuning.slideStartMM, abs(dxMM) > abs(dyMM) {
                current.mode = .swiping(fired: false)
                events += swipe(&current, dxMM: dxMM)
            } else if moved >= tuning.rejectMM || (moved > tuning.tapMaxMoveMM && current.slideSides.isEmpty && !current.kinds.contains(.swipe)) {
                abandon(current)
                return events
            }
        case .sliding(let edge):
            let delta = alongAndAcross(dx: touch.x - current.lastX, dy: touch.y - current.lastY).along
            if delta != 0 { events.append(.slideMoved(edge, deltaMM: delta)) }
        case .swiping:
            events += swipe(&current, dxMM: dxMM)
        }
        current.lastX = touch.x
        current.lastY = touch.y
        tracked = current
        return events
    }

    private func handleNewFingers(_ fingers: [Touch], at time: Double) -> [GestureEvent] {
        var events: [GestureEvent] = []
        var fresh = fingers.filter {
            $0.id != tracked?.id && !(tracked?.siblings.contains($0.id) ?? false) && !ignored.contains($0.id)
        }
        guard !fresh.isEmpty else { return events }

        // A slide that lost its finger picks up a finger landing close by.
        if let lostSlide = lost {
            let last = (x: lostSlide.slide.lastX, y: lostSlide.slide.lastY)
            if let near = fresh.first(where: { distanceMM(from: last, to: $0) <= tuning.reacquireMM || onSlider(lostSlide.edge, $0) }) {
                var resumed = lostSlide.slide
                resumed.id = near.id
                resumed.lastX = near.x
                resumed.lastY = near.y
                resumed.hoverStart = nil
                tracked = resumed
                lost = nil
                ignored.formUnion(fresh.map(\.id).filter { $0 != near.id })
                return events
            }
            lost = nil
            events.append(.slideEnded(lostSlide.edge))
        }

        if var current = tracked {
            // Fingers landing on the same edge as a slide join it. The top strip is slid with one
            // finger; a second finger there is the start of a scroll.
            let sides = current.slideSides
            let joining = config.layout == .top ? [] : fresh.filter { finger in
                if case .sliding(let side) = current.mode { return onSlider(side, finger) }
                return current.isPending && sides.contains { onSlider($0, finger) }
            }
            current.siblings.formUnion(joining.map(\.id))
            tracked = current
            fresh.removeAll { finger in joining.contains { $0.id == finger.id } }
            if fresh.isEmpty { return events }

            let wasResting = current.isPending && time - current.startTime >= tuning.restingAfter
                && hypot((current.lastX - current.startX) * surface.widthMM, (current.lastY - current.startY) * surface.heightMM) < tuning.tapMaxMoveMM
            if !current.isPending || !wasResting {
                // Mid-gesture, a thumb or palm landing elsewhere is ignored. A second finger landing
                // right after the first, away from the edge, means a scroll or other system gesture.
                if current.isPending { abandon(current) }
                ignored.formUnion(fresh.map(\.id))
                return events
            }
            // The tracked finger was only resting there; let the new finger have a go.
            abandon(current)
        }

        // Start on the new finger(s) if every other finger is resting.
        let freshIDs = Set(fresh.map(\.id))
        let othersResting = fingers
            .filter { !freshIDs.contains($0.id) }
            .allSatisfy { time - (firstSeen[$0.id] ?? time) >= tuning.restingAfter }
        let primary = fresh[0]
        let sameEdge = config.layout == .sides && Side.allCases.contains { side in fresh.allSatisfy { onSlider(side, $0) } }
        if othersResting, fresh.count == 1 || sameEdge {
            begin(primary, siblings: Set(fresh.dropFirst().map(\.id)), at: time)
        } else {
            ignored.formUnion(freshIDs)
        }
        return events
    }

    private func begin(_ touch: Touch, siblings: Set<Int32>, at time: Double) {
        var kinds = kinds(for: touch)
        if !siblings.isEmpty {
            // Two fingers together only make sense as a slide.
            kinds = kinds.filter { if case .slide = $0 { return true } else { return false } }
        }
        let typing = config.ignoreWhileTyping && time - lastKeyDown < tuning.typingGuard
        guard !kinds.isEmpty, !typing, gesturesAllowed() else {
            ignored.insert(touch.id)
            ignored.formUnion(siblings)
            return
        }
        tracked = Tracked(id: touch.id, siblings: siblings, startX: touch.x, startY: touch.y,
                          lastX: touch.x, lastY: touch.y, startTime: time, kinds: kinds, mode: .pending)
    }

    private func swipe(_ current: inout Tracked, dxMM: Double) -> [GestureEvent] {
        guard case .swiping(fired: false) = current.mode, abs(dxMM) >= tuning.swipeTriggerMM else { return [] }
        current.mode = .swiping(fired: true)
        return [.mediaSwipe(forward: dxMM > 0)]
    }

    private func lift(_ current: Tracked, at time: Double, definitive: Bool, lastTouch: Touch?) -> [GestureEvent] {
        tracked = nil
        ignored.formUnion(current.siblings)
        switch current.mode {
        case .sliding(let edge):
            if definitive { return [.slideEnded(edge)] }
            // The trackpad sometimes drops a finger mid-slide; give it a moment to come back.
            lost = (current, edge, time)
            return []
        case .swiping:
            return []
        case .pending:
            guard let zone = current.tapZone else { return [] }
            let liftTime = current.hoverStart ?? time
            let moved = hypot((current.lastX - current.startX) * surface.widthMM,
                              (current.lastY - current.startY) * surface.heightMM)
            let isTap = liftTime - current.startTime <= tuning.tapMaxDuration && moved <= tuning.tapMaxMoveMM
            if zone.isTop {
                // Top sections swallow clicks while touched and just after.
                clickGuardUntil = time + tuning.clickGuardAfterLift
            } else {
                // People click along the bottom, so a real press there is never a tap.
                guard isTap, !current.physicallyClicked else { return [] }
                clickGuardUntil = time + tuning.clickGuardAfterLift
            }
            return isTap ? registerTap(zone, at: time) : []
        }
    }

    private func registerTap(_ zone: TapZone, at time: Double) -> [GestureEvent] {
        if let previous = lastTap, previous.zone == zone, time - previous.time <= tuning.doubleTapWindow {
            lastTap = nil
            return [.doubleTap(zone)]
        }
        lastTap = (zone, time)
        return []
    }

    private func abandon(_ current: Tracked) {
        tracked = nil
        ignored.insert(current.id)
        ignored.formUnion(current.siblings)
    }

    private func distanceMM(from point: (x: Double, y: Double), to touch: Touch) -> Double {
        hypot((touch.x - point.x) * surface.widthMM, (touch.y - point.y) * surface.heightMM)
    }
}
