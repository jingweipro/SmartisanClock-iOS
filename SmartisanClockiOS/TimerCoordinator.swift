import Foundation
import SwiftUI

@MainActor
protocol TimerSystemClient: AnyObject {
    func scheduleTimer(id: UUID, duration: TimeInterval) async throws
    func pauseTimer(id: UUID) throws
    func resumeTimer(id: UUID) throws
    func cancelTimer(id: UUID) throws
    func snapshot(for id: UUID) throws -> SystemTimerSnapshot?
    func timerCandidates(excluding ordinaryAlarmIDs: Set<UUID>) throws -> [SystemTimerSnapshot]
}

extension AlarmKitService: TimerSystemClient {}

@MainActor
final class TimerCoordinator: ObservableObject {
    @Published private(set) var session: TimerSession?
    @Published var selectedMinutes: Double = 0
    @Published var message: String?

    private let service: any TimerSystemClient
    private let store: any TimerSessionStoreProtocol
    private var schedulingTask: Task<Void, Never>?
    private var isReconciling = false

    init(
        service: any TimerSystemClient,
        store: any TimerSessionStoreProtocol = UserDefaultsTimerSessionStore()
    ) {
        self.service = service
        self.store = store
        session = store.load()
        if let session {
            selectedMinutes = TimerStateReducer.remaining(session: session, at: Date()) / 60
        }
    }

    var isRunning: Bool { session?.status == .running }
    var isPaused: Bool { session?.status == .paused }
    var fireDate: Date? { isRunning ? session?.fireDate : nil }
    var remainingWhenPaused: TimeInterval { session?.pausedRemaining ?? 0 }

    func remaining(at date: Date) -> TimeInterval {
        guard let session else { return 0 }
        return TimerStateReducer.remaining(session: session, at: date)
    }

    func start(duration: TimeInterval, now: Date = Date()) {
        guard duration > 0 else { return }
        schedulingTask?.cancel()

        if let previous = session {
            do {
                try service.cancelTimer(id: previous.alarmID)
            } catch {
                if (try? service.snapshot(for: previous.alarmID)) != nil {
                    message = error.localizedDescription
                    return
                }
            }
        }

        let pending = TimerSession(
            alarmID: UUID(),
            originalDuration: duration,
            startedAt: now,
            fireDate: now.addingTimeInterval(duration),
            status: .scheduling,
            pausedRemaining: nil,
            updatedAt: now,
            schemaVersion: TimerSession.currentSchemaVersion
        )

        do {
            try store.save(pending)
            session = pending
            selectedMinutes = duration / 60
        } catch {
            message = error.localizedDescription
            return
        }

        schedulingTask = Task { [weak self] in
            guard let self else { return }
            do {
                try await service.scheduleTimer(id: pending.alarmID, duration: duration)
                try Task.checkCancellation()
                guard session?.alarmID == pending.alarmID else { return }
                var running = pending
                running.status = .running
                running.updatedAt = Date()
                try store.save(running)
                session = running
            } catch is CancellationError {
                if session?.alarmID == pending.alarmID {
                    try? service.cancelTimer(id: pending.alarmID)
                    clearLocalSession(resetSelection: false)
                }
            } catch {
                guard session?.alarmID == pending.alarmID else { return }
                clearLocalSession(resetSelection: false)
                selectedMinutes = duration / 60
                message = error.localizedDescription
            }
        }
    }

    func pause(now: Date = Date()) {
        guard let current = session, current.status == .running else { return }
        do {
            try service.pauseTimer(id: current.alarmID)
            let paused = TimerStateReducer.pause(session: current, at: now)
            try store.save(paused)
            session = paused
            selectedMinutes = (paused.pausedRemaining ?? 0) / 60
        } catch {
            message = error.localizedDescription
        }
    }

    func resume(now: Date = Date()) {
        guard let current = session, current.status == .paused else { return }
        do {
            try service.resumeTimer(id: current.alarmID)
            let running = TimerStateReducer.resume(session: current, at: now)
            try store.save(running)
            session = running
            selectedMinutes = running.originalDuration / 60
        } catch {
            message = error.localizedDescription
        }
    }

    @discardableResult
    func cancel(now: Date = Date(), resetSelection: Bool = true) -> Bool {
        schedulingTask?.cancel()
        guard let current = session else {
            clearLocalSession(resetSelection: resetSelection)
            return true
        }

        do {
            try service.cancelTimer(id: current.alarmID)
        } catch {
            if (try? service.snapshot(for: current.alarmID)) != nil {
                message = error.localizedDescription
                return false
            }
        }

        clearLocalSession(resetSelection: resetSelection)
        return true
    }

    func beginAdjustment(now: Date = Date()) -> TimeInterval? {
        let duration = session.map { TimerStateReducer.remaining(session: $0, at: now) }
        guard cancel(now: now, resetSelection: false) else { return nil }
        if let duration { selectedMinutes = duration / 60 }
        return duration
    }

    func setSelectedMinutes(_ value: Double) {
        selectedMinutes = max(0, value)
    }

    func finishIfNeeded(at date: Date = Date()) {
        guard let current = session,
              current.status == .running,
              current.fireDate <= date else { return }
        clearLocalSession(resetSelection: true)
    }

    func reconcile(ordinaryAlarmIDs: Set<UUID>, now: Date = Date()) async {
        guard !isReconciling else { return }
        isReconciling = true
        defer { isReconciling = false }

        if let stored = store.load() {
            do {
                let system = try service.snapshot(for: stored.alarmID)
                apply(
                    TimerSessionReconciler.resolve(session: stored, system: system, now: now),
                    now: now
                )
            } catch {
                message = error.localizedDescription
            }
            return
        }

        do {
            let candidates = try service.timerCandidates(excluding: ordinaryAlarmIDs)
                .filter { snapshot in
                    switch snapshot.state {
                    case .scheduled, .countdown:
                        return snapshot.fireDate.map { $0 > now } ?? true
                    case .paused, .alerting:
                        return true
                    }
                }

            guard let candidate = candidates.first else {
                clearLocalSession(resetSelection: true)
                return
            }

            let remaining = candidate.pausedRemaining
                ?? candidate.fireDate?.timeIntervalSince(now)
                ?? 0
            let duration = max(0, remaining)
            let recovered = TimerSession(
                alarmID: candidate.id,
                originalDuration: duration,
                startedAt: now,
                fireDate: candidate.fireDate ?? now.addingTimeInterval(duration),
                status: candidate.state == .paused ? .paused : .running,
                pausedRemaining: candidate.state == .paused ? duration : nil,
                updatedAt: now,
                schemaVersion: TimerSession.currentSchemaVersion
            )
            try store.save(recovered)
            session = recovered
            selectedMinutes = duration / 60

            for duplicate in candidates.dropFirst() {
                try? service.cancelTimer(id: duplicate.id)
            }
        } catch {
            message = error.localizedDescription
        }
    }

    private func apply(_ decision: TimerRecoveryDecision, now: Date) {
        switch decision {
        case let .restore(recovered):
            do {
                try store.save(recovered)
                session = recovered
                selectedMinutes = TimerStateReducer.remaining(session: recovered, at: now) / 60
            } catch {
                message = error.localizedDescription
            }
        case .completed, .clear:
            clearLocalSession(resetSelection: true)
        }
    }

    private func clearLocalSession(resetSelection: Bool) {
        store.clear()
        session = nil
        if resetSelection { selectedMinutes = 0 }
    }
}
