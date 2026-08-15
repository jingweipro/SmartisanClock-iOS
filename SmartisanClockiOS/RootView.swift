import SwiftUI

enum ClockTab: Int, CaseIterable {
    case world, alarm, stopwatch, timer

    var title: String {
        switch self {
        case .world: "世界时钟"
        case .alarm: "闹钟"
        case .stopwatch: "秒表"
        case .timer: "计时器"
        }
    }

    var icon: String {
        switch self {
        case .world: "tab_worldclock.png"
        case .alarm: "tab_alarm.png"
        case .stopwatch: "tab_stopwatch.png"
        case .timer: "tab_timer.png"
        }
    }
}

struct RootView: View {
    @State private var selection: ClockTab
    @State private var showsRinging: Bool

    init() {
        let arguments = ProcessInfo.processInfo.arguments
        let requestedTab: ClockTab? = arguments.firstIndex(of: "-SmartisanScreen").flatMap { index in
            guard arguments.indices.contains(index + 1) else { return nil }
            return switch arguments[index + 1] {
            case "world": .world
            case "alarm": .alarm
            case "stopwatch": .stopwatch
            case "timer": .timer
            default: nil
            }
        }
        _selection = State(initialValue: requestedTab ?? .alarm)
        _showsRinging = State(initialValue: arguments.contains("-SmartisanRinging"))
    }

    var body: some View {
        GeometryReader { geometry in
            let top = geometry.safeAreaInsets.top
            let bottom = geometry.safeAreaInsets.bottom
            // GeometryReader already receives the safe-area-reduced height. The page canvas
            // only excludes the original 54-point tab bar; subtracting the insets again
            // shortened the timer page and pulled both rulers into the hint label.
            let pageHeight = max(0, geometry.size.height - 54)
            let pageWidth = min(geometry.size.width, 480)

            ZStack(alignment: .top) {
                ClockTheme.background.ignoresSafeArea()

                ZStack {
                    WorldClockView(isActive: selection == .world)
                        .frame(width: pageWidth, height: pageHeight, alignment: .top)
                        .opacity(selection == .world ? 1 : 0)
                        .allowsHitTesting(selection == .world)
                    AlarmView(isActive: selection == .alarm)
                        .frame(width: pageWidth, height: pageHeight, alignment: .top)
                        .opacity(selection == .alarm ? 1 : 0)
                        .allowsHitTesting(selection == .alarm)
                    StopwatchView(isActive: selection == .stopwatch)
                        .frame(width: pageWidth, height: pageHeight, alignment: .top)
                        .opacity(selection == .stopwatch ? 1 : 0)
                        .allowsHitTesting(selection == .stopwatch)
                    TimerView(isActive: selection == .timer, layoutHeight: pageHeight)
                        .frame(width: pageWidth, height: pageHeight, alignment: .top)
                        .opacity(selection == .timer ? 1 : 0)
                        .allowsHitTesting(selection == .timer)
                }
                .frame(width: pageWidth, height: pageHeight, alignment: .top)
                .offset(y: top)
                .animation(.easeOut(duration: 0.30), value: selection)

                SmartisanBottomBar(selection: $selection, safeBottom: bottom)
                    .frame(height: 54 + bottom)
                    .frame(maxHeight: .infinity, alignment: .bottom)

                if showsRinging {
                    SmartisanRingingView(
                        label: "闹钟",
                        alarmHour: 7,
                        alarmMinute: 30,
                        dismiss: { showsRinging = false },
                        snooze: { showsRinging = false }
                    )
                    .transition(.opacity)
                    .zIndex(100)
                }
            }
            .ignoresSafeArea()
        }
        .background(ClockTheme.background)
        .onOpenURL { url in
            guard url.scheme == "smartisanclock" else { return }
            let target: ClockTab? = switch url.host {
            case "world": .world
            case "alarm": .alarm
            case "stopwatch": .stopwatch
            case "timer": .timer
            default: nil
            }
            if let target { selection = target }
            if url.host == "ringing" { showsRinging = true }
        }
    }
}

private struct SmartisanBottomBar: View {
    @Binding var selection: ClockTab
    let safeBottom: CGFloat

    var body: some View {
        VStack(spacing: 0) {
            Rectangle().fill(Color.black.opacity(0.06)).frame(height: 0.67)
            HStack(spacing: 0) {
                ForEach(ClockTab.allCases, id: \.rawValue) { tab in
                    Button {
                        guard selection != tab else { return }
                        SmartisanHaptics.tick()
                        withAnimation(.easeOut(duration: 0.30)) { selection = tab }
                    } label: {
                        Image(uiImage: SmartisanAssets.image(tab.icon, scale: 4))
                            .resizable()
                            .renderingMode(.template)
                            .scaledToFit()
                            .foregroundStyle(Color.black.opacity(selection == tab ? 0.72 : 0.24))
                            .frame(width: 30, height: 30)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(tab.title)
                }
            }
            .frame(height: 53.33)
            .padding(.bottom, safeBottom)
        }
        .background(
            LinearGradient(
                colors: [Color(red: 245 / 255, green: 245 / 255, blue: 245 / 255), .white],
                startPoint: .top,
                endPoint: .bottom
            )
            .shadow(color: .black.opacity(0.12), radius: 7, y: -5)
        )
    }
}
