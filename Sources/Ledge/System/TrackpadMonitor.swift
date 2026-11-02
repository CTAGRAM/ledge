import AppKit
import IOKit
import LedgeCore
import LedgePrivate

/// A multitouch surface Ledge listens to.
struct TrackpadDevice {
    let ref: MTDeviceRef
    let multitouchID: UInt64
    let familyID: Int32
    let isBuiltIn: Bool
    let surface: SurfaceSize

    var key: UInt { UInt(bitPattern: ref) }
}

/// Streams raw touches from every trackpad (built-in and Magic Trackpad) to the main thread,
/// and picks devices back up after sleep or when one is plugged in.
final class TrackpadMonitor {
    static let shared = TrackpadMonitor()

    /// Called on the main thread with every frame of touches.
    var onFrame: ((TrackpadDevice, [Touch]) -> Void)?
    /// Called on the main thread whenever the device list changes.
    var onDevicesChanged: (([TrackpadDevice]) -> Void)?

    private(set) var devices: [TrackpadDevice] = []
    private var deviceList: CFMutableArray?
    private var devicesByKey: [UInt: TrackpadDevice] = [:]
    private var notifyPort: IONotificationPortRef?
    private var restartWork: DispatchWorkItem?

    /// Magic Mouse surfaces also show up as multitouch devices; they are not trackpads.
    private static let mouseFamilies: Set<Int32> = [112, 113, 114]

    func start() {
        stop()
        guard let list = MTDeviceCreateList()?.takeRetainedValue() else { return }
        deviceList = list
        var found: [TrackpadDevice] = []
        for index in 0..<CFArrayGetCount(list) {
            guard let raw = CFArrayGetValueAtIndex(list, index) else { continue }
            let ref = MTDeviceRef(mutating: raw)
            var family: Int32 = 0
            MTDeviceGetFamilyID(ref, &family)
            guard !Self.mouseFamilies.contains(family) else { continue }
            var id: UInt64 = 0
            MTDeviceGetDeviceID(ref, &id)
            var width: Int32 = 0, height: Int32 = 0
            MTDeviceGetSensorSurfaceDimensions(ref, &width, &height)
            let surface = width > 0 && height > 0
                ? SurfaceSize(widthMM: Double(width) / 100, heightMM: Double(height) / 100)
                : .fallback
            let device = TrackpadDevice(ref: ref, multitouchID: id, familyID: family,
                                        isBuiltIn: MTDeviceIsBuiltIn(ref), surface: surface)
            MTRegisterContactFrameCallback(ref, contactCallback)
            MTDeviceStart(ref, 0)
            found.append(device)
        }
        devices = found
        devicesByKey = Dictionary(uniqueKeysWithValues: found.map { ($0.key, $0) })
        onDevicesChanged?(found)
    }

    func stop() {
        for device in devices {
            MTUnregisterContactFrameCallback(device.ref, contactCallback)
            MTDeviceStop(device.ref)
        }
        devices = []
        devicesByKey = [:]
        deviceList = nil
    }

    /// Restarts shortly after wake or a hot-plug, coalescing bursts of notifications.
    func scheduleRestart(after delay: TimeInterval = 1.0) {
        restartWork?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.start() }
        restartWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }

    /// Watches for wake from sleep and for multitouch devices appearing or going away.
    func watchForChanges() {
        let center = NSWorkspace.shared.notificationCenter
        center.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            self?.scheduleRestart(after: 1.5)
        }
        center.addObserver(forName: NSWorkspace.screensDidWakeNotification, object: nil, queue: .main) { [weak self] _ in
            self?.scheduleRestart(after: 1.0)
        }

        guard let port = IONotificationPortCreate(kIOMainPortDefault) else { return }
        notifyPort = port
        CFRunLoopAddSource(CFRunLoopGetMain(), IONotificationPortGetRunLoopSource(port).takeUnretainedValue(), .defaultMode)
        let refcon = Unmanaged.passUnretained(self).toOpaque()
        for type in [kIOFirstMatchNotification, kIOTerminatedNotification] {
            var iterator: io_iterator_t = 0
            let callback: IOServiceMatchingCallback = { refcon, iterator in
                drain(iterator)
                guard let refcon else { return }
                Unmanaged<TrackpadMonitor>.fromOpaque(refcon).takeUnretainedValue().scheduleRestart()
            }
            IOServiceAddMatchingNotification(port, type, IOServiceMatching("AppleMultitouchDevice"), callback, refcon, &iterator)
            drain(iterator) // arms the notification; existing devices are already running
        }
    }

    fileprivate func deliver(deviceKey: UInt, touches: [Touch]) {
        guard let device = devicesByKey[deviceKey] else { return }
        onFrame?(device, touches)
    }
}

private func drain(_ iterator: io_iterator_t) {
    while case let service = IOIteratorNext(iterator), service != 0 {
        IOObjectRelease(service)
    }
}

/// Runs on MultitouchSupport's thread; copies the touches and hops to the main thread.
private let contactCallback: MTContactCallbackFunction = { device, touches, count, _, _ in
    guard let device else { return 0 }
    var frame: [Touch] = []
    if let touches, count > 0 {
        frame.reserveCapacity(Int(count))
        for index in 0..<Int(count) {
            let touch = touches[index]
            let phase: Touch.Phase
            switch touch.state {
            case 3, 4: phase = .touching          // make-touch, touching
            case 1, 2, 5, 6: phase = .hovering    // approaching, hovering, breaking, lingering
            case 7: phase = .lifted               // out of range
            default: continue
            }
            frame.append(Touch(id: touch.identifier,
                               x: Double(touch.normalized.position.x),
                               y: Double(touch.normalized.position.y),
                               phase: phase,
                               majorAxis: Double(touch.majorAxis),
                               size: Double(touch.zTotal)))
        }
    }
    let key = UInt(bitPattern: device)
    DispatchQueue.main.async {
        TrackpadMonitor.shared.deliver(deviceKey: key, touches: frame)
    }
    return 0
}
