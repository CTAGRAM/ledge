import XCTest
@testable import LedgeCore

final class EdgeGestureRecognizerTests: XCTestCase {
    private let surface = SurfaceSize(widthMM: 100, heightMM: 100)

    private func recognizer(_ configure: (inout GestureConfig) -> Void = { _ in }) -> EdgeGestureRecognizer {
        var config = GestureConfig()
        configure(&config)
        return EdgeGestureRecognizer(config: config, surface: surface)
    }

    /// Plays a single-finger path and returns every event.
    private func play(_ r: EdgeGestureRecognizer, id: Int32 = 1, _ points: [(Double, Double)], start: Double = 0,
                      step: Double = 0.01, lift: Bool = true, others: [Touch] = []) -> [GestureEvent] {
        var events: [GestureEvent] = []
        var t = start
        for (x, y) in points {
            events += r.process([Touch(id: id, x: x, y: y)] + others, at: t)
            t += step
        }
        if lift, let last = points.last {
            events += r.process([Touch(id: id, x: last.0, y: last.1, phase: .lifted)] + others, at: t)
            events += r.process(others, at: t + step)
        }
        return events
    }

    private func slideTotal(_ events: [GestureEvent]) -> Double {
        events.reduce(0) { total, event in
            if case .slideMoved(_, let delta) = event { return total + delta }
            return total
        }
    }

    // MARK: Slides

    func testRightEdgeSlideUp() {
        let r = recognizer()
        let events = play(r, [(0.98, 0.3), (0.98, 0.32), (0.98, 0.4), (0.97, 0.5)])
        XCTAssertEqual(events.first, .slideBegan(.right))
        XCTAssertEqual(events.last, .slideEnded(.right))
        XCTAssertEqual(slideTotal(events), 20, accuracy: 0.001)
    }

    func testLeftEdgeSlideDown() {
        let r = recognizer()
        let events = play(r, [(0.0, 0.8), (0.0, 0.75), (0.01, 0.6)])
        XCTAssertEqual(events.first, .slideBegan(.left))
        XCTAssertEqual(slideTotal(events), -20, accuracy: 0.001)
    }

    func testSlideStartsAfterOneMillimetre() {
        let r = recognizer()
        XCTAssertEqual(r.process([Touch(id: 1, x: 0.98, y: 0.3)], at: 0), [])
        XCTAssertEqual(r.process([Touch(id: 1, x: 0.98, y: 0.311)], at: 0.01).first, .slideBegan(.right))
    }

    func testPointerMovementFromCenterIsIgnored() {
        let r = recognizer()
        XCTAssertEqual(play(r, [(0.5, 0.5), (0.5, 0.6), (0.5, 0.7)]), [])
    }

    func testHorizontalMoveAwayFromEdgeIsNotASlide() {
        let r = recognizer()
        XCTAssertEqual(play(r, [(0.98, 0.5), (0.95, 0.5), (0.9, 0.51), (0.9, 0.7)]), [])
    }

    func testSlideKeepsGoingWhenFingerDriftsInward() {
        let r = recognizer()
        let events = play(r, [(0.98, 0.2), (0.98, 0.25), (0.8, 0.5)])
        XCTAssertEqual(slideTotal(events), 30, accuracy: 0.001)
    }

    func testActiveAreaBlocksSlidesStartingHigh() {
        let r = recognizer { $0.activeArea = .bottomQuarter }
        XCTAssertEqual(play(r, [(0.98, 0.6), (0.98, 0.7)]), [])
        XCTAssertEqual(play(r, id: 2, [(0.98, 0.2), (0.98, 0.3)], start: 1).first, .slideBegan(.right))
    }

    func testDisabledEdgeDoesNothing() {
        let r = recognizer { $0.leftEdge = false }
        XCTAssertEqual(play(r, [(0.02, 0.3), (0.02, 0.6)]), [])
    }

    // MARK: Palms, resting fingers and two-finger slides

    func testSlideWorksWithAPalmOnTheTrackpad() {
        let r = recognizer()
        let palm = Touch(id: 9, x: 0.4, y: 0.1, majorAxis: 24, size: 3)
        _ = r.process([palm], at: 0)
        let events = play(r, [(0.02, 0.3), (0.02, 0.4), (0.02, 0.5)], start: 0.01, others: [palm])
        XCTAssertEqual(events.first, .slideBegan(.left))
        XCTAssertEqual(slideTotal(events), 20, accuracy: 0.001)
    }

