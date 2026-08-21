# Recoverable Timer and AlarmKit Live Activity Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Restore AlarmKit timers after process termination and add a Smartisan-style AlarmKit Live Activity for the Lock Screen and Dynamic Island.

**Architecture:** AlarmKit is the only system timer authority. A Codable local session preserves app-facing dates and identity, a main-actor coordinator reconciles that record with `AlarmManager.alarms`, and an AlarmKit `AlarmAttributes` Widget Extension renders the countdown without creating a second ActivityKit lifecycle.

**Tech Stack:** Swift 5, SwiftUI, AlarmKit, ActivityKit, WidgetKit, AppIntents, UserDefaults, Xcode 26, iOS 26.

**Spec:** `docs/superpowers/specs/2026-08-21-timer-restoration-alarmkit-live-activity-design.md`

## Global Constraints

- Keep the iOS deployment target at 26.0 and add no third-party dependencies.
- AlarmKit remains the sole system-side timer and alarm authority.
- Future ordinary alarms do not continuously occupy the Dynamic Island.
- Remaining running time always comes from an absolute fire date.
- Preserve the existing ruler responsiveness and clock-face animation edits.
- Do not stage or overwrite unrelated pre-existing worktree changes.

## File Map

- Create `SmartisanClockiOS/TimerSession.swift` for persistence and pure reconciliation.
- Create `SmartisanClockiOS/TimerCoordinator.swift` for timer lifecycle orchestration.
- Create `Shared/ClockAlarmMetadata.swift` for code shared by the app and extension.
- Modify `SmartisanClockiOS/AlarmKitService.swift`, `TimerView.swift`, and `SmartisanClockiOSApp.swift`.
- Create `SmartisanClockLiveActivity/` for the Widget Extension.
- Modify the app plist and Xcode project for Live Activity support and embedding.
- Create `Tests/TimerSessionTests/main.swift` plus test scripts.

---

### Task 1: Persistent Timer Session

**Files:**
- Create: `SmartisanClockiOS/TimerSession.swift`
- Create: `Tests/TimerSessionTests/main.swift`
- Create: `scripts/test-timer-session.sh`

**Interfaces:**
- Produces: `TimerSession`, `TimerSessionStoreProtocol`, `UserDefaultsTimerSessionStore`, `SystemTimerSnapshot`, and `TimerSessionReconciler.resolve(session:system:now:)`.
- Consumes: Foundation only.

- [ ] **Step 1: Write failing restoration tests**

Use a fixed clock and UUID. Assert that a matching countdown restores, a paused session keeps its frozen remaining time, a missing system timer clears, alerting becomes completed, and corrupt JSON is removed.

```swift
let now = Date(timeIntervalSince1970: 1_800_000_000)
let id = UUID(uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE")!
let running = TimerSession(
    alarmID: id, originalDuration: 600,
    startedAt: now.addingTimeInterval(-120),
    fireDate: now.addingTimeInterval(480),
    status: .running, pausedRemaining: nil,
    updatedAt: now, schemaVersion: 1
)
expectEqual(
    TimerSessionReconciler.resolve(
        session: running,
        system: .init(id: id, state: .countdown),
        now: now
    ),
    .restore(running),
    "matching AlarmKit timer restores"
)
expectEqual(
    TimerSessionReconciler.resolve(session: running, system: nil, now: now),
    .clear,
    "missing AlarmKit timer clears local state"
)
```

- [ ] **Step 2: Run the test and verify failure**

Run: `sh scripts/test-timer-session.sh`

Expected: Swift compilation fails because the session types do not exist.

- [ ] **Step 3: Implement the model, store, and reconciler**

```swift
enum TimerSessionStatus: String, Codable, Equatable {
    case scheduling, running, paused
}

struct TimerSession: Codable, Equatable {
    let alarmID: UUID
    let originalDuration: TimeInterval
    let startedAt: Date
    var fireDate: Date
    var status: TimerSessionStatus
    var pausedRemaining: TimeInterval?
    var updatedAt: Date
    let schemaVersion: Int
}

struct SystemTimerSnapshot: Equatable {
    enum State: Equatable { case scheduled, countdown, paused, alerting }
    let id: UUID
    let state: State
}

enum TimerRecoveryDecision: Equatable {
    case restore(TimerSession), completed(TimerSession), clear
}
```

Use key `clockwork.timerSession.v1`. Decoding failure removes the key. Restore only matching IDs; clear expired or absent IDs; preserve paused remaining time.

