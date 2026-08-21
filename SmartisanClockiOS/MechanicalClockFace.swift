import SwiftUI
import UIKit

enum SmartisanClockFaceMode {
    case world, alarm, stopwatch, timer
}

struct MechanicalClockFace: View {
    var mode: SmartisanClockFaceMode
    var date: Date = .now
    var timeZone: TimeZone = .current
    var stopwatchSeconds: TimeInterval = 0
    var timerMinutes: Double = 0
    var alarmHour: Int = 7
    var alarmMinute: Int = 30
    var hasAlarmContent = true
    var isActive = true

    @State private var entranceStart = Date()

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 60, paused: !isActive)) { timeline in
            Canvas(opaque: false, colorMode: .nonLinear, rendersAsynchronously: mode != .timer) { context, _ in
                drawClock(context: &context, timelineDate: timeline.date)
            }
        }
        .frame(width: 360, height: 400)
        .onAppear { entranceStart = Date() }
        .onChange(of: isActive) { _, active in
            if active { entranceStart = Date() }
        }
        .accessibilityHidden(true)
    }

    private func drawClock(context: inout GraphicsContext, timelineDate: Date) {
        let base = CGSize(width: 360, height: 400)
        let center = CGPoint(x: 180, y: 200)
        let elapsed = max(0, timelineDate.timeIntervalSince(entranceStart))
        let components = clockComponents
        var hour = components.hour
        var minute = components.minute
        var second = components.second

        let dialAlpha: Double
        let topAlpha: Double
        let rightAlpha: Double
        let hourAlpha: Double
        let minuteAlpha: Double
        let secondAlpha: Double
        let alarmAlpha: Double
        var earTravel = 0.0

        switch mode {
        case .world, .alarm:
            hour -= 2 * (1 - easeOut(elapsed / 0.7))
            minute -= 15 * (1 - easeOut(elapsed / 0.9))
            second -= 20 * (1 - easeOut(elapsed / 1.0))
            dialAlpha = easeOut(elapsed / 0.3)
            topAlpha = dialAlpha
            rightAlpha = dialAlpha
            hourAlpha = easeOut(elapsed / 0.7)
            minuteAlpha = easeOut(elapsed / 0.9)
            secondAlpha = easeOut(elapsed / 1.0)
            alarmAlpha = mode == .alarm ? easeOut(elapsed / 1.0) : 1
            if mode == .alarm {
                let earDuration = hasAlarmContent ? 0.7 : 0.3
                earTravel = 1 - easeOut(elapsed / earDuration)
            }
        case .stopwatch:
            dialAlpha = easeOut(elapsed / 0.3)
            topAlpha = easeOut(elapsed / 0.5)
            rightAlpha = easeOut(max(0, elapsed - 0.13) / 0.5)
            hourAlpha = 1
            minuteAlpha = 1
            secondAlpha = easeOut(elapsed / 0.3)
            alarmAlpha = 1
        case .timer:
            dialAlpha = easeOut(elapsed / 0.3)
            topAlpha = dialAlpha
            rightAlpha = dialAlpha
            hourAlpha = 1
            minuteAlpha = easeOut(elapsed / 0.3)
            secondAlpha = 1
            alarmAlpha = 1
        }

        if mode == .alarm {
            drawAlarmEars(context: &context, travel: earTravel, alpha: hasAlarmContent ? easeOut(elapsed / 0.7) : easeOut(elapsed / 0.3))
        }

        drawCentered(context: &context, name: "blank_clock.png", in: base)

        switch mode {
        case .world, .alarm:
            drawImage(context: &context, name: "d12.png", origin: CGPoint(x: centeredX("d12.png", width: base.width), y: 108), alpha: topAlpha)
            let d3 = SmartisanAssets.image("d3.png")
            drawImage(context: &context, name: "d3.png", origin: CGPoint(x: base.width - 84.6 - d3.size.width, y: (base.height - d3.size.height) / 2), alpha: rightAlpha)
        case .stopwatch, .timer:
            drawCentered(context: &context, name: "degree.png", in: base, alpha: dialAlpha)
            drawImage(context: &context, name: "d60.png", origin: CGPoint(x: centeredX("d60.png", width: base.width), y: 110), alpha: topAlpha)
            let d15 = SmartisanAssets.image("d15.png")
            drawImage(context: &context, name: "d15.png", origin: CGPoint(x: base.width - 93 - d15.size.width, y: (base.height - d15.size.height) / 2), alpha: rightAlpha)
        }

        switch mode {
        case .world:
            drawHand(context: &context, hand: "hour_hand.png", shadow: "hour_hand_shadow.png", degrees: hour * 30 + minute * 0.5, alpha: hourAlpha, anchor: 6.9 / 8, center: center)
            drawHand(context: &context, hand: "minute_hand.png", shadow: "minute_hand_shadow.png", degrees: minute * 6 + second * 0.1, alpha: minuteAlpha, anchor: 6.9 / 8, center: center)
            drawCenter(context: &context, name: "hand_center.png", center: center)
            drawHand(context: &context, hand: "sec_hand.png", shadow: "sec_hand_shadow.png", degrees: second * 6, alpha: secondAlpha, anchor: 6.5 / 8, center: center)
            drawCenter(context: &context, name: "hand_center_middle.png", center: center, alpha: secondAlpha)
        case .alarm:
            let alarmTarget = Double(alarmHour % 12) + Double(alarmMinute) / 60
            let alarmDisplay = alarmTarget - 8 * (1 - easeOut(elapsed / 1.0))
            drawHand(context: &context, hand: "alarmpointer.png", shadow: "alarmpointer_shadow.png", degrees: alarmDisplay * 30, alpha: alarmAlpha, anchor: 152 / 184, center: center)
            drawHand(context: &context, hand: "hour_hand.png", shadow: "hour_hand_shadow.png", degrees: hour * 30 + minute * 0.5, alpha: hourAlpha, anchor: 6.9 / 8, center: center)
            drawHand(context: &context, hand: "minute_hand.png", shadow: "minute_hand_shadow.png", degrees: minute * 6 + second * 0.1, alpha: minuteAlpha, anchor: 6.9 / 8, center: center)
            drawCenter(context: &context, name: "hand_center.png", center: center)
            drawHand(context: &context, hand: "sec_hand.png", shadow: "sec_hand_shadow.png", degrees: second * 6, alpha: secondAlpha, anchor: 6.5 / 8, center: center)
            drawCenter(context: &context, name: "hand_center_middle.png", center: center, alpha: secondAlpha)
        case .stopwatch:
            drawCenter(context: &context, name: "hand_center.png", center: center)
            drawHand(context: &context, hand: "sec_hand.png", shadow: "sec_hand_shadow.png", degrees: stopwatchSeconds.truncatingRemainder(dividingBy: 60) * 6, alpha: secondAlpha, anchor: 6.5 / 8, center: center)
            drawCenter(context: &context, name: "hand_center_middle.png", center: center, alpha: secondAlpha)
        case .timer:
            drawHand(context: &context, hand: "minute_hand.png", shadow: "minute_hand_shadow.png", degrees: timerMinutes.truncatingRemainder(dividingBy: 60) * 6, alpha: minuteAlpha, anchor: 6.9 / 8, center: center)
            drawCenter(context: &context, name: "hand_center.png", center: center)
        }
    }

    private var clockComponents: (hour: Double, minute: Double, second: Double) {
        switch mode {
        case .stopwatch:
            return (0, 0, stopwatchSeconds)
        case .timer:
            return (0, timerMinutes, 0)
        case .world, .alarm:
            var calendar = Calendar(identifier: .gregorian)
            calendar.timeZone = timeZone
            let values = calendar.dateComponents([.hour, .minute, .second, .nanosecond], from: date)
            let rawSecond = Double(values.second ?? 0) + Double(values.nanosecond ?? 0) / 1_000_000_000
            let fraction = rawSecond - floor(rawSecond)
            let bounce = fraction < 0.1 ? 0.15 * (1 - easeOut(fraction / 0.1)) : 0
            let second = floor(rawSecond) + bounce
            let minute = Double(values.minute ?? 0) + rawSecond / 60
            let hour = Double((values.hour ?? 0) % 12) + minute / 60
            return (hour, minute, second)
        }
    }

    private func drawAlarmEars(context: inout GraphicsContext, travel: Double, alpha: Double) {
        let left = SmartisanAssets.image("big_left.png")
        let right = SmartisanAssets.image("big_right.png")
        let delta = 52.67 * travel
        drawImage(context: &context, name: "big_left.png", origin: CGPoint(x: 61 + delta, y: 83 + delta), alpha: alpha)
        drawImage(context: &context, name: "big_right.png", origin: CGPoint(x: 360 - 61 - right.size.width - delta, y: 83 + delta), alpha: alpha)
        _ = left
    }

    private func drawHand(context: inout GraphicsContext, hand: String, shadow: String, degrees: Double, alpha: Double, anchor: CGFloat, center: CGPoint) {
        guard alpha > 0 else { return }
        let handImage = SmartisanAssets.image(hand)
        let shadowImage = SmartisanAssets.image(shadow)
        let radians = degrees * .pi / 180
        context.drawLayer { layer in
            layer.opacity = alpha
            layer.translateBy(x: center.x, y: center.y)
            layer.rotate(by: .degrees(degrees))
            layer.draw(
                layer.resolve(Image(uiImage: shadowImage)),
                in: CGRect(x: -handImage.size.width / 2 + sin(radians) * 6, y: -handImage.size.height * anchor + cos(radians) * 6, width: shadowImage.size.width, height: shadowImage.size.height)
            )
            layer.draw(
                layer.resolve(Image(uiImage: handImage)),
                in: CGRect(x: -handImage.size.width / 2, y: -handImage.size.height * anchor, width: handImage.size.width, height: handImage.size.height)
            )
        }
    }

    private func drawCenter(context: inout GraphicsContext, name: String, center: CGPoint, alpha: Double = 1) {
        let image = SmartisanAssets.image(name)
        drawImage(context: &context, name: name, origin: CGPoint(x: center.x - image.size.width / 2, y: center.y - image.size.height / 2), alpha: alpha)
    }

    private func drawCentered(context: inout GraphicsContext, name: String, in base: CGSize, alpha: Double = 1) {
        let image = SmartisanAssets.image(name)
        drawImage(context: &context, name: name, origin: CGPoint(x: (base.width - image.size.width) / 2, y: (base.height - image.size.height) / 2), alpha: alpha)
    }

    private func drawImage(context: inout GraphicsContext, name: String, origin: CGPoint, alpha: Double = 1) {
        let image = SmartisanAssets.image(name)
        context.drawLayer { layer in
            layer.opacity = alpha
            layer.draw(layer.resolve(Image(uiImage: image)), in: CGRect(origin: origin, size: image.size))
        }
    }

    private func centeredX(_ name: String, width: CGFloat) -> CGFloat {
        (width - SmartisanAssets.image(name).size.width) / 2
    }

    private func easeOut(_ value: Double) -> Double {
        let bounded = min(1, max(0, value))
        return 1 - pow(1 - bounded, 2)
    }
}

