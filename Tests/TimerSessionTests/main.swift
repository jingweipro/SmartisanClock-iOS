import Foundation

private func expectEqual<T: Equatable>(_ actual: T, _ expected: T, _ message: String) {
    guard actual == expected else {
        fputs("FAIL: \(message); expected \(expected), got \(actual)\n", stderr)
        exit(1)
    }
}

private func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
    guard condition() else {
        fputs("FAIL: \(message)\n", stderr)
        exit(1)
    }
}

let now = Date(timeIntervalSince1970: 1_800_000_000)
let id = UUID(uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE")!
let otherID = UUID(uuidString: "11111111-2222-3333-4444-555555555555")!
let running = TimerSession(
    alarmID: id,
    originalDuration: 600,
    startedAt: now.addingTimeInterval(-120),
    fireDate: now.addingTimeInterval(480),
    status: .running,
    pausedRemaining: nil,
    updatedAt: now,
    schemaVersion: TimerSession.currentSchemaVersion
)

expectEqual(
    TimerSessionReconciler.resolve(
        session: running,
        system: SystemTimerSnapshot(id: id, state: .countdown),
        now: now
    ),
    .restore(running),
    "matching AlarmKit countdown must restore"
)

expectEqual(
    TimerSessionReconciler.resolve(
        session: running,
        system: SystemTimerSnapshot(id: otherID, state: .countdown),
        now: now
    ),
    .clear,
    "mismatched AlarmKit ID must clear local state"
)

expectEqual(
    TimerSessionReconciler.resolve(session: running, system: nil, now: now),
    .clear,
    "missing AlarmKit timer must clear local state"
)

var paused = running
paused.status = .paused
paused.pausedRemaining = 321
paused.fireDate = now
var expectedPaused = paused
expectedPaused.updatedAt = now.addingTimeInterval(90)
expectEqual(
    TimerSessionReconciler.resolve(
        session: paused,
        system: SystemTimerSnapshot(id: id, state: .paused),
        now: now.addingTimeInterval(90)
    ),
    .restore(expectedPaused),
    "paused timer must keep its frozen remaining time"
)

expectEqual(
    TimerSessionReconciler.resolve(
        session: running,
        system: SystemTimerSnapshot(id: id, state: .alerting),
        now: now.addingTimeInterval(481)
    ),
    .completed(running),
    "alerting timer must become completed instead of restarting"
)

var pending = running
pending.status = .scheduling
let recoveredPending = TimerSessionReconciler.resolve(
    session: pending,
    system: SystemTimerSnapshot(id: id, state: .countdown),
    now: now
)
guard case let .restore(recovered) = recoveredPending else {
    fputs("FAIL: scheduled transaction must recover when AlarmKit owns the ID\n", stderr)
    exit(1)
}
expectEqual(recovered.status, .running, "recovered transaction must commit running state")

expectEqual(
    TimerStateReducer.remaining(session: running, at: now),
    480,
    "running remaining time must come from fireDate"
)
let reducerPaused = TimerStateReducer.pause(session: running, at: now)
expectEqual(reducerPaused.status, .paused, "pause must store paused state")
expectEqual(reducerPaused.pausedRemaining, 480, "pause must freeze current remaining time")
let reducerResumed = TimerStateReducer.resume(
    session: reducerPaused,
    at: now.addingTimeInterval(20)
)
expectEqual(reducerResumed.status, .running, "resume must store running state")
expectEqual(
    reducerResumed.fireDate,
    now.addingTimeInterval(500),
    "resume must create a new absolute fire date"
)

let suiteName = "TimerSessionTests.\(UUID().uuidString)"
let defaults = UserDefaults(suiteName: suiteName)!
defer { defaults.removePersistentDomain(forName: suiteName) }
let key = "test.timer.session"
let store = UserDefaultsTimerSessionStore(userDefaults: defaults, key: key)
try store.save(running)
expectEqual(store.load(), running, "saved timer session must round-trip")
store.clear()
expectEqual(store.load(), nil, "clear must remove persisted timer session")

defaults.set(Data("not-json".utf8), forKey: key)
expectEqual(store.load(), nil, "corrupt timer session must fail closed")
expect(defaults.object(forKey: key) == nil, "corrupt timer data must be removed")

let fileDirectory = FileManager.default.temporaryDirectory
    .appendingPathComponent("TimerSessionTests.\(UUID().uuidString)", isDirectory: true)
let fileURL = fileDirectory.appendingPathComponent("session.json")
let fileStore = FileTimerSessionStore(fileURL: fileURL)
defer { try? FileManager.default.removeItem(at: fileDirectory) }
try fileStore.save(running)
expectEqual(fileStore.load(), running, "atomic file session must round-trip")
fileStore.clear()
expectEqual(fileStore.load(), nil, "file clear must remove persisted timer session")

try FileManager.default.createDirectory(at: fileDirectory, withIntermediateDirectories: true)
try Data("not-json".utf8).write(to: fileURL)
expectEqual(fileStore.load(), nil, "corrupt file session must fail closed")
expect(!FileManager.default.fileExists(atPath: fileURL.path), "corrupt session file must be removed")

print("TimerSessionTests passed")
