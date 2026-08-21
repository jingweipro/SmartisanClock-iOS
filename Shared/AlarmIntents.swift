import AlarmKit
import AppIntents
import Foundation

struct PauseTimerIntent: LiveActivityIntent {
    static var title: LocalizedStringResource = "暂停计时器"
    static var description = IntentDescription("暂停当前倒计时")

    @Parameter(title: "闹钟 ID") var alarmID: String

    init(alarmID: String) { self.alarmID = alarmID }
    init() { alarmID = "" }

    func perform() throws -> some IntentResult {
        guard let id = UUID(uuidString: alarmID) else { return .result() }
        try AlarmManager.shared.pause(id: id)
        return .result()
    }
}

struct ResumeTimerIntent: LiveActivityIntent {
    static var title: LocalizedStringResource = "继续计时器"
    static var description = IntentDescription("继续当前倒计时")

    @Parameter(title: "闹钟 ID") var alarmID: String

    init(alarmID: String) { self.alarmID = alarmID }
    init() { alarmID = "" }

    func perform() throws -> some IntentResult {
        guard let id = UUID(uuidString: alarmID) else { return .result() }
        try AlarmManager.shared.resume(id: id)
        return .result()
    }
}

struct StopTimerIntent: LiveActivityIntent {
    static var title: LocalizedStringResource = "停止计时器"
    static var description = IntentDescription("停止当前倒计时或响铃")

    @Parameter(title: "闹钟 ID") var alarmID: String

    init(alarmID: String) { self.alarmID = alarmID }
    init() { alarmID = "" }

    func perform() throws -> some IntentResult {
        guard let id = UUID(uuidString: alarmID) else { return .result() }
        try AlarmManager.shared.stop(id: id)
        return .result()
    }
}