struct SmallMechanicalClockFace: View {
    let date: Date
    let timeZone: TimeZone

    var body: some View {
        Canvas { context, size in
            var calendar = Calendar(identifier: .gregorian)
            calendar.timeZone = timeZone
            let values = calendar.dateComponents([.hour, .minute, .second], from: date)
            let hour = Double(values.hour ?? 0)
            let minute = Double(values.minute ?? 0)
            let second = Double(values.second ?? 0)
            let night = hour >= 18 || hour < 6
            let center = CGPoint(x: size.width / 2, y: size.height / 2)

            drawCentered(context: &context, name: night ? "small_blank_clock_black.png" : "small_blank_clock.png", center: center)
            drawHand(context: &context, hand: night ? "small_hour_hand_black.png" : "small_hour_hand.png", shadow: "small_hour_hand_shadow.png", units: ((hour.truncatingRemainder(dividingBy: 12) + minute / 60) / 12) * 60, anchor: 6.7 / 8, center: center)
            drawHand(context: &context, hand: night ? "small_minute_hand_black.png" : "small_minute_hand.png", shadow: "small_minute_hand_shadow.png", units: minute + second / 60, anchor: 7.2 / 8, center: center)
            drawCentered(context: &context, name: night ? "small_hand_center_black.png" : "small_hand_center.png", center: center)
            drawHand(context: &context, hand: "small_sec_hand.png", shadow: "small_sec_hand_shadow.png", units: second, anchor: 6.5 / 8, center: center)
            drawCentered(context: &context, name: "small_hand_center_middle.png", center: center)
        }
        .frame(width: 60, height: 60)
    }