- [ ] **Step 4: Run tests and commit**

Run: `sh scripts/test-timer-session.sh`

Expected: `TimerSessionTests passed`.

```bash
git add SmartisanClockiOS/TimerSession.swift Tests/TimerSessionTests/main.swift scripts/test-timer-session.sh
git commit -m "feat: persist recoverable timer sessions"
```

### Task 2: AlarmKit Timer Lifecycle

**Files:**
- Create: `Shared/ClockAlarmMetadata.swift`
- Modify: `SmartisanClockiOS/AlarmKitService.swift`
- Modify: `SmartisanClockiOS.xcodeproj/project.pbxproj`

**Interfaces:**
- Consumes: `SystemTimerSnapshot` from Task 1.
- Produces: `ClockAlarmMetadata`, `scheduleTimer`, `pauseTimer`, `resumeTimer`, `cancelTimer`, `snapshot(for:)`, and migration candidates.

- [ ] **Step 1: Move and extend metadata shared by both targets**

```swift
import AlarmKit

enum ClockAlarmKind: String, Codable, Hashable, Sendable { case timer, alarm }

struct ClockAlarmMetadata: AlarmMetadata, Hashable, Sendable {
    let kind: ClockAlarmKind
    let label: String
    let originalDuration: TimeInterval?
}
```

Remove the previous metadata declaration from `AlarmKitService.swift`. Ordinary alarms use `.alarm`; timers use `.timer`.

- [ ] **Step 2: Replace the fixed-date alarm simulation**

Create alert, countdown, and paused presentations, then schedule with:

```swift
let configuration = AlarmManager.AlarmConfiguration.timer(
    duration: duration,
    attributes: attributes,
    sound: .named("timer.wav")
)
_ = try await manager.schedule(id: id, configuration: configuration)
```

Verify exact `AlarmPresentation.Countdown` and `.Paused` initializer labels against the installed iOS 26.2 Swift interface before compiling.

- [ ] **Step 3: Add throwing lifecycle and snapshot methods**

```swift
func pauseTimer(id: UUID) throws { try manager.pause(id: id) }
func resumeTimer(id: UUID) throws { try manager.resume(id: id) }
func cancelTimer(id: UUID) throws { try manager.cancel(id: id) }
func snapshot(for id: UUID) throws -> SystemTimerSnapshot?
func timerCandidates(excluding ordinaryAlarmIDs: Set<UUID>) throws -> [Alarm]
```

Candidate migration never returns an ID found in the ordinary alarm store. Convert AlarmKit states one-for-one into `SystemTimerSnapshot.State`.

- [ ] **Step 4: Build and commit**

Run:

```bash
xcodebuild -project SmartisanClockiOS.xcodeproj -scheme SmartisanClockiOS \
  -sdk iphonesimulator -destination 'platform=iOS Simulator,name=Codex Smartisan iPhone 16' \
  CODE_SIGNING_ALLOWED=NO build
```

Expected: `** BUILD SUCCEEDED **`.

```bash
git add Shared/ClockAlarmMetadata.swift SmartisanClockiOS/AlarmKitService.swift SmartisanClockiOS.xcodeproj/project.pbxproj
git commit -m "feat: use AlarmKit timer lifecycle"
```

### Task 3: Coordinator and State Recovery

**Files:**
- Create: `SmartisanClockiOS/TimerCoordinator.swift`
- Modify: `Tests/TimerSessionTests/main.swift`
- Modify: `scripts/test-timer-session.sh`
- Modify: `SmartisanClockiOS.xcodeproj/project.pbxproj`

**Interfaces:**
- Consumes: the store/reconciler from Task 1 and AlarmKit operations from Task 2.
- Produces: `TimerCoordinator` state plus `start`, `pause`, `resume`, `cancel`, `beginAdjustment`, and `reconcile` actions.

- [ ] **Step 1: Add failing pure transition tests**

```swift
expectEqual(TimerStateReducer.remaining(session: running, at: now), 480, "remaining uses fireDate")
let paused = TimerStateReducer.pause(session: running, at: now)
expectEqual(paused.status, .paused, "pause stores paused state")
expectEqual(paused.pausedRemaining, 480, "pause freezes remaining")
let resumed = TimerStateReducer.resume(session: paused, at: now.addingTimeInterval(20))
expectEqual(resumed.fireDate, now.addingTimeInterval(500), "resume creates a new fireDate")
```

