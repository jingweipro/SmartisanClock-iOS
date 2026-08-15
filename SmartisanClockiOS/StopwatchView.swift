import SwiftUI
import UIKit

struct StopwatchView: View {
    let isActive: Bool
    @State private var running = false
    @State private var startUptime = 0.0
    @State private var accumulated = 0.0
    @State private var laps: [TimeInterval] = []
    @State private var keepAwake = false

    var body: some View {
        GeometryReader { geometry in
            TimelineView(.animation(minimumInterval: 1 / 60, paused: !running || !isActive)) { _ in
                let elapsed = currentElapsed
                ZStack(alignment: .top) {
                    ClockTheme.background

                    ZStack(alignment: .topLeading) {
                        topMechanicalButtons(elapsed: elapsed)
                        MechanicalClockFace(
                            mode: .stopwatch,
                            stopwatchSeconds: elapsed,
                            isActive: isActive
                        )
                        .allowsHitTesting(false)
                    }
                    .frame(width: 360, height: 400)
                    .position(x: geometry.size.width / 2, y: 266)

                    Text(elapsed.smartisanStopwatchText)
                        .font(SmartisanAssets.font(.light, size: 36))
                        .foregroundStyle(ClockTheme.red)
                        .fixedSize()
                        .position(x: geometry.size.width / 2, y: 492)

                    SmartisanDivider(width: laps.isEmpty ? 80 : 160)
                        .position(x: geometry.size.width / 2, y: 539)
                        .animation(.easeOut(duration: 0.30), value: laps.isEmpty)

                    lapArea(elapsed: elapsed)
                        .frame(width: 160, height: 150, alignment: .top)
                        .position(x: geometry.size.width / 2, y: 614)

                    bottomControls
                        .frame(width: geometry.size.width, height: 40)
                        .position(x: geometry.size.width / 2, y: geometry.size.height - 45)

                    SmartisanTitleBar(
                        title: "秒表",
                        trailing: SmartisanBarAction(
                            image: keepAwake ? "stopwatch_light_on.png" : "stopwatch_light_off.png",
                            pressedImage: keepAwake ? "stopwatch_light_on_pressed.png" : "stopwatch_light_off_pressed.png",
                            accessibilityLabel: "屏幕常亮",
                            action: { keepAwake.toggle() }
                        )
                    )
                }
            }
        }
        .onChange(of: running) { _, value in
            SmartisanSoundEffects.shared.setLoop("stopwatch_loop", playing: value && isActive)
        }
        .onChange(of: isActive) { _, value in
            SmartisanSoundEffects.shared.setLoop("stopwatch_loop", playing: value && running)
        }
        .onChange(of: keepAwake) { _, value in UIApplication.shared.isIdleTimerDisabled = value && isActive }
        .onChange(of: isActive) { _, value in UIApplication.shared.isIdleTimerDisabled = value && keepAwake }
        .onDisappear {
            SmartisanSoundEffects.shared.setLoop("stopwatch_loop", playing: false)
            UIApplication.shared.isIdleTimerDisabled = false
        }
    }

    private func topMechanicalButtons(elapsed: TimeInterval) -> some View {
        ZStack(alignment: .topLeading) {
            Button { lap(elapsed) } label: {
                Image(uiImage: SmartisanAssets.image("stopwatch_top_left_btn.png"))
                    .resizable().scaledToFit()
            }
            .buttonStyle(SmartisanMechanicalPressStyle(offset: CGSize(width: 5, height: 5)))
            .frame(width: 68.67, height: 66.67)
            .position(x: 53 + 34.33, y: 81 + 33.33)
            .disabled(!running)

            Button { toggle() } label: {
                Image(uiImage: SmartisanAssets.image("stopwatch_top_mid_btn.png"))
                    .resizable().scaledToFit()
            }
            .buttonStyle(SmartisanMechanicalPressStyle(offset: CGSize(width: 0, height: 3)))
            .frame(width: 76, height: 88)
            .position(x: 180, y: 28 + 44)

            Button { reset() } label: {
                Image(uiImage: SmartisanAssets.image("stopwatch_top_right_btn.png"))
                    .resizable().scaledToFit()
            }
            .buttonStyle(SmartisanMechanicalPressStyle(offset: CGSize(width: -5, height: 5)))
            .frame(width: 68.67, height: 66.67)
            .position(x: 360 - 53 - 34.33, y: 81 + 33.33)
            .disabled(running || elapsed == 0)
        }
    }

