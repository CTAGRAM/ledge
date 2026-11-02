import AppKit
import LedgePrivate

/// Holds the pointer still (and hidden) during a slide, keeps pages from scrolling
/// under a slide, and swallows the tap-to-click clicks that section taps would produce.
///
/// The event tap runs on its own thread so pointer movement never waits for the UI.
/// Needs Accessibility access.
final class PointerControl {
    /// Called on the main thread for every left mouse-down.
    var onMouseDown: () -> Void = {}

    var hidesPointer = true

    private struct Shared {
        var frozen = false
        var blockScrolling = false
        var sliding = false
        var scrollBlockUntil = 0.0
        /// The last scroll gesture was swallowed, so its momentum must be too.
        var swallowedScrollGesture = false
        var clickGuardDown = false
        var clickGuardUntil = 0.0
        var swallowingClick = false
    }

    private let shared = Locked(Shared())
    private var anchor: CGPoint?
    private var pointerHidden = false
    private var tap: CFMachPort?

    var isFrozen: Bool { shared.read { $0.frozen } }

    init() {
        // Lets a background app hide the pointer.
        let connection = SLSMainConnectionID()
        _ = SLSSetConnectionProperty(connection, connection, "SetsCursorInBackground" as CFString, kCFBooleanTrue)
    }

    /// Installs the event tap. Fails without Accessibility access.
    @discardableResult
    func start() -> Bool {
        guard tap == nil else { return true }
        var mask = CGEventMask(0)
        for type in [CGEventType.mouseMoved, .leftMouseDragged, .rightMouseDragged, .leftMouseDown, .leftMouseUp, .scrollWheel] {
            mask |= 1 << type.rawValue
        }
        mask |= 1 << 29 // NSEventTypeGesture: trackpad swipes and pinches
        let refcon = Unmanaged.passUnretained(self).toOpaque()
        guard let tap = CGEvent.tapCreate(tap: .cghidEventTap, place: .headInsertEventTap, options: .defaultTap,
                                          eventsOfInterest: mask, callback: eventTapCallback, userInfo: refcon) else {
            return false
        }
        self.tap = tap
        let thread = Thread {
            let source = CFMachPortCreateRunLoopSource(nil, tap, 0)
            CFRunLoopAddSource(CFRunLoopGetCurrent(), source, .commonModes)
            CGEvent.tapEnable(tap: tap, enable: true)
            CFRunLoopRun()
        }
        thread.name = "Ledge event tap"
        thread.qualityOfService = .userInteractive
        thread.start()
        return true
    }

    func stop() {
        unfreeze()
        if let tap { CFMachPortInvalidate(tap) } // also ends the tap thread's run loop
        tap = nil
    }

    /// Current pointer position in global (top-left origin) coordinates.
    static var location: CGPoint { CGEvent(source: nil)?.location ?? .zero }

    /// Pins the pointer to `point` until `unfreeze()`.
    func freeze(at point: CGPoint) {
        guard !isFrozen else { return }
        shared.write { $0.frozen = true }
        anchor = point
        if hidesPointer, !pointerHidden {
            CGDisplayHideCursor(CGMainDisplayID())
            pointerHidden = true
        }
    }

    func unfreeze() {
        guard isFrozen else { return }
        shared.write { $0.frozen = false }
        if let anchor {
            CGWarpMouseCursorPosition(anchor)
            // Re-associating right after a warp removes the short input freeze a warp normally causes.
            CGAssociateMouseAndMouseCursorPosition(1)
        }
        anchor = nil
        if pointerHidden {
            CGDisplayShowCursor(CGMainDisplayID())
            pointerHidden = false
        }
    }

    /// Called after every touch frame with what the gesture recognizers currently want.
    func update(blockScrolling: Bool, sliding: Bool, clickGuardDown: Bool, clickGuardUntil: Double) {
        shared.write { state in
            if state.sliding, !sliding, state.blockScrolling {
                // Keep blocking briefly so a flick at the end of a slide doesn't scroll the page.
                state.scrollBlockUntil = ProcessInfo.processInfo.systemUptime + 0.3
            }
            state.sliding = sliding
            state.blockScrolling = blockScrolling
            state.clickGuardDown = clickGuardDown
            state.clickGuardUntil = clickGuardUntil
        }
    }

    // MARK: Event tap (runs on the tap thread)

    fileprivate func handle(_ type: CGEventType, _ event: CGEvent) -> Unmanaged<CGEvent>? {
        let pass = Unmanaged.passUnretained(event)
        switch type {
        case .tapDisabledByTimeout, .tapDisabledByUserInput:
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            return pass
        case .mouseMoved, .leftMouseDragged, .rightMouseDragged:
            return shared.read { $0.frozen } ? nil : pass
        case .scrollWheel:
            return shouldSwallowScroll(event) ? nil : pass
        case .leftMouseDown:
            DispatchQueue.main.async { [weak self] in self?.onMouseDown() }
            let now = ProcessInfo.processInfo.systemUptime
            let swallow = shared.write { state -> Bool in
                state.swallowingClick = state.clickGuardDown || now <= state.clickGuardUntil
                return state.swallowingClick
            }
            return swallow ? nil : pass
        case .leftMouseUp:
            let swallow = shared.write { state -> Bool in
                defer { state.swallowingClick = false }
                return state.swallowingClick
            }
            return swallow ? nil : pass
        default:
            if type.rawValue == 29 { return shared.read { $0.blockScrolling || $0.frozen } ? nil : pass }
            return pass
        }
    }

    private func shouldSwallowScroll(_ event: CGEvent) -> Bool {
        let phase = event.getIntegerValueField(.scrollWheelEventScrollPhase)
        let momentum = event.getIntegerValueField(.scrollWheelEventMomentumPhase)
        let now = ProcessInfo.processInfo.systemUptime
        return shared.write { state in
            if state.blockScrolling || state.frozen || now <= state.scrollBlockUntil {
                if phase != 0 { state.swallowedScrollGesture = true }
                return true
            }
            if momentum != 0 { return state.swallowedScrollGesture }
            if phase == 1 || phase == 128 { state.swallowedScrollGesture = false } // a fresh scroll began
            return false
        }
    }
}

private let eventTapCallback: CGEventTapCallBack = { _, type, event, refcon in
    guard let refcon else { return Unmanaged.passUnretained(event) }
    return Unmanaged<PointerControl>.fromOpaque(refcon).takeUnretainedValue().handle(type, event)
}

/// A value shared between threads.
final class Locked<Value> {
    private var value: Value
    private let lock = NSLock()

    init(_ value: Value) { self.value = value }

    func read<T>(_ body: (Value) -> T) -> T {
        lock.lock()
        defer { lock.unlock() }
        return body(value)
    }

    @discardableResult
    func write<T>(_ body: (inout Value) -> T) -> T {
        lock.lock()
        defer { lock.unlock() }
        return body(&value)
    }
}
