import ActivityKit
import AlarmKit
import AppIntents
import SwiftUI
import WidgetKit

private enum LiveClockPalette {
    static let red = Color(red: 0.82, green: 0.19, blue: 0.17)
    static let islandRed = Color(red: 0.98, green: 0.30, blue: 0.26)
    static let graphite = Color(white: 0.31)
    static let secondary = Color(white: 0.55)
    static let paper = Color(white: 0.98)
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
                        .frame(width: 48, height: 48)
                        .padding(.leading, 4)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    VStack(alignment: .trailing, spacing: 2) {
                        Text(context.attributes.metadata?.label ?? "计时器")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.white.opacity(0.76))
                        countdownText(context.state)
                            .font(.system(size: 24, weight: .medium, design: .rounded))
                            .foregroundStyle(LiveClockPalette.islandRed)
                    }
                    .padding(.trailing, 4)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    HStack(spacing: 10) {
                        Text(statusText(context.state.mode))
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.68))
                        Spacer(minLength: 4)
                        AlarmLiveControls(
                            presentation: context.attributes.presentation,
                            state: context.state,
                            compact: true
                        )
                    }
                    .padding(.horizontal, 4)
                    .padding(.bottom, 2)
                }
            } compactLeading: {
                LiveMechanicalDial(mode: context.state.mode)
                    .frame(width: 23, height: 23)
                    .accessibilityHidden(true)
            } compactTrailing: {
                countdownText(context.state)
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(LiveClockPalette.islandRed)
                    .frame(maxWidth: 58)
            } minimal: {
                LiveMechanicalDial(mode: context.state.mode)
                    .frame(width: 22, height: 22)
                    .accessibilityLabel(Text(statusText(context.state.mode)))
            }
            .keylineTint(LiveClockPalette.islandRed)
            .widgetURL(URL(string: "smartisanclock://timer"))
        }
    }

    private func lockScreenView(_ context: Context) -> some View {
        HStack(spacing: 14) {
            LiveMechanicalDial(mode: context.state.mode)
                .frame(width: 64, height: 64)
                .shadow(color: .black.opacity(0.14), radius: 6, y: 3)

            VStack(alignment: .leading, spacing: 3) {
                Text(context.attributes.metadata?.label ?? "计时器")
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(LiveClockPalette.graphite)
                countdownText(context.state)
                    .font(.system(size: 34, weight: .light, design: .rounded))
                    .foregroundStyle(LiveClockPalette.red)
                Text(statusText(context.state.mode))
                    .font(.caption)
                    .foregroundStyle(LiveClockPalette.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            AlarmLiveControls(
                presentation: context.attributes.presentation,
                state: context.state,
                compact: false
            )
        }
        .padding(14)
    }

    @ViewBuilder
    private func countdownText(_ state: AlarmPresentationState) -> some View {
        Group {
            switch state.mode {
            case let .countdown(countdown):
                let upperBound = max(Date.now, countdown.fireDate)
                Text(timerInterval: Date.now ... upperBound, countsDown: true)
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
        .minimumScaleFactor(0.65)
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
        ZStack {
            Circle()
                .fill(LiveClockPalette.paper)
            Circle()
                .stroke(Color.white, lineWidth: 2.2)
            Circle()
                .stroke(Color.black.opacity(0.08), lineWidth: 0.7)

            progressLayer

            Capsule()
                .fill(LiveClockPalette.graphite)
                .frame(width: 2.6, height: 20)
                .offset(y: -7)
                .rotationEffect(.degrees(handAngle))
                .shadow(color: .black.opacity(0.20), radius: 1.5, x: 1, y: 1)

            Circle()
                .fill(LiveClockPalette.red)
                .frame(width: 7, height: 7)
                .overlay(Circle().stroke(Color.black.opacity(0.18), lineWidth: 0.6))
        }
    }

    @ViewBuilder
    private var progressLayer: some View {
        switch mode {
        case let .countdown(countdown):
            let upperBound = max(Date.now, countdown.fireDate)
            ProgressView(timerInterval: Date.now ... upperBound, countsDown: true)
                .progressViewStyle(.circular)
                .tint(LiveClockPalette.red.opacity(0.72))
                .padding(3)
        case let .paused(paused):
            let remaining = max(0, paused.totalCountdownDuration - paused.previouslyElapsedDuration)
            ProgressView(value: remaining, total: max(1, paused.totalCountdownDuration))
                .progressViewStyle(.circular)
                .tint(LiveClockPalette.red.opacity(0.72))
                .padding(3)
        case .alert:
            Circle().stroke(LiveClockPalette.red, lineWidth: 2.3).padding(3)
        @unknown default:
            EmptyView()
        }
    }

    private var handAngle: Double {
        switch mode {
        case let .countdown(countdown):
            let remaining = max(0, countdown.fireDate.timeIntervalSinceNow)
            let elapsed = max(0, countdown.totalCountdownDuration - remaining)
            return elapsed / max(1, countdown.totalCountdownDuration) * 360
        case let .paused(paused):
            return paused.previouslyElapsedDuration / max(1, paused.totalCountdownDuration) * 360
        case .alert:
            return 0
        @unknown default:
            return 0
        }
    }
}

private struct AlarmLiveControls: View {
    let presentation: AlarmPresentation
    let state: AlarmPresentationState
    let compact: Bool

    var body: some View {
        HStack(spacing: compact ? 7 : 9) {
            switch state.mode {
            case .countdown:
                AlarmIntentButton(
                    config: presentation.countdown?.pauseButton,
                    intent: PauseTimerIntent(alarmID: state.alarmID.uuidString),
                    tint: Color(white: 0.43),
                    compact: compact
                )
            case .paused:
                AlarmIntentButton(
                    config: presentation.paused?.resumeButton,
                    intent: ResumeTimerIntent(alarmID: state.alarmID.uuidString),
                    tint: Color(white: 0.43),
                    compact: compact
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
                    systemImageName: "stop.circle"
                ),
                intent: StopTimerIntent(alarmID: state.alarmID.uuidString),
                tint: LiveClockPalette.red,
                compact: compact
            )
        }
    }
}

private struct AlarmIntentButton<Intent: AppIntent>: View {
    let config: AlarmButton
    let intent: Intent
    let tint: Color
    let compact: Bool

    init?(config: AlarmButton?, intent: Intent, tint: Color, compact: Bool) {
        guard let config else { return nil }
        self.config = config
        self.intent = intent
        self.tint = tint
        self.compact = compact
    }

    var body: some View {
        Button(intent: intent) {
            Label(config.text, systemImage: config.systemImageName)
                .font(.caption.weight(.semibold))
                .lineLimit(1)
        }
        .buttonStyle(.borderedProminent)
        .tint(tint)
        .frame(width: compact ? 82 : 92, height: 44)
    }
}
