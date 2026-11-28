import Testing
@testable import MetalDuckKit

@Suite struct CadenceTrackerTests {
    /// 24 fps video shown by a browser a little early or late each frame.
    @Test func locksOntoJitteredVideoAndEvensItOut() {
        var tracker = CadenceTracker()
        let period = 1.0 / 24.0
        let jitter = [0.0, 0.006, -0.005, 0.004, -0.006, 0.005, -0.003, 0.002]
        var times: [Double] = []
        for index in 0..<60 {
            let raw = 10.0 + Double(index) * period + jitter[index % jitter.count]
            times.append(tracker.time(for: raw))
        }
        #expect(tracker.isLocked)
        #expect(abs(tracker.period - period) < 0.001)
        // Once locked, the steps between frames are far steadier than the raw stamps.
        let steps = zip(times.dropFirst(40), times.dropFirst(39)).map { $0 - $1 }
        for step in steps {
            #expect(abs(step - period) < 0.002)
        }
    }

    @Test func doesNotLockOntoAnIrregularSource() {
        var tracker = CadenceTracker()
        let gaps = [0.010, 0.031, 0.017, 0.044, 0.012, 0.038, 0.021, 0.009, 0.047, 0.015]
        var raw = 5.0
        for index in 0..<50 {
            raw += gaps[index % gaps.count]
            _ = tracker.time(for: raw)
        }
        #expect(!tracker.isLocked)
    }

    @Test func timesNeverGoBackwards() {
        var tracker = CadenceTracker()
        var last = -Double.infinity
        let raws = [1.0, 1.04, 1.039, 1.08, 1.5, 1.54, 1.58, 1.581, 1.62]
        for raw in raws {
            let time = tracker.time(for: raw)
            #expect(time > last)
            last = time
        }
    }

    @Test func aLongGapStartsTheBeatAgain() {
        var tracker = CadenceTracker()
        for index in 0..<30 {
            _ = tracker.time(for: 2.0 + Double(index) / 30.0)
        }
        #expect(tracker.isLocked)
        _ = tracker.time(for: 10.0)
        #expect(!tracker.isLocked)
    }
}
