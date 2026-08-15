import SwiftUI

struct AlarmView: View {
    @EnvironmentObject private var store: AlarmStore
    @EnvironmentObject private var service: AlarmKitService
    let isActive: Bool
    @State private var editing = false
    @State private var editedAlarm: UserAlarm?
    @State private var presentsEditor = false
    @State private var message: String?

    var body: some View {
        GeometryReader { geometry in
            TimelineView(.animation(minimumInterval: 1 / 60, paused: !isActive)) { timeline in
                let next = nextEnabledAlarm(after: timeline.date)
                let faceAlarm = next?.alarm ?? store.alarms.first
                ZStack(alignment: .top) {
                    ClockTheme.background

                    MechanicalClockFace(
                        mode: .alarm,
                        date: timeline.date,
                        alarmHour: faceAlarm?.hour ?? 0,
                        alarmMinute: faceAlarm?.minute ?? 0,
                        hasAlarmContent: faceAlarm != nil,
                        isActive: isActive
                    )
                    .position(x: geometry.size.width / 2, y: 266)

                    Text(statusText(next: next, now: timeline.date))
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(ClockTheme.primaryText)
                        .lineLimit(1)
                        .position(x: geometry.size.width / 2, y: 437)

                    if !store.alarms.isEmpty {
                        ScrollView {
                            LazyVStack(spacing: 0) {
                                ForEach(store.alarms) { alarm in
                                    AlarmRow(
                                        alarm: alarm,
                                        editing: editing,
                                        remaining: remainingText(for: alarm, now: timeline.date),
                                        onToggle: { setEnabled(alarm, enabled: $0) },
                                        onDelete: { delete(alarm) },
                                        onEdit: {
                                            editedAlarm = alarm
                                            presentsEditor = true
                                        }
                                    )
                                }
                                Rectangle().fill(ClockTheme.divider).frame(height: 0.67)
                            }
                        }
                        .scrollIndicators(.hidden)
                        .frame(height: max(0, geometry.size.height - 475), alignment: .top)
                        .position(x: geometry.size.width / 2, y: 475 + max(0, geometry.size.height - 475) / 2)
                    }

                    SmartisanTitleBar(
                        title: "闹钟",
                        leading: store.alarms.isEmpty ? nil : SmartisanBarAction(
                            image: editing ? "standard_icon_cancel.png" : "standard_icon_multi_select.png",
                            pressedImage: editing ? "standard_icon_cancel_pressed.png" : "standard_icon_multi_select_pressed.png",
                            accessibilityLabel: editing ? "完成编辑" : "编辑",
                            action: { withAnimation(.easeOut(duration: 0.30)) { editing.toggle() } }
                        ),
                        trailing: SmartisanBarAction(
                            image: "standard_icon_common_add.png",
                            pressedImage: "standard_icon_common_add_pressed.png",
                            accessibilityLabel: "添加闹钟",
                            action: {
                                editedAlarm = nil
                                presentsEditor = true
                            }
                        )
                    )
                }
            }
        }
        .fullScreenCover(isPresented: $presentsEditor) {
            AlarmEditor(alarm: editedAlarm) { alarm in
                if store.alarms.contains(where: { $0.id == alarm.id }) {
                    store.replace(alarm)
                } else {
                    store.add(alarm)
                }
                setEnabled(alarm, enabled: alarm.isEnabled)
            }
        }
        .onAppear {
            guard ProcessInfo.processInfo.arguments.contains("-SmartisanAlarmEditor") else { return }
            editedAlarm = nil
            presentsEditor = true
        }
        .alert("提示", isPresented: Binding(get: { message != nil }, set: { if !$0 { message = nil } })) {
            Button("确定", role: .cancel) { message = nil }
        } message: { Text(message ?? "") }
    }

    private func setEnabled(_ alarm: UserAlarm, enabled: Bool) {
        var changed = alarm
        changed.isEnabled = enabled
        store.replace(changed)
        if enabled {
            Task {
                do { try await service.schedule(changed) }
                catch {
                    changed.isEnabled = false
                    store.replace(changed)
                    message = error.localizedDescription
                }
            }
        } else {
            service.cancel(id: changed.id)
        }
    }

