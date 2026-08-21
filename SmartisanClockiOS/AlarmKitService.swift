import AlarmKit
import ActivityKit
import Foundation
import SwiftUI

@MainActor
final class AlarmKitService: ObservableObject {
    @Published private(set) var authorizationState = AlarmManager.shared.authorizationState
    @Published var lastError: String?
    private let manager = AlarmManager.shared

    func requestAuthorization() async -> Bool {
        do {
            authorizationState = try await manager.requestAuthorization()
            return authorizationState == .authorized
        } catch {
            lastError = error.localizedDescription
            return false
        }
    }

    func schedule(_ item: UserAlarm) async throws {
        guard await ensureAuthorized() else { throw AlarmServiceError.notAuthorized }
        try Task.checkCancellation()

        let recurrence: Alarm.Schedule.Relative.Recurrence = item.weekdays.isEmpty
            ? .never
            : .weekly(item.weekdays.sorted().compactMap(Self.localeWeekday))
        let schedule = Alarm.Schedule.relative(.init(
            time: .init(hour: item.hour, minute: item.minute),
            repeats: recurrence
        ))

        let snooze = AlarmButton(text: "贪睡", textColor: .white, systemImageName: "clock.arrow.circlepath")
        let stop = AlarmButton(text: "停止", textColor: .white, systemImageName: "stop.circle")
        let alert = AlarmPresentation.Alert(
            title: "时钟",
            stopButton: stop,
            secondaryButton: snooze,
            secondaryButtonBehavior: .countdown
        )
        let attributes = AlarmAttributes(
            presentation: .init(alert: alert),
            metadata: ClockAlarmMetadata(kind: .alarm, label: item.label),
            tintColor: ClockTheme.red
        )
        let configuration = AlarmManager.AlarmConfiguration(
            countdownDuration: .init(preAlert: nil, postAlert: 10 * 60),
            schedule: schedule,
            attributes: attributes,
            sound: .named(item.ringtoneSoundFile)
        )
        _ = try await manager.schedule(id: item.id, configuration: configuration)
        if Task.isCancelled {
            try? manager.cancel(id: item.id)
            throw CancellationError()
        }
    }

    func scheduleTimer(id: UUID, duration: TimeInterval) async throws {
        guard await ensureAuthorized() else { throw AlarmServiceError.notAuthorized }
        try Task.checkCancellation()
        let stop = AlarmButton(text: "停止", textColor: .white, systemImageName: "stop.circle")
        let pause = AlarmButton(text: "暂停", textColor: .white, systemImageName: "pause.circle")
        let resume = AlarmButton(text: "继续", textColor: .white, systemImageName: "play.circle")
        let alert = AlarmPresentation.Alert(title: "计时结束", stopButton: stop)
        let attributes = AlarmAttributes(
            presentation: .init(
                alert: alert,
                countdown: .init(title: "计时器", pauseButton: pause),
                paused: .init(title: "计时器已暂停", resumeButton: resume)
            ),
            metadata: ClockAlarmMetadata(kind: .timer, label: "计时器", originalDuration: duration),
            tintColor: ClockTheme.red
        )
        let configuration = AlarmManager.AlarmConfiguration.timer(
            duration: duration,
            attributes: attributes,
            sound: .named("timer.wav")
        )
        _ = try await manager.schedule(id: id, configuration: configuration)
        if Task.isCancelled {
            try? manager.cancel(id: id)
            throw CancellationError()
        }
    }

    func pauseTimer(id: UUID) throws {
        try manager.pause(id: id)
    }

    func resumeTimer(id: UUID) throws {
        try manager.resume(id: id)
    }

    func cancelTimer(id: UUID) throws {
        try manager.cancel(id: id)
    }

    func snapshot(for id: UUID) throws -> SystemTimerSnapshot? {
        guard let alarm = try manager.alarms.first(where: { $0.id == id }) else { return nil }
        return snapshot(for: alarm)
    }

    func timerCandidates(excluding ordinaryAlarmIDs: Set<UUID>) throws -> [SystemTimerSnapshot] {
        try manager.alarms.compactMap { alarm in
            guard !ordinaryAlarmIDs.contains(alarm.id) else { return nil }
            let isTimer = alarm.countdownDuration?.preAlert != nil
            let isLegacyFixedTimer: Bool
            if case .fixed = alarm.schedule {
                isLegacyFixedTimer = true
            } else {
                isLegacyFixedTimer = false
            }
            guard isTimer || isLegacyFixedTimer else { return nil }
            return snapshot(for: alarm)
        }
    }

    func cancel(id: UUID) {
        do { try manager.cancel(id: id) }
        catch { lastError = error.localizedDescription }
    }

    private func ensureAuthorized() async -> Bool {
        if manager.authorizationState == .authorized {
            authorizationState = .authorized
            return true
        }
        return await requestAuthorization()
    }

    private func snapshot(for alarm: Alarm) -> SystemTimerSnapshot {
        let activityState = Activity<AlarmAttributes<ClockAlarmMetadata>>.activities
            .lazy
            .map(\.content.state)
            .first(where: { $0.alarmID == alarm.id })

        var fireDate: Date?
        var pausedRemaining: TimeInterval?
        if let activityState {
            switch activityState.mode {
            case let .countdown(countdown):
                fireDate = countdown.fireDate
            case let .paused(paused):
                pausedRemaining = max(0, paused.totalCountdownDuration - paused.previouslyElapsedDuration)
            case .alert:
                break
            @unknown default:
                break
            }
        }

        if fireDate == nil, case let .fixed(date) = alarm.schedule {
            fireDate = date
        }

        return SystemTimerSnapshot(
            id: alarm.id,
            state: alarm.state.timerSnapshotState,
            fireDate: fireDate,
            pausedRemaining: pausedRemaining
        )
    }

    private static func localeWeekday(_ day: Int) -> Locale.Weekday? {
        switch day {
        case 1: .monday
        case 2: .tuesday
        case 3: .wednesday
        case 4: .thursday
        case 5: .friday
        case 6: .saturday
        case 7: .sunday
        default: nil
        }
    }
}

private extension Alarm.State {
    var timerSnapshotState: SystemTimerSnapshot.State {
        switch self {
        case .scheduled: .scheduled
        case .countdown: .countdown
        case .paused: .paused
        case .alerting: .alerting
        @unknown default: .scheduled
        }
    }
}

enum AlarmServiceError: LocalizedError {
    case notAuthorized

    var errorDescription: String? { "没有获得系统闹钟权限" }
}