- [ ] **Step 2: Run tests and verify failure**

Run: `sh scripts/test-timer-session.sh`

Expected: compilation fails because `TimerStateReducer` does not exist.

- [ ] **Step 3: Implement reducer and coordinator**

```swift
@MainActor
final class TimerCoordinator: ObservableObject {
    @Published private(set) var session: TimerSession?
    @Published var selectedMinutes: Double = 0
    @Published var message: String?
    var isRunning: Bool { session?.status == .running }
    var fireDate: Date? { isRunning ? session?.fireDate : nil }
    var remainingWhenPaused: TimeInterval { session?.pausedRemaining ?? 0 }
    func remaining(at date: Date) -> TimeInterval
}
```

Save `.scheduling` before AlarmKit scheduling and commit `.running` only after success. On cancellation, keep the local session until AlarmKit confirms the ID is absent. `reconcile` restores the stored ID first; with no record it may recover one safe historical timer candidate and cancel only duplicate candidate IDs.

- [ ] **Step 4: Run tests, build, and commit**

Run both `sh scripts/test-timer-session.sh` and the Task 2 Xcode build command. Both must pass.

```bash
git add SmartisanClockiOS/TimerCoordinator.swift SmartisanClockiOS.xcodeproj/project.pbxproj Tests/TimerSessionTests/main.swift scripts/test-timer-session.sh
git commit -m "feat: reconcile timer state with AlarmKit"
```

### Task 4: TimerView and App Lifecycle Integration

**Files:**
- Modify: `SmartisanClockiOS/TimerView.swift`
- Modify: `SmartisanClockiOS/SmartisanClockiOSApp.swift`

**Interfaces:**
- Consumes: `TimerCoordinator` and `AlarmStore.alarms`.
- Produces: recovered UI state on launch and foreground activation.

- [ ] **Step 1: Construct and inject one service/coordinator pair**

```swift
@StateObject private var alarmService: AlarmKitService
@StateObject private var timerCoordinator: TimerCoordinator
@Environment(\.scenePhase) private var scenePhase

init() {
    let service = AlarmKitService()
    _alarmService = StateObject(wrappedValue: service)
    _timerCoordinator = StateObject(wrappedValue: TimerCoordinator(service: service))
}
```

Inject both objects. Reconcile on the first task and whenever scene phase becomes active, passing `Set(alarmStore.alarms.map(\.id))`.

- [ ] **Step 2: Route TimerView lifecycle through the coordinator**

Remove view-owned `running`, `fireDate`, `remainingWhenPaused`, `alarmID`, and `pendingSchedule`. Keep local ruler preview and bounce state. Add `@EnvironmentObject private var timer: TimerCoordinator` and route every start/pause/resume/reset/adjustment action through it.

- [ ] **Step 3: Add deterministic DEBUG launch support**

Support `-SmartisanTimerTestDurationSeconds <number>` once when no session exists. This enables simulator process-termination tests and has no release effect.

- [ ] **Step 4: Run regressions and commit**

Run:

```bash
sh scripts/test-timer-ruler-policy.sh
sh scripts/test-timer-session.sh
xcodebuild -project SmartisanClockiOS.xcodeproj -scheme SmartisanClockiOS \
  -sdk iphonesimulator -destination 'platform=iOS Simulator,name=Codex Smartisan iPhone 16' \
  CODE_SIGNING_ALLOWED=NO build
```

Expected: both scripts pass and the Xcode build succeeds.

```bash
git add SmartisanClockiOS/SmartisanClockiOSApp.swift SmartisanClockiOS/TimerView.swift
git commit -m "fix: restore active timer after relaunch"
```

### Task 5: Smartisan AlarmKit Live Activity

**Files:**
- Create: `SmartisanClockLiveActivity/SmartisanClockLiveActivityBundle.swift`
- Create: `SmartisanClockLiveActivity/AlarmLiveActivity.swift`
- Create: `SmartisanClockLiveActivity/Info.plist`
- Modify: `SmartisanClockiOS/Info.plist`
- Modify: `SmartisanClockiOS.xcodeproj/project.pbxproj`

**Interfaces:**
- Consumes: `AlarmAttributes<ClockAlarmMetadata>`.
- Produces: Lock Screen plus compact, minimal, and expanded Dynamic Island layouts.

- [ ] **Step 1: Add and embed the extension target**