    func testPalmOnTheEdgeDoesNotSlide() {
        let r = recognizer()
        let events = r.process([Touch(id: 1, x: 0.02, y: 0.3, majorAxis: 22)], at: 0)
            + r.process([Touch(id: 1, x: 0.02, y: 0.5, majorAxis: 22)], at: 0.01)
        XCTAssertEqual(events, [])
    }

    func testSlideWorksWithARestingThumb() {
        let r = recognizer()
        let thumb = Touch(id: 5, x: 0.4, y: 0.3)
        _ = r.process([thumb], at: 0)
        let events = play(r, [(0.98, 0.3), (0.98, 0.4)], start: 0.5, others: [thumb])
        XCTAssertEqual(events.first, .slideBegan(.right))
    }

    func testTwoFingersSlidingTogetherOnTheEdge() {
        let r = recognizer()
        var events: [GestureEvent] = []
        for (t, y) in [(0.0, 0.3), (0.01, 0.35), (0.02, 0.45)] {
            events += r.process([Touch(id: 1, x: 0.0, y: y), Touch(id: 2, x: 0.01, y: y - 0.25)], at: t)
        }
        XCTAssertEqual(events.first, .slideBegan(.left))
        XCTAssertEqual(slideTotal(events), 15, accuracy: 0.001)
        XCTAssertTrue(r.blocksScrolling)
    }

    func testSecondEdgeFingerJoinsAndTakesOverWhenFirstLifts() {
        let r = recognizer()
        _ = r.process([Touch(id: 1, x: 0.0, y: 0.5)], at: 0)
        _ = r.process([Touch(id: 1, x: 0.0, y: 0.5), Touch(id: 2, x: 0.0, y: 0.25)], at: 0.01)
        _ = r.process([Touch(id: 1, x: 0.0, y: 0.6), Touch(id: 2, x: 0.0, y: 0.35)], at: 0.02)
        let events = r.process([Touch(id: 2, x: 0.0, y: 0.4)], at: 0.03)
            + r.process([Touch(id: 2, x: 0.0, y: 0.5)], at: 0.04)
        XCTAssertEqual(slideTotal(events), 10, accuracy: 0.001)
        XCTAssertTrue(r.isSliding)
    }

    func testTwoFingerScrollAwayFromEdgeIsLeftAlone() {
        let r = recognizer()
        var events: [GestureEvent] = []
        events += r.process([Touch(id: 1, x: 0.97, y: 0.5)], at: 0)
        events += r.process([Touch(id: 1, x: 0.97, y: 0.5), Touch(id: 2, x: 0.8, y: 0.5)], at: 0.02)
        events += r.process([Touch(id: 1, x: 0.97, y: 0.7), Touch(id: 2, x: 0.8, y: 0.7)], at: 0.04)
        XCTAssertEqual(events, [])
        XCTAssertFalse(r.blocksScrolling)
    }

    func testFingerLandingRightAfterAnotherIsIgnored() {
        let r = recognizer()
        _ = r.process([Touch(id: 1, x: 0.5, y: 0.5)], at: 0)
        let events = r.process([Touch(id: 1, x: 0.5, y: 0.5), Touch(id: 2, x: 0.98, y: 0.3)], at: 0.05)
            + r.process([Touch(id: 1, x: 0.5, y: 0.6), Touch(id: 2, x: 0.98, y: 0.6)], at: 0.06)
        XCTAssertEqual(events, [])
    }

    func testRestingThumbDoesNotStopRunningSlide() {
        let r = recognizer()
        _ = play(r, [(0.98, 0.3), (0.98, 0.35)], lift: false)
        let events = r.process([Touch(id: 1, x: 0.98, y: 0.4), Touch(id: 2, x: 0.3, y: 0.05)], at: 0.1)
        XCTAssertEqual(slideTotal(events), 5, accuracy: 0.001)
        XCTAssertTrue(r.isSliding)
    }

    func testFingerRestingInAZoneDoesNotBlockTheEdge() {
        let r = recognizer { $0.tapZones = [.bottomCenter] }
        let thumb = Touch(id: 5, x: 0.5, y: 0.03)
        _ = r.process([thumb], at: 0)
        _ = r.process([thumb], at: 0.4)
        let events = play(r, [(0.98, 0.3), (0.98, 0.4)], start: 0.5, others: [thumb])
        XCTAssertEqual(events.first, .slideBegan(.right))
    }

    // MARK: Sensor glitches

    func testBriefLossOfContactDoesNotEndTheSlide() {
        let r = recognizer()
        _ = play(r, [(0.98, 0.3), (0.98, 0.4)], lift: false)
        XCTAssertEqual(r.process([Touch(id: 1, x: 0.98, y: 0.4, phase: .hovering)], at: 0.05), [])
        let events = r.process([Touch(id: 1, x: 0.98, y: 0.45)], at: 0.06)
        XCTAssertEqual(slideTotal(events), 5, accuracy: 0.001)
        XCTAssertTrue(r.isSliding)
    }

