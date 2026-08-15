import SwiftUI

struct SmartisanRingingView: View {
    let label: String
    let alarmHour: Int
    let alarmMinute: Int
    let dismiss: () -> Void
    let snooze: () -> Void

    @State private var revealed = false
    @State private var entranceOffset: CGFloat = -509
    @State private var dragOffset: CGFloat = 0

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                Color.black.opacity(0.60).ignoresSafeArea()

                TimelineView(.animation(minimumInterval: 1 / 120, paused: !revealed)) { timeline in
                    ringingPanel(date: timeline.date)
                }
                .frame(width: 316, height: 509)
                .offset(y: entranceOffset + dragOffset)
                .opacity(revealed ? 1 : 0)
                .contentShape(RoundedRectangle(cornerRadius: 16))
                .gesture(panelGesture(screenHeight: geometry.size.height))
            }
            .task {
                guard !revealed else { return }
                try? await Task.sleep(for: .milliseconds(500))
                revealed = true
                entranceOffset = -509
                try? await Task.sleep(for: .milliseconds(16))
                withAnimation(.easeOut(duration: 0.30)) { entranceOffset = 0 }
            }
            .onAppear { SmartisanSoundEffects.shared.setLoop("timer", playing: true) }
            .onDisappear { SmartisanSoundEffects.shared.setLoop("timer", playing: false) }
        }
    }

    private func ringingPanel(date: Date) -> some View {
        ZStack(alignment: .top) {
            RoundedRectangle(cornerRadius: 16)
                .fill(
                    LinearGradient(
                        colors: [.white, Color(red: 245 / 255, green: 245 / 255, blue: 245 / 255)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .overlay { RoundedRectangle(cornerRadius: 16).stroke(Color.black.opacity(0.071), lineWidth: 0.5) }

            Rectangle()
                .fill(Color(red: 227 / 255, green: 227 / 255, blue: 227 / 255))
                .frame(width: 314, height: 1)
                .offset(y: 465)

            Text(label)
                .font(.system(size: 18))
                .foregroundStyle(Color.black.opacity(0.40))
                .lineLimit(1)
                .frame(maxWidth: 210)
                .position(x: 158, y: 71)

            AlarmRingingEars(date: date)
                .frame(width: 200, height: 77.7)
                .position(x: 158, y: 102 + 77.7 / 2)

            CompactRingingClock(
                date: date,
                alarmHour: alarmHour,
                alarmMinute: alarmMinute
            )
            .frame(width: 188, height: 196.1)
            .position(x: 158, y: 102 + 196.1 / 2)

            HStack(alignment: .lastTextBaseline, spacing: 2) {
                Text(currentTimeText(date))
                    .font(SmartisanAssets.font(.light, size: 30))
                if !uses24HourTime {
                    Text(Calendar.current.component(.hour, from: date) >= 12 ? "PM" : "AM")
                        .font(.system(size: 13.5))
                }
            }
            .foregroundStyle(ClockTheme.red)
            .position(x: 158, y: 362)

            Button { finish(snooze) } label: {
                ZStack {
                    Image(uiImage: SmartisanAssets.image("alarm_ringing_snooze_normal.png"))
                        .resizable().frame(width: 210, height: 80)
                    Text("贪睡")
                        .font(.system(size: 13.5, weight: .medium))
                        .foregroundStyle(Color.white)
                        .shadow(color: .black.opacity(0.15), radius: 2, y: 2)
                }
            }
            .buttonStyle(AlarmSnoozeButtonStyle())
            .frame(width: 210, height: 80)
            .position(x: 158, y: 424.5)

            Text("向上滑动关闭闹钟")
                .font(.system(size: 12))
                .foregroundStyle(Color.black.opacity(0.40))
                .frame(height: 42.5)
                .position(x: 158, y: 487.75)
        }
        .frame(width: 316, height: 509)
        .clipped(antialiased: true)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(label)，\(currentTimeText(date))，向上滑动关闭闹钟")
    }

    private func panelGesture(screenHeight: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 2)
            .onChanged { value in
                guard revealed else { return }
                let raw = value.translation.height
                if raw <= 0 {
                    dragOffset = raw
                } else {
                    let available = max(509, screenHeight)
                    let resistance = max(0, 1 - 2 * raw / available)
                    dragOffset = raw * resistance
                }
            }
            .onEnded { value in
                let projected = value.predictedEndTranslation.height
                let shouldDismiss = dragOffset <= -screenHeight / 3 || projected < -180
                if shouldDismiss {
                    withAnimation(.easeOut(duration: 0.30)) {
                        entranceOffset = -screenHeight
                        dragOffset = 0
                    }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.30) { finish(dismiss) }
                } else {
                    withAnimation(.easeOut(duration: 0.30)) { dragOffset = 0 }
                }
            }
    }

    private var uses24HourTime: Bool {
        let format = DateFormatter.dateFormat(fromTemplate: "j", options: 0, locale: .current) ?? "HH"
        return !format.contains("a")
    }

    private func finish(_ action: () -> Void) {
        SmartisanSoundEffects.shared.setLoop("timer", playing: false)
        action()
    }

    private func currentTimeText(_ date: Date) -> String {
        let components = Calendar.current.dateComponents([.hour, .minute], from: date)
        let sourceHour = components.hour ?? 0
        let displayHour = uses24HourTime ? sourceHour : ((sourceHour % 12 == 0) ? 12 : sourceHour % 12)
        return String(format: "%d:%02d", displayHour, components.minute ?? 0)
    }
}

