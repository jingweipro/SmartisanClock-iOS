import AlarmKit
import Foundation
import SwiftUI

struct ClockAlarmMetadata: AlarmMetadata {
    let label: String
}

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
            metadata: ClockAlarmMetadata(label: item.label),
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
        let alert = AlarmPresentation.Alert(title: "计时结束", stopButton: stop)
        let attributes = AlarmAttributes(
            presentation: .init(alert: alert),
            metadata: ClockAlarmMetadata(label: "计时结束"),
            tintColor: ClockTheme.red
        )
        let configuration = AlarmManager.AlarmConfiguration.alarm(
            schedule: .fixed(Date().addingTimeInterval(duration)),
            attributes: attributes,
            sound: .named("timer.wav")
        )
        _ = try await manager.schedule(id: id, configuration: configuration)
        if Task.isCancelled {
            try? manager.cancel(id: id)
            throw CancellationError()
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

enum AlarmServiceError: LocalizedError {
    case notAuthorized

    var errorDescription: String? { "没有获得系统闹钟权限" }
}
