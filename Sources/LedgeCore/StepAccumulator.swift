import Foundation

/// Turns continuous finger travel into stepped values, like the keyboard keys:
/// 16 steps normally, 64 ("quarter steps") for fine control.
public struct StepAccumulator {
    public private(set) var raw: Double
    public private(set) var value: Double

    public init(start: Double) {
        raw = Self.clamp(start)
        value = raw
    }

    /// Adds `delta` (fraction of the full range) and returns the new value when it lands on a new step.
    public mutating func apply(delta: Double, steps: Int) -> Double? {
        guard delta != 0, steps > 0 else { return nil }
        raw = Self.clamp(raw + delta)
        let stepped = (raw * Double(steps)).rounded() / Double(steps)
        // Never step against the direction of travel (e.g. snapping 0.53 down to 0.5 while moving up).
        guard stepped != value, (stepped > value) == (delta > 0) else { return nil }
        value = stepped
        return stepped
    }

    private static func clamp(_ x: Double) -> Double { min(1, max(0, x)) }
}