private struct AlarmSnoozeButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        ZStack {
            Image(uiImage: SmartisanAssets.image(configuration.isPressed ? "alarm_ringing_snooze_pressed.png" : "alarm_ringing_snooze_normal.png"))
                .resizable().frame(width: 210, height: 80)
            configuration.label.opacity(0)
            Text("贪睡")
                .font(.system(size: 13.5, weight: .medium))
                .foregroundStyle(Color.white)
                .shadow(color: .black.opacity(0.15), radius: 2, y: 2)
        }
    }
}

private struct AlarmRingingEars: View {
    let date: Date

    var body: some View {
        let position = date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 0.064) / 0.016
        let current = Int(floor(position)) % 4
        let next = (current + 1) % 4
        let blend = position - floor(position)
        ZStack {
            ear(current).opacity(1 - blend)
            ear(next).opacity(blend).blendMode(.plusLighter)
        }
    }

    private func ear(_ index: Int) -> some View {
        Image(uiImage: SmartisanAssets.image(String(format: "alarm_ringing_ear_%04d.png", index + 1)))
            .resizable()
            .frame(width: 200, height: 77.7)
    }
}

private struct CompactRingingClock: View {
    let date: Date
    let alarmHour: Int
    let alarmMinute: Int

    var body: some View {
        Canvas { context, _ in
            let base = CGSize(width: 188, height: 196.1)
            let center = CGPoint(x: base.width / 2, y: base.height / 2)
            let calendar = Calendar.current
            let hour = CGFloat(calendar.component(.hour, from: date))
            let minute = CGFloat(calendar.component(.minute, from: date))
            let nanosecond = CGFloat(calendar.component(.nanosecond, from: date)) / 1_000_000_000
            let secondWhole = CGFloat(calendar.component(.second, from: date))
            let rebound = max(0, 1 - nanosecond / 0.05) * 0.2
            let second = secondWhole + rebound
            let night = alarmHour >= 18 || alarmHour < 6

            drawCentered(context: &context, name: "alarm_ringing_clock_face.png", center: center)
            if night { drawCentered(context: &context, name: "alarm_ringing_clock_face_night.png", center: center) }
            drawImage(context: &context, name: night ? "alarm_ringing_clock_12_night.png" : "alarm_ringing_clock_12.png", x: center.x, y: 30, anchor: .top)
            let three = SmartisanAssets.image(night ? "alarm_ringing_clock_3_night.png" : "alarm_ringing_clock_3.png")
            context.draw(context.resolve(Image(uiImage: three)), in: CGRect(x: base.width - 25 - three.size.width, y: center.y - three.size.height / 2, width: three.size.width, height: three.size.height))

            drawHand(context: &context, hand: "alarm_ringing_alarm_hand.png", shadow: "alarm_ringing_alarm_shadow.png", degrees: (CGFloat(alarmHour) + CGFloat(alarmMinute) / 60) * 30, anchor: 152 / 184, center: center)
            drawHand(context: &context, hand: night ? "alarm_ringing_hour_hand_night.png" : "alarm_ringing_hour_hand.png", shadow: "alarm_ringing_hour_shadow.png", degrees: (hour.truncatingRemainder(dividingBy: 12) + minute / 60) * 30, anchor: 6.9 / 8, center: center)
            drawHand(context: &context, hand: night ? "alarm_ringing_minute_hand_night.png" : "alarm_ringing_minute_hand.png", shadow: "alarm_ringing_minute_shadow.png", degrees: (minute + second / 60) * 6, anchor: 6.9 / 8, center: center)
            drawCentered(context: &context, name: night ? "alarm_ringing_hand_center_night.png" : "alarm_ringing_hand_center.png", center: center)
            drawHand(context: &context, hand: "alarm_ringing_second_hand.png", shadow: "alarm_ringing_second_shadow.png", degrees: second * 6, anchor: 6.5 / 8, center: center)
            drawCentered(context: &context, name: "alarm_ringing_hand_center_middle.png", center: center)
        }
    }

    private func drawCentered(context: inout GraphicsContext, name: String, center: CGPoint) {
        let image = SmartisanAssets.image(name)
        context.draw(context.resolve(Image(uiImage: image)), in: CGRect(x: center.x - image.size.width / 2, y: center.y - image.size.height / 2, width: image.size.width, height: image.size.height))
    }

    private func drawImage(context: inout GraphicsContext, name: String, x: CGFloat, y: CGFloat, anchor: UnitPoint) {
        let image = SmartisanAssets.image(name)
        let originX = x - image.size.width * anchor.x
        let originY = y - image.size.height * anchor.y
        context.draw(context.resolve(Image(uiImage: image)), in: CGRect(x: originX, y: originY, width: image.size.width, height: image.size.height))
    }

    private func drawHand(context: inout GraphicsContext, hand: String, shadow: String, degrees: CGFloat, anchor: CGFloat, center: CGPoint) {
        let handImage = SmartisanAssets.image(hand)
        let shadowImage = SmartisanAssets.image(shadow)
        let radians = degrees * .pi / 180
        context.drawLayer { layer in
            layer.translateBy(x: center.x, y: center.y)
            layer.rotate(by: .degrees(degrees))
            let shadowRect = CGRect(
                x: -shadowImage.size.width / 2 + sin(radians) * 6,
                y: -shadowImage.size.height * anchor + cos(radians) * 6,
                width: shadowImage.size.width,
                height: shadowImage.size.height
            )
            layer.draw(layer.resolve(Image(uiImage: shadowImage)), in: shadowRect)
            layer.draw(layer.resolve(Image(uiImage: handImage)), in: CGRect(x: -handImage.size.width / 2, y: -handImage.size.height * anchor, width: handImage.size.width, height: handImage.size.height))
        }
    }
}