    private func delete(_ alarm: UserAlarm) {
        service.cancel(id: alarm.id)
        withAnimation(.easeOut(duration: 0.20)) { store.remove(alarm) }
    }

    private func nextEnabledAlarm(after date: Date) -> (alarm: UserAlarm, date: Date)? {
        store.alarms
            .filter(\.isEnabled)
            .compactMap { alarm in alarm.nextOccurrence(after: date).map { (alarm, $0) } }
            .min { $0.1 < $1.1 }
    }

    private func statusText(next: (alarm: UserAlarm, date: Date)?, now: Date) -> String {
        guard let next else { return store.alarms.isEmpty ? "还没有设置闹钟" : "没有开启的闹钟" }
        let minutes = max(0, Int(next.date.timeIntervalSince(now) / 60))
        if minutes < 60 { return "将在 \(max(1, minutes)) 分钟后响铃" }
        let hours = minutes / 60
        let rest = minutes % 60
        return rest == 0 ? "将在 \(hours) 小时后响铃" : "将在 \(hours) 小时 \(rest) 分钟后响铃"
    }

    private func remainingText(for alarm: UserAlarm, now: Date) -> String {
        guard alarm.isEnabled, let next = alarm.nextOccurrence(after: now) else { return "" }
        let total = max(0, Int(next.timeIntervalSince(now) / 60))
        if total < 60 { return "\(max(1, total))分钟后" }
        return "\(total / 60)小时\(total % 60)分钟后"
    }
}

private struct AlarmRow: View {
    let alarm: UserAlarm
    let editing: Bool
    let remaining: String
    let onToggle: (Bool) -> Void
    let onDelete: () -> Void
    let onEdit: () -> Void

    var body: some View {
        Button(action: editing ? onEdit : {}) {
            ZStack {
                Rectangle().fill(Color.clear)
                Rectangle().fill(ClockTheme.divider).frame(height: 0.67).frame(maxHeight: .infinity, alignment: .top)

                VStack(alignment: .leading, spacing: 1) {
                    HStack(spacing: 10) {
                        Text(alarm.timeText)
                            .font(.system(size: 20, weight: .bold))
                            .foregroundStyle(alarm.isEnabled ? ClockTheme.alarmRed : Color.black.opacity(0.40))
                        if !remaining.isEmpty {
                            Text(remaining)
                                .font(.system(size: 12, weight: .bold))
                                .foregroundStyle(ClockTheme.title)
                        }
                    }
                    HStack(spacing: 5) {
                        Text(alarm.label).lineLimit(1)
                        Rectangle().fill(Color.black.opacity(0.10)).frame(width: 0.67, height: 10)
                        Text(alarm.repeatText).lineLimit(1)
                    }
                    .font(.system(size: 12))
                    .foregroundStyle(ClockTheme.secondaryText)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.leading, editing ? 52 : 24)
                .padding(.trailing, 86)

                if editing {
                    Button(action: onDelete) {
                        ZStack {
                            Circle().fill(ClockTheme.red)
                            Rectangle().fill(.white).frame(width: 12, height: 2)
                        }
                        .frame(width: 24, height: 24)
                    }
                    .buttonStyle(.plain)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.leading, 14)

                    Image(uiImage: SmartisanAssets.image("setting_item_arrow_normal.png"))
                        .resizable().scaledToFit().frame(width: 24, height: 24)
                        .frame(maxWidth: .infinity, alignment: .trailing).padding(.trailing, 8)
                } else {
                    SmartisanSwitch(isOn: Binding(get: { alarm.isEnabled }, set: onToggle))
                        .frame(maxWidth: .infinity, alignment: .trailing)
                        .padding(.trailing, 8)
                }
            }
            .frame(height: 60)
        }
        .buttonStyle(.plain)
    }
}

private struct SmartisanSwitch: View {
    @Binding var isOn: Bool
    @State private var position: CGFloat = 0
    @GestureState private var drag: CGFloat = 0

