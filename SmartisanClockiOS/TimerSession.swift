import Foundation

enum TimerSessionStatus: String, Codable, Equatable {
    case scheduling
    case running
    case paused
}

struct TimerSession: Codable, Equatable {
    static let currentSchemaVersion = 1

    let alarmID: UUID
    let originalDuration: TimeInterval
    let startedAt: Date
    var fireDate: Date
    var status: TimerSessionStatus
    var pausedRemaining: TimeInterval?
    var updatedAt: Date
    let schemaVersion: Int
}

protocol TimerSessionStoreProtocol {
    func load() -> TimerSession?
    func save(_ session: TimerSession) throws
    func clear()
}

struct UserDefaultsTimerSessionStore: TimerSessionStoreProtocol {
    static let defaultKey = "clockwork.timerSession.v1"

    private let userDefaults: UserDefaults
    private let key: String
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init(userDefaults: UserDefaults = .standard, key: String = Self.defaultKey) {
        self.userDefaults = userDefaults
        self.key = key
    }

    func load() -> TimerSession? {
        guard let data = userDefaults.data(forKey: key) else { return nil }
        do {
            let session = try decoder.decode(TimerSession.self, from: data)
            guard session.schemaVersion == TimerSession.currentSchemaVersion else {
                userDefaults.removeObject(forKey: key)
                return nil
            }
            return session
        } catch {
            userDefaults.removeObject(forKey: key)
            return nil
        }
    }

    func save(_ session: TimerSession) throws {
        userDefaults.set(try encoder.encode(session), forKey: key)
    }

    func clear() {
        userDefaults.removeObject(forKey: key)
    }
}

struct SystemTimerSnapshot: Equatable {
    enum State: Equatable {
        case scheduled
        case countdown
        case paused
        case alerting
    }

    let id: UUID
    let state: State
    let fireDate: Date?
    let pausedRemaining: TimeInterval?

    init(
        id: UUID,
        state: State,
        fireDate: Date? = nil,
        pausedRemaining: TimeInterval? = nil
    ) {
        self.id = id
        self.state = state
        self.fireDate = fireDate
        self.pausedRemaining = pausedRemaining
    }
}

enum TimerRecoveryDecision: Equatable {
    case restore(TimerSession)
    case completed(TimerSession)
    case clear
}

enum TimerSessionReconciler {
    static func resolve(
        session: TimerSession,
        system: SystemTimerSnapshot?,
        now: Date
    ) -> TimerRecoveryDecision {
        guard session.schemaVersion == TimerSession.currentSchemaVersion,
              let system,
              system.id == session.alarmID else {
            return .clear
        }

        if system.state == .alerting {
            return .completed(session)
        }

        var recovered = session
        recovered.updatedAt = now

        switch system.state {
        case .paused:
            recovered.status = .paused
            recovered.pausedRemaining = system.pausedRemaining
                ?? session.pausedRemaining
                ?? max(0, session.fireDate.timeIntervalSince(now))
            return .restore(recovered)

        case .scheduled, .countdown:
            recovered.status = .running
            recovered.pausedRemaining = nil
            if let systemFireDate = system.fireDate {
                recovered.fireDate = systemFireDate
            }
            return recovered.fireDate > now ? .restore(recovered) : .completed(recovered)

        case .alerting:
            return .completed(recovered)
        }
    }
}