    @ViewBuilder
    private func lapArea(elapsed: TimeInterval) -> some View {
        if laps.isEmpty {
            Text("点击左侧按钮记录时间")
                .font(.system(size: 10))
                .foregroundStyle(ClockTheme.hintText)
                .frame(width: 160, height: 30)
        } else {
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(Array(laps.enumerated().reversed()), id: \.offset) { index, lap in
                        let previous = index == 0 ? 0 : laps[index - 1]
                        HStack(spacing: 0) {
                            Text("\(index + 1)").frame(width: 22, alignment: .leading).font(.system(size: 10))
                            Text(lap.smartisanLapText).frame(width: 70, alignment: .trailing).font(SmartisanAssets.font(.regular, size: 14))
                            Text((lap - previous).smartisanLapDeltaText).frame(maxWidth: .infinity, alignment: .trailing).font(.system(size: 10))
                        }
                        .foregroundStyle(ClockTheme.secondaryText)
                        .frame(height: 29.33)
                    }
                }
            }
            .scrollIndicators(.hidden)
        }
    }

    private var bottomControls: some View {
        ZStack {
            if running {
                bitmapButton(normal: "button_stopwatch_normal.png", pressed: "button_stopwatch_pressed.png", action: { lap(currentElapsed) })
                    .offset(x: -70)
            }
            bitmapButton(
                normal: running ? "button_stopwatch_stop.png" : (accumulated > 0 ? "button_stopwatch_play.png" : "button_stopwatch_center_normal.png"),
                pressed: running ? "button_stopwatch_stop_pressed.png" : (accumulated > 0 ? "button_stopwatch_play_pressed.png" : "button_stopwatch_center_pressed.png"),
                action: toggle
            )
            if !running && accumulated > 0 {
                bitmapButton(normal: "button_stopwatch_reset.png", pressed: "button_stopwatch_reset_pressed.png", action: reset)
                    .offset(x: 70)
            }
        }
    }

    private func bitmapButton(normal: String, pressed: String, action: @escaping () -> Void) -> some View {
        Button(action: action) { Color.clear }
            .buttonStyle(SmartisanBitmapButtonStyle(normal: normal, pressed: pressed, size: 40))
            .frame(width: 40, height: 40)
    }

    private var currentElapsed: TimeInterval {
        accumulated + (running ? ProcessInfo.processInfo.systemUptime - startUptime : 0)
    }

    private func toggle() {
        SmartisanSoundEffects.shared.play("stopwatch_mid", volume: 0.5)
        SmartisanHaptics.confirm()
        if running {
            accumulated = currentElapsed
            running = false
        } else {
            startUptime = ProcessInfo.processInfo.systemUptime
            running = true
        }
    }

    private func lap(_ elapsed: TimeInterval) {
        guard running, laps.count < 99 else { return }
        SmartisanSoundEffects.shared.play("stopwatch_left_right", volume: 0.4)
        SmartisanHaptics.tick()
        laps.append(elapsed)
    }

    private func reset() {
        guard !running else { return }
        SmartisanSoundEffects.shared.play("stopwatch_clear", volume: 0.4)
        SmartisanHaptics.confirm()
        accumulated = 0
        laps.removeAll()
    }
}

private struct SmartisanMechanicalPressStyle: ButtonStyle {
    let offset: CGSize

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .offset(configuration.isPressed ? offset : .zero)
            .opacity(configuration.isPressed ? 0.94 : 1)
            .animation(.easeOut(duration: 0.10), value: configuration.isPressed)
    }
}