    var body: some View {
        let base = isOn ? CGFloat(1) : 0
        let p = min(1, max(0, base + drag / 29.333))
        Canvas { context, _ in
            context.drawLayer { layer in
                let offset = -29.333 + 29.333 * p
                layer.clip(to: Path(roundedRect: CGRect(x: 6, y: 11.67, width: 54, height: 24.67), cornerRadius: 12.33))
                draw(context: &layer, "alarm_repeat_switch_bottom_green.png", x: offset, width: 95.333)
            }
            let offset = -29.333 + 29.333 * p
            draw(context: &context, "alarm_repeat_switch_frame.png", x: 0, width: 66)
            draw(context: &context, "alarm_repeat_switch_unpressed.png", x: offset, width: 95.333)
        }
        .frame(width: 66, height: 48)
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 0)
                .updating($drag) { value, state, _ in state = value.translation.width }
                .onEnded { value in
                    let shouldOn = abs(value.translation.width) < 8.25 ? !isOn : p > 0.5
                    SmartisanHaptics.tick()
                    withAnimation(.easeInOut(duration: 0.18)) { isOn = shouldOn }
                }
        )
        .accessibilityLabel("闹钟开关")
        .accessibilityValue(isOn ? "开启" : "关闭")
    }

    private func draw(context: inout GraphicsContext, _ name: String, x: CGFloat, width: CGFloat) {
        let image = SmartisanAssets.image(name)
        context.draw(context.resolve(Image(uiImage: image)), in: CGRect(x: x, y: 0, width: width, height: 48))
    }
}

private struct AlarmEditor: View {
    @Environment(\.dismiss) private var dismiss
    let original: UserAlarm?
    let onSave: (UserAlarm) -> Void
    @State private var hour: Int
    @State private var minute: Int
    @State private var label: String
    @State private var weekdays: Set<Int>
    @State private var followHolidays: Bool
    @State private var ringtoneTitle: String
    @State private var showsRepeat = false
    @State private var showsRingtone = false
    @State private var showsLabel = false

    init(alarm: UserAlarm?, onSave: @escaping (UserAlarm) -> Void) {
        original = alarm
        self.onSave = onSave
        let now = Calendar.current.date(byAdding: .minute, value: 1, to: Date()) ?? Date()
        let base = alarm ?? UserAlarm(
            hour: Calendar.current.component(.hour, from: now),
            minute: Calendar.current.component(.minute, from: now),
            label: "闹钟",
            weekdays: [],
            isEnabled: true
        )
        _hour = State(initialValue: base.hour)
        _minute = State(initialValue: base.minute)
        _label = State(initialValue: base.label)
        _weekdays = State(initialValue: base.weekdays)
        _followHolidays = State(initialValue: base.followHolidays == true)
        _ringtoneTitle = State(initialValue: base.effectiveRingtoneTitle)
        let arguments = ProcessInfo.processInfo.arguments
        _showsRepeat = State(initialValue: arguments.contains("-SmartisanAlarmRepeat"))
        _showsRingtone = State(initialValue: arguments.contains("-SmartisanRingtonePicker"))
    }

    var body: some View {
        GeometryReader { geometry in
            let top = geometry.safeAreaInsets.top
            ZStack(alignment: .top) {
                Image(uiImage: SmartisanAssets.image("alarm_editor_background_texture.png"))
                    .resizable(resizingMode: .tile)
                    .ignoresSafeArea()
                VStack(spacing: 0) {
                    AlarmEditorTitleBar(
                        title: original == nil ? "添加闹钟" : "编辑闹钟",
                        cancel: { dismiss() },
                        confirm: save
                    )

                    ScrollView {
                        VStack(spacing: 0) {
                            Text(leftTimeText)
                                .font(.system(size: 15, weight: .bold))
                                .foregroundStyle(Color.black.opacity(0.40))
                                .frame(maxWidth: .infinity)
                                .padding(.top, 14)

                            SmartisanTimePicker(hour: $hour, minute: $minute)
                                .frame(height: 208)
                                .padding(.horizontal, 12)
                                .padding(.top, 14)

                            VStack(spacing: 0) {
                                AlarmEditorRow(title: "重复", value: repeatSummary) {
                                    showsRepeat = true
                                }
                                AlarmEditorRow(title: "铃声", value: ringtoneTitle) {
                                    showsRingtone = true
                                }
                                AlarmEditorRow(title: "标签", value: label) {
                                    showsLabel = true
                                }
                            }
                            .background(Color.white)
                            .clipShape(RoundedRectangle(cornerRadius: 3.5))
                            .shadow(color: .black.opacity(0.09), radius: 1, y: 1)
                            .padding(.horizontal, 12)
                            .padding(.top, 14)
                            .padding(.bottom, 24)
                        }
                    }
                    .scrollIndicators(.hidden)
                }
                .padding(.top, top)

                if showsRepeat {
                    SmartisanRepeatDialog(initial: weekdays, followsHolidays: followHolidays) { selected, follows in
                        weekdays = selected
                        followHolidays = follows
                        showsRepeat = false
                    } cancel: {
                        showsRepeat = false
                    }
                    .zIndex(20)
                }

                if showsLabel {
                    SmartisanLabelDialog(initial: label) { value in
                        label = value
                        showsLabel = false
                    } cancel: {
                        showsLabel = false
                    }
                    .zIndex(20)
                }

                if showsRingtone {
                    SmartisanRingtonePicker(selection: $ringtoneTitle, safeTop: top) {
                        showsRingtone = false
                    }
                    .zIndex(20)
                }
            }
            .ignoresSafeArea()
        }
    }