    private func drawCentered(context: inout GraphicsContext, name: String, center: CGPoint) {
        let image = SmartisanAssets.image(name)
        context.draw(context.resolve(Image(uiImage: image)), in: CGRect(x: center.x - image.size.width / 2, y: center.y - image.size.height / 2, width: image.size.width, height: image.size.height))
    }

    private func drawHand(context: inout GraphicsContext, hand: String, shadow: String, units: Double, anchor: CGFloat, center: CGPoint) {
        let handImage = SmartisanAssets.image(hand)
        let shadowImage = SmartisanAssets.image(shadow)
        let degrees = units * 6
        let radians = degrees * .pi / 180
        context.drawLayer { layer in
            layer.translateBy(x: center.x, y: center.y)
            layer.rotate(by: .degrees(degrees))
            layer.draw(layer.resolve(Image(uiImage: shadowImage)), in: CGRect(x: -handImage.size.width / 2 + sin(radians) * 0.67, y: -handImage.size.height * anchor + cos(radians) * 0.67, width: shadowImage.size.width, height: shadowImage.size.height))
            layer.draw(layer.resolve(Image(uiImage: handImage)), in: CGRect(x: -handImage.size.width / 2, y: -handImage.size.height * anchor, width: handImage.size.width, height: handImage.size.height))
        }
    }
}
