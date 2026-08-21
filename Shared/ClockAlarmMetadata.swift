import AlarmKit
import Foundation

enum ClockAlarmKind: String, Codable, Hashable, Sendable {
    case timer
    case alarm
}

struct ClockAlarmMetadata: AlarmMetadata, Hashable, Sendable {
    let kind: ClockAlarmKind
    let label: String
    let originalDuration: TimeInterval?

    init(kind: ClockAlarmKind, label: String, originalDuration: TimeInterval? = nil) {
        self.kind = kind
        self.label = label
        self.originalDuration = originalDuration
    }
}