    private var repeatSummary: String {
        let days: String
        if weekdays.isEmpty { days = "仅一次" }
        else if weekdays == Set(1...7) { days = "每天" }
        else { days = weekdays.sorted().map { "周\(weekdayName($0))" }.joined(separator: " ") }
        return followHolidays && !weekdays.isEmpty ? "\(days)\n跟随法定节假、调休日" : days
    }

    private func weekdayName(_ day: Int) -> String { ["一", "二", "三", "四", "五", "六", "日"][day - 1] }

    private var leftTimeText: String {
        let preview = UserAlarm(hour: hour, minute: minute, label: label, weekdays: weekdays, isEnabled: true)
        guard let next = preview.nextOccurrence(after: Date()) else { return "" }
        let total = max(0, Int(next.timeIntervalSinceNow / 60))
        if total == 0 { return "不到 1 分钟后响铃" }
        if total < 60 { return "\(total) 分钟后响铃" }
        if total % 60 == 0 { return "\(total / 60) 小时后响铃" }
        return "\(total / 60) 小时 \(total % 60) 分钟后响铃"
    }

    private func save() {
        var alarm = original ?? UserAlarm(hour: 7, minute: 30, label: "闹钟", weekdays: [], isEnabled: true)
        alarm.hour = hour
        alarm.minute = minute
        alarm.label = label.isEmpty ? "闹钟" : label
        alarm.weekdays = weekdays
        alarm.followHolidays = followHolidays
        alarm.ringtoneTitle = ringtoneTitle
        onSave(alarm)
        dismiss()
    }
}

private struct AlarmEditorTitleBar: View {
    let title: String
    let cancel: () -> Void
    let confirm: () -> Void

    var body: some View {
        ZStack {
            Color.white
            Text(title)
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(ClockTheme.title)
            SmartisanImageButton(
                action: SmartisanBarAction(
                    image: "standard_icon_cancel.png",
                    pressedImage: "standard_icon_cancel_pressed.png",
                    accessibilityLabel: "取消",
                    action: cancel
                ),
                size: 36
            )
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.leading, 6)
            SmartisanImageButton(
                action: SmartisanBarAction(
                    image: "standard_icon_hignlight_confirm.png",
                    pressedImage: "standard_icon_hignlight_confirm_pressed.png",
                    disabledImage: "standard_icon_hignlight_confirm_disabled.png",
                    accessibilityLabel: "保存",
                    action: confirm
                ),
                size: 36
            )
            .frame(maxWidth: .infinity, alignment: .trailing)
            .padding(.trailing, 6)
        }
        .frame(height: 48)
        .overlay(alignment: .bottom) { Rectangle().fill(ClockTheme.divider).frame(height: 0.67) }
        .shadow(color: .black.opacity(0.10), radius: 7, y: 5)
        .zIndex(2)
    }
}

