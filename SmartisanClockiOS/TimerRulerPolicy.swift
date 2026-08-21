import Foundation

enum TimerRulerPolicy {
    static let modernMaximumMinutes = 180
    static let classicMaximumMinutes = 60

    static func minute(
        at position: CGFloat,
        pixelsPerMinute: CGFloat,
        maximumMinutes: Int
    ) -> Double {
        guard pixelsPerMinute > 0 else { return 0 }
        return Double(position / pixelsPerMinute)
            .clamped(to: 0...Double(maximumMinutes))
    }

    static func committedMinute(
        at position: CGFloat,
        pixelsPerMinute: CGFloat,
        maximumMinutes: Int
    ) -> Int {
        Int(minute(
            at: position,
            pixelsPerMinute: pixelsPerMinute,
            maximumMinutes: maximumMinutes
        ).rounded())
    }

    static func changedMinute(
        previous: Int,
        position: CGFloat,
        pixelsPerMinute: CGFloat,
        maximumMinutes: Int
    ) -> Int? {
        let candidate = committedMinute(
            at: position,
            pixelsPerMinute: pixelsPerMinute,
            maximumMinutes: maximumMinutes
        )
        return candidate == previous ? nil : candidate
    }
}

private extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self {
        min(range.upperBound, max(range.lowerBound, self))
    }
}