Use bundle ID `com.jingweipro.SmartisanClockiOS.LiveActivity`, iOS 26.0, `APPLICATION_EXTENSION_API_ONLY = YES`, and `SKIP_INSTALL = YES`. Add a target dependency and Embed App Extensions phase with CodeSignOnCopy. Include the shared metadata file in both targets. Set `NSSupportsLiveActivities` to true in the app plist. The extension plist uses `com.apple.widgetkit-extension`.

- [ ] **Step 2: Implement the mechanical dial**

Use SwiftUI shapes so the extension does not depend on app assets:

```swift
ZStack {
    Circle().fill(.white.opacity(0.96))
    Circle().stroke(.white, lineWidth: 3)
    Capsule().fill(Color(white: 0.35))
        .frame(width: 3, height: 22).offset(y: -8)
        .rotationEffect(.degrees(progress * 360))
    Circle().fill(Color(red: 0.82, green: 0.18, blue: 0.16))
        .frame(width: 7, height: 7)
}
```

Derive progress from `AlarmPresentationState.Mode` and clamp it to `0...1`.

- [ ] **Step 3: Implement all Live Activity presentations**

Compact leading is a 22-point dial; compact trailing is a red system-updating countdown; minimal is the white ring/red hub. Expanded and Lock Screen presentations show the simplified dial, label, large red remaining time, and pause/resume/stop actions supplied by AlarmKit. Add accessibility labels for countdown and paused state.

- [ ] **Step 4: Build, verify embedding, and commit**

Run the simulator build, then verify the built app contains `PlugIns/SmartisanClockLiveActivity.appex` with `find`.

```bash
git add SmartisanClockLiveActivity Shared/ClockAlarmMetadata.swift SmartisanClockiOS/Info.plist SmartisanClockiOS.xcodeproj/project.pbxproj
git commit -m "feat: add Smartisan AlarmKit live activity"
```

### Task 6: Relaunch, Visual, and Device Verification

**Files:**
- Create: `scripts/test-timer-restoration-simulator.sh`
- Modify: `README.md` only when documenting the shipped behavior.

**Interfaces:**
- Consumes: the DEBUG launch argument and embedded app from Tasks 4-5.
- Produces: repeatable relaunch evidence and the installed device build.

- [ ] **Step 1: Write simulator termination/relaunch smoke test**

Build and install the app, erase its previous container, launch with a 90-second timer, read `clockwork.timerSession.v1`, terminate the process, relaunch without arguments, and verify the UUID and fire date are unchanged.

```bash
xcrun simctl launch "$device_id" com.jingweipro.SmartisanClockiOS -SmartisanTimerTestDurationSeconds 90
xcrun simctl terminate "$device_id" com.jingweipro.SmartisanClockiOS
xcrun simctl launch "$device_id" com.jingweipro.SmartisanClockiOS
```

- [ ] **Step 2: Run all automated checks**

```bash
sh scripts/test-timer-ruler-policy.sh
sh scripts/test-timer-session.sh
sh scripts/test-timer-restoration-simulator.sh
```

Expected: all scripts exit 0 and print pass markers.

- [ ] **Step 3: Inspect Live Activity states**

On the Dynamic-Island simulator, capture compact and expanded countdown states, pause and inspect the paused state, reset, and confirm the Live Activity disappears. Keep temporary evidence outside the repository unless README images are intentionally updated.

- [ ] **Step 4: Build and install on the connected iPhone**

Verify connectivity with `xcrun devicectl list devices`, build for destination `id=00008140-00160108140A801C` with `-allowProvisioningUpdates`, install the resulting app using `xcrun devicectl device install app`, and launch it. If the phone is disconnected, report only that final device-specific remainder after completing simulator verification.

- [ ] **Step 5: Final diff review and focused commit**

Run `git diff --check`, `git status --short`, and the complete test suite. Stage only the new smoke script and an intentional README change:

```bash
git add scripts/test-timer-restoration-simulator.sh README.md
git commit -m "test: verify timer restoration after relaunch"
```

## Self-Review Results

- Spec coverage: persistence, recovery, migration, AlarmKit conversion, foreground reconciliation, Widget Extension, all Dynamic Island states, fallback behavior, tests, simulator relaunch, and device installation each have an owning task.
- Placeholder scan: no deferred implementation markers remain; the two SDK initializer checks are bounded compile-verification steps against the installed SDK.
- Type consistency: the same `TimerSession`, `SystemTimerSnapshot`, `ClockAlarmMetadata`, and `TimerCoordinator` names are used across all tasks.
