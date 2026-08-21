import ActivityKit
import AlarmKit
import AppIntents
import SwiftUI
import UIKit
import WidgetKit

private enum LiveClockPalette {
    static let red = Color(red: 0.82, green: 0.19, blue: 0.17)
    static let islandRed = Color(red: 0.98, green: 0.30, blue: 0.26)
    static let graphite = Color(white: 0.34)
    static let secondary = Color(white: 0.56)
    static let paper = Color(white: 0.985)
}

struct SmartisanAlarmLiveActivity: Widget {
    typealias Attributes = AlarmAttributes<ClockAlarmMetadata>
    typealias Context = ActivityViewContext<Attributes>

    var body: some WidgetConfiguration {
        ActivityConfiguration(for: Attributes.self) { context in
            lockScreenView(context)
                .activityBackgroundTint(LiveClockPalette.paper)
                .activitySystemActionForegroundColor(LiveClockPalette.graphite)
                .widgetURL(URL(string: "smartisanclock://timer"))
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    LiveMechanicalDial(mode: context.state.mode)
                        .frame(width: 52, height: 52)
                        .padding(.leading, 3)
                }

                DynamicIslandExpandedRegion(.trailing) {
                    VStack(alignment: .trailing, spacing: 1) {
                        Text(context.attributes.metadata?.label ?? "计时器")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.68))
                        countdownText(context.state)
                            .font(.system(size: 26, weight: .light))
                            .foregroundStyle(LiveClockPalette.islandRed)
                    }
                    .padding(.trailing, 3)
                }

                DynamicIslandExpandedRegion(.bottom) {
                    HStack(spacing: 8) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(statusText(context.state.mode))
                                .font(.system(size: 11, weight: .regular))
                                .foregroundStyle(.white.opacity(0.66))
                            Rectangle()
                                .fill(LiveClockPalette.islandRed.opacity(0.72))
                                .frame(width: 24, height: 1)
                        }

                        Spacer(minLength: 8)

                        AlarmLiveControls(
                            state: context.state,
                            presentation: context.attributes.presentation,
                            surface: .island
                        )
                    }
                    .padding(.horizontal, 3)
                    .padding(.bottom, 2)
                }
            } compactLeading: {
                LiveMechanicalDial(mode: context.state.mode)
                    .frame(width: 24, height: 24)
                    .accessibilityHidden(true)
            } compactTrailing: {
                countdownText(context.state)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(LiveClockPalette.islandRed)
                    .frame(maxWidth: 58)
            } minimal: {
                LiveMechanicalDial(mode: context.state.mode)
                    .frame(width: 23, height: 23)
                    .accessibilityLabel(Text(statusText(context.state.mode)))
            }
            .keylineTint(LiveClockPalette.islandRed)
            .widgetURL(URL(string: "smartisanclock://timer"))
        }
    }

    private func lockScreenView(_ context: Context) -> some View {
        HStack(spacing: 12) {
            LiveMechanicalDial(mode: context.state.mode)
                .frame(width: 68, height: 68)

            VStack(alignment: .leading, spacing: 1) {
                Text(context.attributes.metadata?.label ?? "计时器")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(LiveClockPalette.graphite)

                countdownText(context.state)
                    .font(.system(size: 30, weight: .light))
                    .foregroundStyle(LiveClockPalette.red)

                Text(statusText(context.state.mode))
                    .font(.system(size: 11, weight: .regular))
                    .foregroundStyle(LiveClockPalette.secondary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .layoutPriority(1)

            AlarmLiveControls(
                state: context.state,
                presentation: context.attributes.presentation,
                surface: .lockScreen
            )
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }

    @ViewBuilder
    private func countdownText(_ state: AlarmPresentationState) -> some View {
        Group {
            switch state.mode {
            case let .countdown(countdown):
                Text(timerInterval: Date.now ... max(Date.now, countdown.fireDate), countsDown: true)
            case let .paused(paused):
                let seconds = max(0, paused.totalCountdownDuration - paused.previouslyElapsedDuration)
                let duration = Duration.seconds(seconds)
                let pattern: Duration.TimeFormatStyle.Pattern = seconds >= 3_600
                    ? .hourMinuteSecond
                    : .minuteSecond
                Text(duration.formatted(.time(pattern: pattern)))
            case .alert:
                Text("00:00")
            @unknown default:
                Text("--:--")
            }
        }
        .monospacedDigit()
        .lineLimit(1)
        .minimumScaleFactor(0.72)
        .accessibilityLabel(Text("剩余时间"))
    }

    private func statusText(_ mode: AlarmPresentationState.Mode) -> String {
        switch mode {
        case .countdown: "正在倒计时"
        case .paused: "计时器已暂停"
        case .alert: "计时结束"
        @unknown default: "计时器"
        }
    }
}

private struct LiveMechanicalDial: View {
    let mode: AlarmPresentationState.Mode

    var body: some View {
        GeometryReader { geometry in
            let side = min(geometry.size.width, geometry.size.height)

            ZStack {
                BundleRasterImage(name: "small_blank_clock")
                    .frame(width: side, height: side)

                BundleRasterImage(name: "small_minute_hand_shadow")
                    .frame(width: side * 0.07, height: side * 0.282)
                    .offset(x: side * 0.018, y: -side * 0.105)
                    .rotationEffect(.degrees(handAngle))

                BundleRasterImage(name: "small_minute_hand")
                    .frame(width: side * 0.07, height: side * 0.282)
                    .offset(y: -side * 0.105)
                    .rotationEffect(.degrees(handAngle))

                Circle()
                    .fill(LiveClockPalette.red)
                    .frame(width: side * 0.125, height: side * 0.125)
                    .overlay(Circle().stroke(Color.black.opacity(0.18), lineWidth: 0.6))
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
        }
    }

    private var handAngle: Double {
        let remaining: TimeInterval = switch mode {
        case let .countdown(countdown):
            max(0, countdown.fireDate.timeIntervalSinceNow)
        case let .paused(paused):
            max(0, paused.totalCountdownDuration - paused.previouslyElapsedDuration)
        case .alert:
            0
        @unknown default:
            0
        }
        return remaining.truncatingRemainder(dividingBy: 3_600) / 10
    }
}

private struct BundleRasterImage: View {
    let name: String

    var body: some View {
        if let url = Bundle.main.url(forResource: name, withExtension: "png"),
           let image = UIImage(contentsOfFile: url.path) {
            Image(uiImage: image)
                .resizable()
                .interpolation(.high)
        }
    }
}

private enum LiveControlSurface {
    case lockScreen
    case island

    var size: CGFloat {
        switch self {
        case .lockScreen: 46
        case .island: 44
        }
    }
}

private struct AlarmLiveControls: View {
    let state: AlarmPresentationState
    let presentation: AlarmPresentation
    let surface: LiveControlSurface

    var body: some View {
        HStack(spacing: 8) {
            switch state.mode {
            case .countdown:
                AlarmIntentButton(
                    config: presentation.countdown?.pauseButton,
                    intent: PauseTimerIntent(alarmID: state.alarmID.uuidString),
                    iconColor: LiveClockPalette.graphite,
                    surface: surface
                )
            case .paused:
                AlarmIntentButton(
                    config: presentation.paused?.resumeButton,
                    intent: ResumeTimerIntent(alarmID: state.alarmID.uuidString),
                    iconColor: LiveClockPalette.graphite,
                    surface: surface
                )
            case .alert:
                EmptyView()
            @unknown default:
                EmptyView()
            }

            AlarmIntentButton(
                config: AlarmButton(
                    text: "停止",
                    textColor: .white,
                    systemImageName: "stop.fill"
                ),
                intent: StopTimerIntent(alarmID: state.alarmID.uuidString),
                iconColor: LiveClockPalette.red,
                surface: surface
            )
        }
    }
}

private struct AlarmIntentButton<Intent: AppIntent>: View {
    let config: AlarmButton
    let intent: Intent
    let iconColor: Color
    let surface: LiveControlSurface

    init?(config: AlarmButton?, intent: Intent, iconColor: Color, surface: LiveControlSurface) {
        guard let config else { return nil }
        self.config = config
        self.intent = intent
        self.iconColor = iconColor
        self.surface = surface
    }

    var body: some View {
        Button(intent: intent) {
            Image(systemName: config.systemImageName)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(iconColor)
                .frame(width: surface.size, height: surface.size)
                .background(SmartisanLiveButtonSurface())
        }
        .buttonStyle(.plain)
        .contentShape(Circle())
        .accessibilityLabel(Text(config.text))
    }
}

private struct SmartisanLiveButtonSurface: View {
    var body: some View {
        Circle()
            .fill(Color(white: 0.965))
            .overlay(
                Circle()
                    .stroke(Color.white, lineWidth: 1.2)
                    .padding(1)
            )
            .overlay(
                Circle()
                    .stroke(Color.black.opacity(0.09), lineWidth: 0.8)
                    .padding(2)
            )
            .shadow(color: .black.opacity(0.18), radius: 3, y: 2)
    }
}