    func testLostFingerIsPickedBackUp() {
        let r = recognizer()
        _ = play(r, [(0.98, 0.3), (0.98, 0.4)], lift: false)
        XCTAssertEqual(r.process([], at: 0.05), [])
        XCTAssertTrue(r.isSliding)
        let events = r.process([Touch(id: 7, x: 0.97, y: 0.42)], at: 0.1)
            + r.process([Touch(id: 7, x: 0.97, y: 0.5)], at: 0.11)
        XCTAssertEqual(slideTotal(events), 8, accuracy: 0.001)
        XCTAssertFalse(events.contains(.slideEnded(.right)))
    }

    func testLostFingerEndsSlideAfterGrace() {
        let r = recognizer()
        _ = play(r, [(0.98, 0.3), (0.98, 0.4)], lift: false)
        XCTAssertEqual(r.process([], at: 0.05), [])
        XCTAssertTrue(r.needsTick)
        XCTAssertEqual(r.tick(at: 0.1), [])
        XCTAssertEqual(r.tick(at: 0.5), [.slideEnded(.right)])
        XCTAssertFalse(r.isSliding)
    }

    func testNewFingerFarAwayEndsALostSlide() {
        let r = recognizer()
        _ = play(r, [(0.98, 0.3), (0.98, 0.4)], lift: false)
        _ = r.process([], at: 0.05)
        XCTAssertEqual(r.process([Touch(id: 8, x: 0.4, y: 0.5)], at: 0.08), [.slideEnded(.right)])
    }

    // MARK: Media strip

    func testMediaSwipeFiresOnce() {
        let r = recognizer()
        let events = play(r, [(0.4, 0.03), (0.45, 0.03), (0.55, 0.03), (0.7, 0.04)])
        XCTAssertEqual(events, [.mediaSwipe(forward: true)])
        XCTAssertEqual(play(r, id: 2, [(0.6, 0.03), (0.5, 0.03), (0.4, 0.03)], start: 1), [.mediaSwipe(forward: false)])
    }

    func testMediaSwipeNeedsEnoughTravel() {
        let r = recognizer()
        XCTAssertEqual(play(r, [(0.4, 0.03), (0.45, 0.03)]), [])
    }

    // MARK: Tap sections

    func testTopRightDoubleTap() {
        let r = recognizer()
        XCTAssertEqual(play(r, id: 1, [(0.95, 0.95), (0.95, 0.95)], start: 0), [])
        XCTAssertEqual(play(r, id: 2, [(0.94, 0.96), (0.94, 0.96)], start: 0.15), [.doubleTap(.topRight)])
    }

    func testEverySectionCanBeTapped() {
        let points: [TapZone: (Double, Double)] = [
            .topLeft: (0.05, 0.95), .topCenter: (0.5, 0.95), .topRight: (0.95, 0.95),
            .bottomLeft: (0.05, 0.05), .bottomCenter: (0.5, 0.05), .bottomRight: (0.95, 0.05),
        ]
        for (zone, point) in points {
            let r = recognizer { $0.tapZones = Set(TapZone.allCases) }
            _ = play(r, id: 1, [point], start: 0)
            XCTAssertEqual(play(r, id: 2, [point], start: 0.15), [.doubleTap(zone)], "\(zone)")
        }
    }

    func testSectionWithoutActionDoesNothing() {
        let r = recognizer { $0.tapZones = [] }
        _ = play(r, id: 1, [(0.95, 0.95)], start: 0)
        XCTAssertEqual(play(r, id: 2, [(0.95, 0.95)], start: 0.15), [])
    }

    func testSlowSecondTapIsNotADoubleTap() {
        let r = recognizer()
        XCTAssertEqual(play(r, id: 1, [(0.95, 0.95)], start: 0), [])
        XCTAssertEqual(play(r, id: 2, [(0.95, 0.95)], start: 1.0), [])
    }

    func testLongPressIsNotATap() {
        let r = recognizer()
        XCTAssertEqual(play(r, id: 1, [(0.95, 0.95)], start: 0, step: 0.5), [])
        XCTAssertEqual(play(r, id: 2, [(0.95, 0.95)], start: 1.1, step: 0.5), [])
    }

