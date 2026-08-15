import SwiftUI

struct WorldClockView: View {
    @EnvironmentObject private var store: CityStore
    let isActive: Bool
    @State private var showsCities = false
    @State private var editing = false

    var body: some View {
        GeometryReader { geometry in
            TimelineView(.animation(minimumInterval: 1 / 60, paused: !isActive)) { timeline in
                ZStack(alignment: .top) {
                    ClockTheme.background

                    MechanicalClockFace(
                        mode: .world,
                        date: timeline.date,
                        timeZone: .current,
                        isActive: isActive
                    )
                    .position(x: geometry.size.width / 2, y: 266)

                    Text("本地时间")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(ClockTheme.primaryText)
                        .position(x: geometry.size.width / 2, y: 410)

                    Text(localDateText(timeline.date))
                        .font(.system(size: 12))
                        .foregroundStyle(ClockTheme.secondaryText)
                        .position(x: geometry.size.width / 2, y: 438)

                    if !store.cities.isEmpty {
                        ScrollView(.vertical) {
                            LazyVStack(spacing: 0) {
                                ForEach(store.cities) { city in
                                    WorldCityRow(city: city, date: timeline.date, editing: editing) {
                                        store.remove(city)
                                    }
                                }
                            }
                        }
                        .scrollIndicators(.hidden)
                        .frame(height: max(0, geometry.size.height - 461), alignment: .top)
                        .position(x: geometry.size.width / 2, y: 461 + max(0, geometry.size.height - 461) / 2)
                    }

                    SmartisanTitleBar(
                        title: "世界时钟",
                        leading: store.cities.isEmpty ? nil : SmartisanBarAction(
                            image: editing ? "standard_icon_cancel.png" : "standard_icon_multi_select.png",
                            pressedImage: editing ? "standard_icon_cancel_pressed.png" : "standard_icon_multi_select_pressed.png",
                            accessibilityLabel: editing ? "完成编辑" : "编辑",
                            action: { withAnimation(.easeOut(duration: 0.30)) { editing.toggle() } }
                        ),
                        trailing: SmartisanBarAction(
                            image: "standard_icon_common_add.png",
                            pressedImage: "standard_icon_common_add_pressed.png",
                            accessibilityLabel: "添加城市",
                            action: { showsCities = true }
                        )
                    )
                }
            }
        }
        .fullScreenCover(isPresented: $showsCities) { SmartisanCityPicker() }
    }

    private func localDateText(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "M月d日 EEEE"
        return formatter.string(from: date)
    }
}

private struct WorldCityRow: View {
    let city: WorldCity
    let date: Date
    let editing: Bool
    let delete: () -> Void

    var body: some View {
        ZStack {
            Rectangle().fill(Color.clear)
            Rectangle().fill(ClockTheme.divider).frame(height: 0.67).frame(maxHeight: .infinity, alignment: .top)

            Text(city.name)
                .font(.system(size: city.name.count > 4 ? 15 : 17, weight: .bold))
                .foregroundStyle(ClockTheme.primaryText)
                .lineLimit(1)
                .frame(maxWidth: 112, alignment: .leading)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.leading, editing ? 52 : 24)

            SmallMechanicalClockFace(date: date, timeZone: city.timeZone)

            VStack(alignment: .trailing, spacing: 1) {
                Text(timeText)
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(ClockTheme.alarmRed)
                HStack(spacing: 5) {
                    Text(dayText)
                    Rectangle().fill(Color.black.opacity(0.10)).frame(width: 0.67, height: 10)
                    Text(relativeOffset)
                }
                .font(.system(size: 12))
                .foregroundStyle(ClockTheme.secondaryText)
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
            .padding(.trailing, 19)

            if editing {
                Button(action: delete) {
                    ZStack {
                        Circle().fill(ClockTheme.red)
                        Rectangle().fill(.white).frame(width: 12, height: 2)
                    }
                    .frame(width: 24, height: 24)
                }
                .buttonStyle(.plain)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.leading, 14)
                .transition(.move(edge: .leading).combined(with: .opacity))
            }
        }
        .frame(height: 60)
        .clipped()
    }

    private var timeText: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        formatter.timeZone = city.timeZone
        return formatter.string(from: date)
    }

    private var dayText: String {
        var local = Calendar.current
        var remote = Calendar.current
        remote.timeZone = city.timeZone
        let localDay = local.startOfDay(for: date)
        let remoteParts = remote.dateComponents([.year, .month, .day], from: date)
        let remoteDay = local.date(from: remoteParts) ?? localDay
        let difference = local.dateComponents([.day], from: localDay, to: remoteDay).day ?? 0
        return difference > 0 ? "明天" : (difference < 0 ? "昨天" : "今天")
    }

    private var relativeOffset: String {
        let offset = city.timeZone.secondsFromGMT(for: date) - TimeZone.current.secondsFromGMT(for: date)
        if offset == 0 { return "同一时间" }
        let hours = abs(offset) / 3600
        return "\(offset > 0 ? "+" : "−")\(hours)小时"
    }
}

private struct SmartisanCityPicker: View {
    @EnvironmentObject private var store: CityStore
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""

    var body: some View {
        GeometryReader { geometry in
            let top = geometry.safeAreaInsets.top
            ZStack(alignment: .top) {
                ClockTheme.background.ignoresSafeArea()
                VStack(spacing: 0) {
                    SmartisanTitleBar(
                        title: "添加城市",
                        leading: SmartisanBarAction(
                            image: "standard_icon_cancel.png",
                            pressedImage: "standard_icon_cancel_pressed.png",
                            accessibilityLabel: "返回",
                            action: { dismiss() }
                        )
                    )
                    HStack(spacing: 8) {
                        Image(systemName: "magnifyingglass").foregroundStyle(ClockTheme.hintText)
                        TextField("搜索城市", text: $query)
                            .font(.system(size: 15))
                    }
                    .padding(.horizontal, 12)
                    .frame(height: 32)
                    .background(RoundedRectangle(cornerRadius: 8).fill(.white).stroke(Color.black.opacity(0.10)))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 9)

                    ScrollView {
                        LazyVStack(spacing: 0) {
                            ForEach(filtered) { city in
                                Button {
                                    store.add(city)
                                    dismiss()
                                } label: {
                                    HStack {
                                        Text(city.name).font(.system(size: 17, weight: .bold)).foregroundStyle(ClockTheme.primaryText)
                                        Spacer()
                                        Text(city.country).font(.system(size: 12)).foregroundStyle(ClockTheme.secondaryText)
                                    }
                                    .padding(.horizontal, 20)
                                    .frame(height: 60)
                                    .overlay(alignment: .top) { Rectangle().fill(ClockTheme.divider).frame(height: 0.67) }
                                }
                                .buttonStyle(.plain)
                                .disabled(store.cities.contains(city))
                                .opacity(store.cities.contains(city) ? 0.35 : 1)
                            }
                        }
                    }
                }
                .padding(.top, top)
            }
            .ignoresSafeArea()
        }
    }

    private var filtered: [WorldCity] {
        guard !query.isEmpty else { return CityStore.catalog }
        return CityStore.catalog.filter { $0.searchText.localizedCaseInsensitiveContains(query) }
    }
}
