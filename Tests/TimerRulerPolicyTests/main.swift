import Foundation

private func expectEqual<T: Equatable>(_ actual: T, _ expected: T, _ message: String) {
    guard actual == expected else {
        fputs("FAIL: \(message); expected \(expected), got \(actual)\n", stderr)
        exit(1)
    }
}

expectEqual(
    TimerRulerPolicy.minute(at: 181 * 24, pixelsPerMinute: 24, maximumMinutes: 180),
    180,
    "horizontal ruler must stop at 180 minutes"
)
expectEqual(
    TimerRulerPolicy.minute(at: -12, pixelsPerMinute: 24, maximumMinutes: 180),
    0,
    "horizontal ruler must stop at zero"
)
expectEqual(
    TimerRulerPolicy.changedMinute(previous: 12, position: 12.2 * 24, pixelsPerMinute: 24, maximumMinutes: 180),
    nil,
    "sub-minute movement must stay local to the ruler"
)
expectEqual(
    TimerRulerPolicy.changedMinute(previous: 12, position: 12.6 * 24, pixelsPerMinute: 24, maximumMinutes: 180),
    13,
    "crossing a minute boundary must update the timer preview"
)
expectEqual(
    Double(TimerRulerPolicy.minute(at: 12.25 * 24, pixelsPerMinute: 24, maximumMinutes: 180)),
    12.25,
    "clock preview must preserve sub-minute ruler movement"
)

print("TimerRulerPolicyTests passed")