    func testPhysicalClickInBottomSectionIsNotATap() {
        let r = recognizer { $0.tapZones = [.bottomCenter] }
        _ = play(r, id: 1, [(0.5, 0.03)], start: 0)
        _ = r.process([Touch(id: 2, x: 0.5, y: 0.03)], at: 0.15)
        r.noteMouseDown(at: 0.16)
        let events = r.process([Touch(id: 2, x: 0.5, y: 0.03, phase: .lifted)], at: 0.2)
        XCTAssertEqual(events, [])
        XCTAssertFalse(r.shouldSuppressClick(at: 0.4)) // the real press did not extend the first tap's guard
    }

    func testBottomSectionDoubleTap() {
        let r = recognizer { $0.tapZones = [.bottomCenter] }
        XCTAssertEqual(play(r, id: 1, [(0.5, 0.03)], start: 0), [])
        XCTAssertEqual(play(r, id: 2, [(0.5, 0.03)], start: 0.15), [.doubleTap(.bottomCenter)])
    }

    func testTopSectionSuppressesTapClicks() {
        let r = recognizer()
        _ = r.process([Touch(id: 1, x: 0.95, y: 0.95)], at: 0)
        XCTAssertTrue(r.shouldSuppressClick(at: 0.05))
        _ = r.process([Touch(id: 1, x: 0.95, y: 0.95, phase: .lifted)], at: 0.1)
        XCTAssertTrue(r.shouldSuppressClick(at: 0.3))
        XCTAssertFalse(r.shouldSuppressClick(at: 1))
    }

    func testCentreTouchNeverSuppressesClicks() {
        let r = recognizer()
        _ = r.process([Touch(id: 1, x: 0.5, y: 0.5)], at: 0)
        XCTAssertFalse(r.shouldSuppressClick(at: 0.05))
    }

    func testSlideFromCornerStillWorks() {
        let r = recognizer()
        let events = play(r, [(0.97, 0.95), (0.97, 0.9), (0.97, 0.7)])
        XCTAssertEqual(events.first, .slideBegan(.right))
        XCTAssertFalse(r.shouldSuppressClick(at: 10))
    }

    // MARK: Misc

    func testModifierRequirement() {
        let r = recognizer()
        r.gesturesAllowed = { false }
        XCTAssertEqual(play(r, [(0.98, 0.3), (0.98, 0.6)]), [])
        r.gesturesAllowed = { true }
        XCTAssertEqual(play(r, id: 2, [(0.98, 0.3), (0.98, 0.6)], start: 1).first, .slideBegan(.right))
    }

    func testResetEndsSlide() {
        let r = recognizer()
        _ = play(r, [(0.98, 0.3), (0.98, 0.4)], lift: false)
        XCTAssertEqual(r.reset(), [.slideEnded(.right)])
        XCTAssertFalse(r.isSliding)
    }

    func testZoneRectsStayInsideTheSurface() {
        for zone in TapZone.allCases {
            let r = EdgeGestureRecognizer.rect(of: zone, on: .fallback)
            XCTAssertTrue(r.minX >= 0 && r.maxX <= 1 && r.minY >= 0 && r.maxY <= 1 && r.minX < r.maxX && r.minY < r.maxY, "\(zone)")
        }
    }
}

final class StepAccumulatorTests: XCTestCase {
    func testStepsLikeTheKeyboard() {
        var acc = StepAccumulator(start: 0.5)
        XCTAssertNil(acc.apply(delta: 0.02, steps: 16))
        XCTAssertEqual(acc.apply(delta: 0.02, steps: 16), 0.5625)
    }

    func testSmoothStepsRespondImmediately() {
        var acc = StepAccumulator(start: 0.5)
        XCTAssertEqual(acc.apply(delta: 0.006, steps: 100)!, 0.51, accuracy: 0.0001)
    }

    func testNeverStepsAgainstTravel() {
        var acc = StepAccumulator(start: 0.53)
        XCTAssertNil(acc.apply(delta: 0.0001, steps: 16))
        XCTAssertEqual(acc.apply(delta: -0.02, steps: 16), 0.5)
    }

    func testQuarterSteps() {
        var acc = StepAccumulator(start: 0.5)
        XCTAssertEqual(acc.apply(delta: 0.01, steps: 64), 0.515625)
    }

    func testClampsAndReversesImmediately() {
        var acc = StepAccumulator(start: 0.95)
        XCTAssertEqual(acc.apply(delta: 0.5, steps: 16), 1)
        XCTAssertNil(acc.apply(delta: 0.5, steps: 16))
        XCTAssertEqual(acc.apply(delta: -0.04, steps: 16), 0.9375)
    }

    func testReachesZero() {
        var acc = StepAccumulator(start: 0.1)
        XCTAssertEqual(acc.apply(delta: -1, steps: 16), 0)
    }
}
