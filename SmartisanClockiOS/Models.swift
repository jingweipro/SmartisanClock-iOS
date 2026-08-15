import Foundation
import SwiftUI

struct UserAlarm: Identifiable, Codable, Hashable {
    var id = UUID()
    var hour: Int
    var minute: Int
    var label: String
    var weekdays: Set<Int>
    var isEnabled: Bool
    var followHolidays: Bool? = nil
    var ringtoneTitle: String? = nil

    var timeText: String { String(format: "%d:%02d", hour, minute) }

    var repeatText: String {
        if weekdays.isEmpty { return "仅一次" }
        if weekdays == Set(1...7) { return "每天" }
        let names = [1: "周一", 2: "周二", 3: "周三", 4: "周四", 5: "周五", 6: "周六", 7: "周日"]
        return weekdays.sorted().compactMap { names[$0] }.joined(separator: " ")
    }

    var effectiveRingtoneTitle: String {
        let value = ringtoneTitle?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return value.isEmpty ? "计时器" : value
    }

    var ringtoneSoundFile: String {
        switch effectiveRingtoneTitle {
        case "铃铛": "ruler_ring.wav"
        case "经典": "ruler_back.wav"
        default: "timer.wav"
        }
    }

    func nextOccurrence(after date: Date) -> Date? {
        var calendar = Calendar.current
        calendar.timeZone = .current
        for dayOffset in 0...8 {
            guard let day = calendar.date(byAdding: .day, value: dayOffset, to: date) else { continue }
            let parts = calendar.dateComponents([.year, .month, .day], from: day)
            guard let candidate = calendar.date(from: DateComponents(
                year: parts.year,
                month: parts.month,
                day: parts.day,
                hour: hour,
                minute: minute
            )), candidate > date else { continue }
            if weekdays.isEmpty { return candidate }
            let systemWeekday = calendar.component(.weekday, from: candidate)
            let mondayBased = ((systemWeekday + 5) % 7) + 1
            if weekdays.contains(mondayBased) { return candidate }
        }
        return nil
    }
}

@MainActor
final class AlarmStore: ObservableObject {
    @Published var alarms: [UserAlarm] { didSet { save() } }
    private let key = "clockwork.userAlarms.v1"

    init() {
        if let data = UserDefaults.standard.data(forKey: key),
           let decoded = try? JSONDecoder().decode([UserAlarm].self, from: data) {
            alarms = decoded
        } else {
            alarms = [UserAlarm(hour: 7, minute: 30, label: "起床", weekdays: Set(1...5), isEnabled: false)]
        }
    }

    func add(_ alarm: UserAlarm) { alarms.append(alarm) }
    func remove(at offsets: IndexSet) { alarms.remove(atOffsets: offsets) }
    func remove(_ alarm: UserAlarm) { alarms.removeAll { $0.id == alarm.id } }

    func replace(_ alarm: UserAlarm) {
        guard let index = alarms.firstIndex(where: { $0.id == alarm.id }) else { return }
        alarms[index] = alarm
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(alarms) else { return }
        UserDefaults.standard.set(data, forKey: key)
    }
}

struct WorldCity: Identifiable, Codable, Hashable {
    var id: String { "\(name)|\(timeZoneID)" }
    let name: String
    let country: String
    let timeZoneID: String
    var englishName: String? = nil
    var englishCountry: String? = nil
    var searchAliases: String? = nil

    var timeZone: TimeZone { TimeZone(identifier: timeZoneID) ?? .current }

    var searchText: String {
        [name, country, englishName, englishCountry, searchAliases]
            .compactMap { $0 }
            .joined(separator: " ")
    }
}

@MainActor
final class CityStore: ObservableObject {
    static let catalog = WorldCityCatalog.load()

    @Published var cities: [WorldCity] { didSet { save() } }
    private let key = "clockwork.cities.v1"

    init() {
        if let data = UserDefaults.standard.data(forKey: key),
           let decoded = try? JSONDecoder().decode([WorldCity].self, from: data), !decoded.isEmpty {
            cities = decoded
        } else {
            let preferred = ["上海", "东京", "伦敦", "旧金山"].compactMap { name in
                Self.catalog.first { $0.name == name }
            }
            cities = preferred.isEmpty ? Array(Self.catalog.prefix(4)) : preferred
        }
    }

    func add(_ city: WorldCity) {
        guard !cities.contains(city) else { return }
        cities.append(city)
    }

    func remove(at offsets: IndexSet) {
        guard cities.count > offsets.count else { return }
        cities.remove(atOffsets: offsets)
    }

    func remove(_ city: WorldCity) {
        guard cities.count > 1 else { return }
        cities.removeAll { $0 == city }
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(cities) else { return }
        UserDefaults.standard.set(data, forKey: key)
    }
}

private enum WorldCityCatalog {
    static func load() -> [WorldCity] {
        guard let url = SmartisanAssets.url("world_cities.tsv"),
              let source = try? String(contentsOf: url, encoding: .utf8) else {
            return fallback
        }

        let cities = source.split(whereSeparator: \.isNewline).compactMap { row -> WorldCity? in
            guard !row.hasPrefix("#") else { return nil }
            let columns = row.split(separator: "\t", omittingEmptySubsequences: false).map(String.init)
            // The bundled catalog is generated from the original, validated IANA list.
            // Re-validating every identifier here made the first world-clock launch block
            // the main thread for several seconds on a clean install.
            guard columns.count >= 9 else { return nil }
            return WorldCity(
                name: columns[5].isEmpty ? columns[2] : columns[5],
                country: columns[6].isEmpty ? columns[3] : columns[6],
                timeZoneID: columns[1],
                englishName: columns[2],
                englishCountry: columns[3],
                searchAliases: columns[8]
            )
        }
        return cities.isEmpty ? fallback : cities
    }

    private static let fallback = [
        WorldCity(name: "上海", country: "中国", timeZoneID: "Asia/Shanghai"),
        WorldCity(name: "北京", country: "中国", timeZoneID: "Asia/Shanghai"),
        WorldCity(name: "东京", country: "日本", timeZoneID: "Asia/Tokyo"),
        WorldCity(name: "伦敦", country: "英国", timeZoneID: "Europe/London"),
        WorldCity(name: "纽约", country: "美国", timeZoneID: "America/New_York")
    ]
}

extension TimeInterval {
    var stopwatchText: String {
        let safe = max(0, self)
        let minutes = Int(safe) / 60
        let seconds = Int(safe) % 60
        let hundredths = Int((safe - floor(safe)) * 100)
        return String(format: "%02d:%02d.%02d", minutes, seconds, hundredths)
    }

    var timerText: String {
        let total = max(0, Int(ceil(self)))
        return String(format: "%02d:%02d", total / 60, total % 60)
    }

    var smartisanStopwatchText: String {
        let centiseconds = max(0, Int(self * 100))
        return String(format: "%02d:%02d:%02d", centiseconds / 6_000, (centiseconds / 100) % 60, centiseconds % 100)
    }

    var smartisanLapText: String { smartisanStopwatchText }

    var smartisanLapDeltaText: String {
        let centiseconds = max(0, Int(self * 100))
        return String(format: "+%02d:%02d:%02d", centiseconds / 6_000, (centiseconds / 100) % 60, centiseconds % 100)
    }

    var smartisanTimerText: String {
        let total = max(0, Int(ceil(self)))
        return String(format: "%02d:%02d", total / 60, total % 60)
    }
}