private struct AlarmEditorRow: View {
    let title: String
    let value: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Text(title)
                    .font(.system(size: 18))
                    .foregroundStyle(Color.black.opacity(0.80))
                Spacer()
                Text(value)
                    .font(.system(size: 15))
                    .foregroundStyle(Color.black.opacity(0.40))
                    .lineLimit(2)
                    .multilineTextAlignment(.trailing)
                AlarmEditorChevron()
                    .stroke(
                        Color(red: 136 / 255, green: 136 / 255, blue: 136 / 255),
                        style: StrokeStyle(lineWidth: 1.8, lineCap: .square)
                    )
                    .frame(width: 20, height: 20)
            }
            .padding(.leading, 20)
            .padding(.trailing, 20)
            .frame(height: 60)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .overlay(alignment: .bottom) { Rectangle().fill(Color.black.opacity(0.08)).frame(height: 0.5) }
    }
}

private struct AlarmEditorChevron: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX + 7, y: rect.minY + 4))
        path.addLine(to: CGPoint(x: rect.minX + 13, y: rect.midY))
        path.addLine(to: CGPoint(x: rect.minX + 7, y: rect.maxY - 4))
        return path
    }
}

private struct SmartisanTimePicker: View {
    @Binding var hour: Int
    @Binding var minute: Int
    @State private var activeColumn: Int?
    @State private var scrollOffset: CGFloat = 0
    @State private var lastTranslation: CGFloat = 0
    @State private var motionID = UUID()

    private var is24Hour: Bool {
        let format = DateFormatter.dateFormat(fromTemplate: "j", options: 0, locale: .current) ?? "HH"
        return !format.contains("a")
    }

    var body: some View {
        GeometryReader { geometry in
            let columns = is24Hour ? 2 : 3
            let rowHeight = geometry.size.height / 5
            ZStack {
                Image(uiImage: SmartisanAssets.image(is24Hour ? "alarm_editor_timepicker_2.png" : "alarm_editor_timepicker_3.png"))
                    .resizable()
                Canvas { context, size in
                    for column in 0..<columns {
                        let x = size.width / CGFloat(columns) * (CGFloat(column) + 0.5)
                        for relative in -2...2 {
                            let y = size.height / 2 + CGFloat(relative) * rowHeight + (activeColumn == column ? scrollOffset : 0)
                            let highlight = max(0, min(1, 1 - abs(y - size.height / 2) / rowHeight))
                            let red = (179 + (80 - 179) * highlight) / 255
                            let green = (179 + (121 - 179) * highlight) / 255
                            let blue = (181 + (217 - 181) * highlight) / 255
                            let label = label(column: column, relative: relative)
                            context.draw(
                                Text(label)
                                    .font(.system(size: 15 + 3 * highlight, weight: .bold))
                                    .foregroundStyle(Color(red: red, green: green, blue: blue)),
                                at: CGPoint(x: x, y: y),
                                anchor: .center
                            )
                        }
                    }
                }
            }
            .contentShape(Rectangle())
            .clipped()
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        motionID = UUID()
                        if activeColumn == nil {
                            activeColumn = min(columns - 1, max(0, Int(value.startLocation.x / (geometry.size.width / CGFloat(columns)))))
                            lastTranslation = value.translation.height
                            return
                        }
                        let delta = value.translation.height - lastTranslation
                        lastTranslation = value.translation.height
                        scrollOffset += delta
                        while scrollOffset <= -rowHeight / 2 {
                            scrollOffset += rowHeight
                            step(1)
                        }
                        while scrollOffset >= rowHeight / 2 {
                            scrollOffset -= rowHeight
                            step(-1)
                        }
                    }
                    .onEnded { value in
                        let projected = value.predictedEndTranslation.height - value.translation.height
                        let extra = min(12, max(-12, Int((-projected / rowHeight).rounded())))
                        let id = UUID()
                        motionID = id
                        withAnimation(.easeOut(duration: 0.20)) { scrollOffset = 0 }
                        lastTranslation = 0
                        if extra == 0 {
                            activeColumn = nil
                        } else {
                            let direction = extra > 0 ? 1 : -1
                            Task { @MainActor in
                                for index in 0..<abs(extra) {
                                    guard motionID == id else { return }
                                    try? await Task.sleep(for: .milliseconds(18 + index * 7))
                                    step(direction)
                                }
                                guard motionID == id else { return }
                                activeColumn = nil
                            }
                        }
                    }
            )
        }
        .accessibilityLabel("时间选择器")
        .accessibilityValue(String(format: "%02d:%02d", hour, minute))
    }

    private func step(_ direction: Int) {
        guard let activeColumn else { return }
        switch activeColumn {
        case 0: hour = (hour + direction + 24) % 24
        case 1: minute = (minute + direction + 60) % 60
        case 2: hour = (hour + 12) % 24
        default: break
        }
        SmartisanSoundEffects.shared.play("time_picker", volume: 0.095)
        SmartisanHaptics.tick()
    }

    private func label(column: Int, relative: Int) -> String {
        switch column {
        case 0:
            if is24Hour { return String(format: "%02d", (hour + relative + 24) % 24) }
            let selected = hour % 12 == 0 ? 12 : hour % 12
            return "\((selected - 1 + relative + 12) % 12 + 1)"
        case 1:
            return String(format: "%02d", (minute + relative + 60) % 60)
        case 2:
            let target = (hour >= 12 ? 1 : 0) + relative
            guard target == 0 || target == 1 else { return "" }
            let formatter = DateFormatter()
            return target == 0 ? formatter.amSymbol : formatter.pmSymbol
        default: return ""
        }
    }
}

private struct SmartisanRepeatDialog: View {
    let initial: Set<Int>
    let followsHolidays: Bool
    let confirm: (Set<Int>, Bool) -> Void
    let cancel: () -> Void
    @State private var selected: Set<Int>
    @State private var holidaySelection: Bool

    init(initial: Set<Int>, followsHolidays: Bool, confirm: @escaping (Set<Int>, Bool) -> Void, cancel: @escaping () -> Void) {
        self.initial = initial
        self.followsHolidays = followsHolidays
        self.confirm = confirm
        self.cancel = cancel
        _selected = State(initialValue: initial)
        _holidaySelection = State(initialValue: followsHolidays)
    }

    var body: some View {
        ZStack {
            Color.black.opacity(0.34).ignoresSafeArea().onTapGesture(perform: cancel)
            VStack(spacing: 0) {
                Text("重复")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(ClockTheme.title)
                    .frame(height: 48)
                ForEach(1...7, id: \.self) { day in
                    Button {
                        SmartisanHaptics.tick()
                        if selected.contains(day) { selected.remove(day) } else { selected.insert(day) }
                    } label: {
                        HStack {
                            Text("星期\(["一", "二", "三", "四", "五", "六", "日"][day - 1])")
                                .font(.system(size: 15))
                                .foregroundStyle(ClockTheme.primaryText)
                            Spacer()
                            Image(uiImage: SmartisanAssets.image(selected.contains(day) ? "alarm_repeat_checkbox_on.png" : "alarm_repeat_checkbox_off.png"))
                                .resizable().frame(width: 36, height: 36)
                        }
                        .padding(.horizontal, 12)
                        .frame(height: 48)
                        .background(Color(red: 250 / 255, green: 250 / 255, blue: 250 / 255))
                    }
                    .buttonStyle(.plain)
                    .overlay(alignment: .top) { Rectangle().fill(ClockTheme.divider).frame(height: 0.67) }
                }
                HStack {
                    Text("跟随法定节假、调休日")
                        .font(.system(size: 15))
                        .foregroundStyle(selected.isEmpty ? Color.black.opacity(0.24) : ClockTheme.primaryText)
                    Spacer()
                    SmartisanSwitch(isOn: $holidaySelection)
                        .disabled(selected.isEmpty)
                        .opacity(selected.isEmpty ? 0.38 : 1)
                }
                .padding(.leading, 18)
                .padding(.trailing, 8)
                .frame(height: 48)
                .background(ClockTheme.background)
                .overlay(alignment: .top) { Rectangle().fill(ClockTheme.divider).frame(height: 0.67) }
                HStack(spacing: 0) {
                    Button("取消", action: cancel).frame(maxWidth: .infinity)
                    Button("确定") { confirm(selected, holidaySelection && !selected.isEmpty) }.frame(maxWidth: .infinity)
                }
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(ClockTheme.switchBlue)
                .frame(height: 48)
            }
            .frame(maxWidth: 330)
            .background(Color.white)
            .clipShape(RoundedRectangle(cornerRadius: 4))
            .shadow(color: .black.opacity(0.26), radius: 16, y: 7)
            .padding(.horizontal, 18)
        }
    }
}

private struct SmartisanLabelDialog: View {
    let initial: String
    let confirm: (String) -> Void
    let cancel: () -> Void
    @State private var value: String

    init(initial: String, confirm: @escaping (String) -> Void, cancel: @escaping () -> Void) {
        self.initial = initial
        self.confirm = confirm
        self.cancel = cancel
        _value = State(initialValue: initial)
    }

    var body: some View {
        ZStack {
            Color.black.opacity(0.34).ignoresSafeArea().onTapGesture(perform: cancel)
            VStack(spacing: 0) {
                Text("标签")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(ClockTheme.title)
                    .frame(height: 48)
                HStack(spacing: 6) {
                    TextField("闹钟", text: $value)
                        .font(.system(size: 16))
                    Button { value = "" } label: {
                        Image(uiImage: SmartisanAssets.image("alarm_label_clear_normal.png"))
                            .resizable().frame(width: 36, height: 36)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 12)
                .frame(height: 58)
                .background(ClockTheme.background)
                HStack(spacing: 0) {
                    Button("取消", action: cancel).frame(maxWidth: .infinity)
                    Button("确定") { if !value.trimmingCharacters(in: .whitespaces).isEmpty { confirm(value.trimmingCharacters(in: .whitespaces)) } }
                        .disabled(value.trimmingCharacters(in: .whitespaces).isEmpty)
                        .frame(maxWidth: .infinity)
                }
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(ClockTheme.switchBlue)
                .frame(height: 48)
            }
            .frame(maxWidth: 330)
            .background(Color.white)
            .clipShape(RoundedRectangle(cornerRadius: 4))
            .shadow(color: .black.opacity(0.26), radius: 16, y: 7)
            .padding(.horizontal, 18)
        }
    }
}

private struct SmartisanRingtonePicker: View {
    @Binding var selection: String
    let safeTop: CGFloat
    let dismiss: () -> Void
    private let choices = ["计时器", "铃铛", "经典"]

    var body: some View {
        ZStack(alignment: .top) {
            Image(uiImage: SmartisanAssets.image("ringtone_picker_common_bg.png"))
                .resizable(resizingMode: .tile)
                .ignoresSafeArea()
            VStack(spacing: 0) {
                SmartisanTitleBar(
                    title: "铃声",
                    leading: SmartisanBarAction(
                        image: "ringtone_picker_back_normal.png",
                        pressedImage: "ringtone_picker_back_pressed.png",
                        accessibilityLabel: "返回",
                        action: dismiss
                    )
                )
                VStack(spacing: 0) {
                    ForEach(Array(choices.enumerated()), id: \.element) { index, choice in
                        Button {
                            selection = choice
                            SmartisanSoundEffects.shared.play(choice == "计时器" ? "timer" : (choice == "铃铛" ? "ruler_ring" : "ruler_back"))
                        } label: {
                            HStack {
                                Text(choice).font(.system(size: 17)).foregroundStyle(Color.black.opacity(0.70))
                                Spacer()
                                if selection == choice {
                                    Image(uiImage: SmartisanAssets.image("ringtone_picker_radio_normal.png"))
                                        .resizable().frame(width: 27, height: 27)
                                } else {
                                    Color.clear.frame(width: 27, height: 27)
                                }
                            }
                            .padding(.leading, 18)
                            .padding(.trailing, 6)
                            .frame(height: 60)
                            .background {
                                Image(uiImage: SmartisanAssets.image(index == 0 ? "ringtone_picker_group_top.png" : (index == choices.count - 1 ? "ringtone_picker_group_bottom.png" : "ringtone_picker_group_middle.png")))
                                    .resizable(capInsets: EdgeInsets(top: 8, leading: 8, bottom: 8, trailing: 8), resizingMode: .stretch)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.top, 14)
                Spacer()
            }
            .padding(.top, safeTop)
        }
        .ignoresSafeArea()
    }
}
