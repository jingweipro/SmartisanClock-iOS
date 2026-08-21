import SwiftUI

struct TimerView: View {
    enum Mode: String { case modern, classic }

    @EnvironmentObject private var service: AlarmKitService
    let isActive: Bool
    let layoutHeight: CGFloat?
    @AppStorage("smartisan.timer.style") private var storedMode = Mode.classic.rawValue
    @State private var selectedMinutes: Double
    @State private var running = false
    @State private var fireDate: Date?
    @State private var remainingWhenPaused: TimeInterval = 0
    @State private var alarmID = UUID()
    @State private var showsStylePicker = false
    @State private var message: String?
    @State private var bounceRequest: ClassicBounceRequest?
    @State private var adjustmentWasPaused = false
    @State private var pendingSchedule: Task<Void, Never>?
    @State private var rulerPreviewMinutes: Double?

    private var mode: Mode { Mode(rawValue: storedMode) ?? .classic }

    init(isActive: Bool, layoutHeight: CGFloat? = nil) {
        self.isActive = isActive
        self.layoutHeight = layoutHeight
        let arguments = ProcessInfo.processInfo.arguments
        let previewMinutes = arguments.firstIndex(of: "-SmartisanTimerMinutes").flatMap { index -> Double? in
            guard arguments.indices.contains(index + 1) else { return nil }
            return Double(arguments[index + 1])
        }
        let runningMinutes = arguments.firstIndex(of: "-SmartisanTimerRunning").flatMap { index -> Double? in
            guard arguments.indices.contains(index + 1) else { return nil }
            return Double(arguments[index + 1])
        }
        let initialMinutes = runningMinutes ?? previewMinutes ?? 0
        _selectedMinutes = State(initialValue: min(Double(TimerRulerPolicy.modernMaximumMinutes), max(0, initialMinutes)))
        _running = State(initialValue: runningMinutes != nil)
        _fireDate = State(initialValue: runningMinutes.map { Date().addingTimeInterval(max(0, $0) * 60) })
    }

    var body: some View {
        GeometryReader { geometry in
            let canvasHeight = layoutHeight ?? geometry.size.height
            ZStack(alignment: .top) {
                TimelineView(.animation(minimumInterval: 1 / 60, paused: !running || !isActive)) { timeline in
                    let remaining = remaining(at: timeline.date)
                let timerMinutes = (running || remainingWhenPaused > 0) ? remaining / 60 : selectedMinutes
                let displayMinutes = rulerPreviewMinutes ?? timerMinutes

                    ZStack(alignment: .top) {
                        ClockTheme.background

                        MechanicalClockFace(
                            mode: .timer,
                            timerMinutes: displayMinutes,
                            isActive: isActive
                        )
                        .position(x: geometry.size.width / 2, y: 266)

                        if mode == .classic {
                            classicSurface(width: geometry.size.width, height: canvasHeight, remaining: remaining, displayMinutes: displayMinutes)
                        } else {
                            modernSurface(width: geometry.size.width, height: canvasHeight, remaining: remaining, displayMinutes: displayMinutes)
                        }
                    }
                }

                TimerHeader(
                    enabled: !running && remainingWhenPaused == 0,
                    showsStylePicker: $showsStylePicker
                )
                .equatable()

                if showsStylePicker {
                    TimerStylePicker(mode: mode) { selected in
                        storedMode = selected.rawValue
                        selectedMinutes = 0
                        showsStylePicker = false
                    } dismiss: {
                        showsStylePicker = false
                    }
                    .transition(.opacity)
                    .zIndex(10)
                }
            }
        }
        .onChange(of: running) { _, value in
            SmartisanSoundEffects.shared.setLoop("timer_loop", playing: value && isActive)
        }
        .onChange(of: isActive) { _, value in
            SmartisanSoundEffects.shared.setLoop("timer_loop", playing: value && running)
        }
        .onDisappear { SmartisanSoundEffects.shared.setLoop("timer_loop", playing: false) }
        .onAppear { SmartisanSoundEffects.shared.setLoop("timer_loop", playing: running && isActive) }
        .task(id: fireDate) {
            guard running, let target = fireDate else { return }
            let delay = max(0, target.timeIntervalSinceNow)
            if delay > 0 { try? await Task.sleep(for: .seconds(delay)) }
            guard !Task.isCancelled, running, fireDate == target else { return }
            running = false
            fireDate = nil
            remainingWhenPaused = 0
            selectedMinutes = 0
        }
        .alert("提示", isPresented: Binding(get: { message != nil }, set: { if !$0 { message = nil } })) {
            Button("确定", role: .cancel) { message = nil }
        } message: { Text(message ?? "") }
    }

    private func classicSurface(width: CGFloat, height: CGFloat, remaining: TimeInterval, displayMinutes: Double) -> some View {
        ZStack(alignment: .topTrailing) {
            ClassicPullRingView(
                minutes: Binding(get: { displayMinutes }, set: { selectedMinutes = $0 }),
                enabled: isActive,
                bounceRequest: bounceRequest,
                onAdjustmentStarted: beginAdjustment,
                onCommit: commitClassicAdjustment,
                onQuickRelease: { strength in resetClassic(releaseStrength: strength) }
            )
            .frame(width: 80, height: 500)
            .padding(.top, 58)
            .padding(.trailing, -3.6)

            VStack(spacing: 0) {
                Spacer()
                Text((running || remainingWhenPaused > 0 ? remaining : selectedMinutes * 60).smartisanTimerText)
                    .font(SmartisanAssets.font(.light, size: 30))
                    .foregroundStyle(ClockTheme.red)
                    .frame(height: 38)
                    .offset(y: (running || remainingWhenPaused > 0) ? -12 : 0)
                    .animation(.interpolatingSpring(stiffness: 210, damping: 18), value: running || remainingWhenPaused > 0)

                if running || remainingWhenPaused > 0 {
                    HStack(spacing: 22) {
                        Button(action: primaryAction) { Color.clear }
                            .buttonStyle(SmartisanBitmapButtonStyle(
                                normal: running ? "timer_680_button_stopwatch_stop.png" : "timer_680_button_stopwatch_play.png",
                                pressed: running ? "timer_680_button_stopwatch_stop_pressed.png" : "timer_680_button_stopwatch_play_pressed.png",
                                size: 75.34,
                                scale: 4
                            ))
                            .frame(width: 75.34, height: 75.34)

                        Button { resetClassic(releaseStrength: nil) } label: { Color.clear }
                            .buttonStyle(SmartisanBitmapButtonStyle(
                                normal: running ? "timer_680_button_stopwatch_reset_undo.png" : "timer_680_button_stopwatch_reset.png",
                                pressed: "timer_680_button_stopwatch_reset_pressed.png",
                                size: 75.34,
                                enabled: !running,
                                scale: 4
                            ))
                            .frame(width: 75.34, height: 75.34)
                            .disabled(running)
                    }
                    .frame(height: 83)
                    .transition(.opacity)
                } else {
                    Color.clear.frame(height: 83)
                }
            }
            .frame(width: width, height: height)
            .padding(.bottom, 4)
        }
        .frame(width: width, height: height)
    }

    private func modernSurface(width: CGFloat, height: CGFloat, remaining: TimeInterval, displayMinutes: Double) -> some View {
        ZStack(alignment: .top) {
            Text((running || remainingWhenPaused > 0 ? remaining : selectedMinutes * 60).smartisanTimerText)
                .font(SmartisanAssets.font(.light, size: 36))
                .foregroundStyle(ClockTheme.red)
                .position(x: width / 2, y: 492)

            SmartisanDivider()
                .position(x: width / 2, y: 539)

            Text("向左滑动刻度设置计时时长")
                .font(.system(size: 10))
                .foregroundStyle(ClockTheme.hintText)
                .position(x: width / 2, y: 557)

            HStack(spacing: 18) {
                Button { resetModern() } label: { Color.clear }
                    .buttonStyle(SmartisanBitmapButtonStyle(
                        normal: "button_stopwatch_reset_undo.png",
                        size: 40,
                        enabled: running || remainingWhenPaused > 0
                    ))
                    .frame(width: 40, height: 40)
                    .disabled(!running && remainingWhenPaused == 0)

                HorizontalTimerRuler(
                    minutes: Binding(get: { displayMinutes }, set: { selectedMinutes = $0 }),
                    enabled: true,
                    onAdjustmentStarted: beginAdjustment,
                    onPreview: { rulerPreviewMinutes = $0 },
                    onRelease: { commitModernAdjustment(Double($0)) }
                )
                .frame(maxWidth: .infinity)

                Button(action: primaryAction) { Color.clear }
                    .buttonStyle(SmartisanBitmapButtonStyle(
                        normal: running ? "button_stopwatch_stop.png" : "button_stopwatch_play.png",
                        pressed: running ? "button_stopwatch_stop_pressed.png" : "button_stopwatch_play_pressed.png",
                        disabled: "button_stopwatch_stop_disable.png",
                        size: 40,
                        enabled: running || remainingWhenPaused > 0 || selectedMinutes > 0
                    ))
                    .frame(width: 40, height: 40)
                    .disabled(!running && remainingWhenPaused == 0 && selectedMinutes == 0)
            }
            .padding(.horizontal, 18)
            .frame(width: width, height: 48)
            .position(x: width / 2, y: height - 49)
        }
        .frame(width: width, height: height)
    }

    private func remaining(at date: Date) -> TimeInterval {
        if running, let fireDate { return max(0, fireDate.timeIntervalSince(date)) }
        return remainingWhenPaused
    }

    private func primaryAction() {
        SmartisanHaptics.confirm()
        if running {
            pendingSchedule?.cancel()
            remainingWhenPaused = remaining(at: Date())
            selectedMinutes = remainingWhenPaused / 60
            running = false
            fireDate = nil
            service.cancel(id: alarmID)
        } else {
            let duration = remainingWhenPaused > 0 ? remainingWhenPaused : selectedMinutes * 60
            start(duration: duration)
        }
    }

    private func start(duration: TimeInterval) {
        guard duration > 0 else { return }
        adjustmentWasPaused = false
        pendingSchedule?.cancel()
        service.cancel(id: alarmID)
        alarmID = UUID()
        let scheduledID = alarmID
        fireDate = Date().addingTimeInterval(duration)
        remainingWhenPaused = 0
        selectedMinutes = duration / 60
        running = true
        pendingSchedule = Task {
            do { try await service.scheduleTimer(id: scheduledID, duration: duration) }
            catch {
                guard !Task.isCancelled, alarmID == scheduledID else { return }
                running = false
                fireDate = nil
                remainingWhenPaused = duration
                message = error.localizedDescription
            }
        }
    }

    private func commitClassicAdjustment(_ minutes: Double) {
        let whole = floor(min(max(minutes, 0), Double(TimerRulerPolicy.classicMaximumMinutes)))
        selectedMinutes = whole
        guard whole > 0 else {
            adjustmentWasPaused = false
            return
        }
        if adjustmentWasPaused {
            remainingWhenPaused = whole * 60
            adjustmentWasPaused = false
        } else {
            start(duration: whole * 60)
        }
    }

    private func commitModernAdjustment(_ minutes: Double) {
        let whole = min(max(minutes.rounded(), 0), Double(TimerRulerPolicy.modernMaximumMinutes))
        selectedMinutes = whole
        guard whole > 0 else {
            adjustmentWasPaused = false
            return
        }
        if adjustmentWasPaused {
            remainingWhenPaused = whole * 60
            adjustmentWasPaused = false
        } else {
            start(duration: whole * 60)
        }
    }

    private func beginAdjustment() {
        let paused = !running && remainingWhenPaused > 0
        let currentDuration: TimeInterval
        if running {
            currentDuration = remaining(at: Date())
        } else if paused {
            currentDuration = remainingWhenPaused
        } else {
            currentDuration = selectedMinutes * 60
        }
        pendingSchedule?.cancel()
        service.cancel(id: alarmID)
        adjustmentWasPaused = paused
        running = false
        fireDate = nil
        remainingWhenPaused = 0
        selectedMinutes = max(0, currentDuration / 60)
    }

    private func resetClassic(releaseStrength: Double?) {
        let from = Int(ceil(max(selectedMinutes, remaining(at: Date()) / 60)))
        cancelSession()
        let profile = ClassicResetProfile(minutes: from, releaseStrength: releaseStrength)
        withAnimation(.easeOut(duration: profile.returnDuration)) { selectedMinutes = 0 }
        guard let bounce = profile.bounce else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + profile.returnDuration) {
            bounceRequest = ClassicBounceRequest(type: bounce, gain: profile.gain)
        }
    }

    private func resetModern() {
        cancelSession()
        withAnimation(.easeOut(duration: 0.36)) { selectedMinutes = -0.25 }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.36) {
            withAnimation(.easeInOut(duration: 0.18)) { selectedMinutes = 0 }
        }
    }

    private func cancelSession() {
        pendingSchedule?.cancel()
        service.cancel(id: alarmID)
        adjustmentWasPaused = false
        running = false
        fireDate = nil
        remainingWhenPaused = 0
    }
}

private enum ClassicBounce: Equatable { case short, mid, long }

private struct ClassicBounceRequest: Equatable {
    let id = UUID()
    let type: ClassicBounce
    let gain: Float
}

private struct ClassicResetProfile {
    let returnDuration: Double
    let bounce: ClassicBounce?
    let gain: Float

    init(minutes: Int, releaseStrength: Double?) {
        let distance: (Double, ClassicBounce?, Float) = switch minutes {
        case ..<10: (0.060, nil, 0)
        case ..<25: (0.100, .short, 0.2)
        case ...40: (0.120, .mid, 0.5)
        default: (0.150, .long, 1)
        }
        returnDuration = distance.0
        if let releaseStrength {
            if releaseStrength < 0.33 { bounce = .short; gain = 0.2 }
            else if releaseStrength < 0.72 { bounce = .mid; gain = 0.5 }
            else { bounce = .long; gain = 1 }
        } else {
            bounce = distance.1
            gain = distance.2
        }
    }
}

private struct ClassicPullRingView: View {
    @Binding var minutes: Double
    let enabled: Bool
    let bounceRequest: ClassicBounceRequest?
    let onAdjustmentStarted: () -> Void
    let onCommit: (Double) -> Void
    let onQuickRelease: (Double) -> Void
    @State private var dragStart: Double?
    @State private var thresholdFired = false
    @State private var activeBounce: ClassicBounceRequest?
    @State private var bounceStart: Date?
    @State private var entranceStart: Date?
    @State private var entranceFrom: Double = 0
    @State private var entranceTarget: Double = 0
    @State private var entranceDuration: Double = 0.412
    @State private var entranceID = UUID()

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 120, paused: entranceStart == nil)) { timeline in
            ringBody(visualMinutes(at: timeline.date))
        }
        .contentShape(Rectangle())
        .gesture(dragGesture)
        .onAppear { if enabled { beginEntrance() } }
        .onChange(of: enabled) { _, value in if value { beginEntrance() } }
        .onChange(of: bounceRequest?.id) { _, _ in beginBounce() }
    }

    private func ringBody(_ visualMinutes: Double) -> some View {
        ZStack(alignment: .topTrailing) {
            Image(uiImage: SmartisanAssets.image("timer_680_ruler_highlight_2.png"))
                .resizable().frame(width: 78, height: 50)
                .offset(x: 2.6)

            if activeBounce == nil {
                Image(uiImage: SmartisanAssets.image("timer_680_ruler.png", scale: 4))
                    .resizable()
                    .frame(width: 77.67, height: 494)
                    .offset(x: 3.6, y: visualMinutes / 60 * 400 - 400 - 0.25)
            } else {
                ClassicBounceFrames(request: activeBounce!, start: bounceStart ?? Date())
                    .frame(width: 80, height: 100, alignment: .topTrailing)
                    .offset(x: 3.6, y: -2.7)
                    .clipped()
            }

            Image(uiImage: SmartisanAssets.image("timer_680_ruler_highlight_2.png"))
                .resizable().frame(width: 78, height: 50)
                .offset(x: 2.6)
        }
        .frame(width: 80, height: 500, alignment: .topTrailing)
        .clipped()
    }

    private func visualMinutes(at date: Date) -> Double {
        guard let entranceStart else { return min(60, max(0, minutes)) }
        let progress = min(1, max(0, date.timeIntervalSince(entranceStart) / entranceDuration))
        let eased: Double
        if entranceFrom < 0 {
            let shifted = progress - 1
            eased = shifted * shifted * (3 * shifted + 2) + 1
        } else {
            eased = 1 - (1 - progress) * (1 - progress)
        }
        return entranceFrom + (entranceTarget - entranceFrom) * eased
    }

    private func beginEntrance() {
        guard enabled, activeBounce == nil else { return }
        let target = min(60, max(0, minutes))
        entranceFrom = target == 0 ? -60 * (282 / 1_200) : 0
        entranceTarget = target
        entranceDuration = target == 0 ? 0.412 : 0.400
        entranceStart = Date()
        let id = UUID()
        entranceID = id
        DispatchQueue.main.asyncAfter(deadline: .now() + entranceDuration) {
            guard entranceID == id else { return }
            entranceStart = nil
        }
    }

    private var dragGesture: some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                guard enabled, activeBounce == nil, entranceStart == nil else { return }
                let handleBottom = min(60, max(0, minutes)) / 60 * 400 + 94
                if dragStart == nil {
                    guard value.startLocation.y <= handleBottom else { return }
                    dragStart = minutes
                    thresholdFired = false
                }
                guard let dragStart else { return }
                let candidate = min(60, max(0, dragStart + Double(value.translation.height) * 0.15))
                if !thresholdFired {
                    guard abs(candidate - dragStart) >= 0.75 else { return }
                    thresholdFired = true
                    onAdjustmentStarted()
                    SmartisanHaptics.tick()
                }
                minutes = candidate
            }
            .onEnded { value in
                guard dragStart != nil else { return }
                self.dragStart = nil
                let quickDistance = value.predictedEndTranslation.height - value.translation.height
                let quick = quickDistance < -80
                if quick {
                    let strength = min(1, max(0, Double((-quickDistance - 80) / 260)))
                    onQuickRelease(strength)
                } else if thresholdFired {
                    let whole = floor(min(60, max(0, minutes)))
                    minutes = whole
                    onCommit(whole)
                }
                thresholdFired = false
            }
    }

    private func beginBounce() {
        guard let request = bounceRequest else { return }
        entranceID = UUID()
        entranceStart = nil
        activeBounce = request
        bounceStart = Date()
        SmartisanSoundEffects.shared.play("ruler_back", volume: request.gain)
        let duration = Double(request.type.sequence.count) * 0.016
        DispatchQueue.main.asyncAfter(deadline: .now() + duration) {
            guard activeBounce?.id == request.id else { return }
            SmartisanSoundEffects.shared.play("ruler_ring", volume: request.gain)
            activeBounce = nil
            bounceStart = nil
        }
    }
}

private struct ClassicBounceFrames: View {
    let request: ClassicBounceRequest
    let start: Date

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 120)) { timeline in
            let frames = request.type.sequence
            let position = max(0, timeline.date.timeIntervalSince(start) / 0.016)
            let slot = min(frames.count - 1, Int(position))
            let next = min(frames.count - 1, slot + 1)
            let fraction = min(1, max(0, position - Double(slot)))
            let first = interpolatedFrame(from: frames[slot], to: frames[next], fraction: fraction, upper: false)
            let second = interpolatedFrame(from: frames[slot], to: frames[next], fraction: fraction, upper: true)
            let blend = interpolatedSourcePosition(from: frames[slot], to: frames[next], fraction: fraction) - Double(first)
            ZStack {
                frame(first).opacity(1 - blend)
                frame(second).opacity(blend).blendMode(.plusLighter)
            }
        }
    }

    private func frame(_ index: Int) -> some View {
        Image(uiImage: SmartisanAssets.image(String(format: "timer_680_loop_%04d.png", index + 1), scale: 4))
            .resizable().frame(width: 81.5, height: 92.25)
    }

    private func interpolatedSourcePosition(from: Int, to: Int, fraction: Double) -> Double {
        Double(from) + Double(to - from) * fraction
    }

    private func interpolatedFrame(from: Int, to: Int, fraction: Double, upper: Bool) -> Int {
        let value = interpolatedSourcePosition(from: from, to: to, fraction: fraction)
        return upper ? Int(ceil(value)) : Int(floor(value))
    }
}

private extension ClassicBounce {
    var sequence: [Int] {
        switch self {
        case .short: [5, 8, 9, 9, 9, 9, 9, 9, 9, 8, 7, 6, 5, 4, 3, 2, 1, 0]
        case .mid: [6, 11, 14, 17, 19, 19, 19, 19, 19, 19, 19, 19, 19, 19, 19, 17, 15, 13, 11, 8, 6, 4, 2, 0]
        case .long: [9, 16, 22, 26, 28, 29, 29, 29, 29, 29, 29, 29, 29, 29, 29, 29, 28, 27, 26, 24, 22, 19, 16, 13, 9, 5, 0]
        }
    }
}

private struct HorizontalTimerRuler: View {
    @Binding var minutes: Double
    let enabled: Bool
    let onAdjustmentStarted: () -> Void
    let onPreview: (Double?) -> Void
    let onRelease: (Int) -> Void
    @State private var position: CGFloat = 0
    @State private var startPosition: CGFloat?
    @State private var lastBucket = 0
    @State private var lastPublishedMinute = 0
    private let pixelsPerMinute: CGFloat = 70 / 3

    init(minutes: Binding<Double>, enabled: Bool, onAdjustmentStarted: @escaping () -> Void, onPreview: @escaping (Double?) -> Void, onRelease: @escaping (Int) -> Void) {
        _minutes = minutes
        self.enabled = enabled
        self.onAdjustmentStarted = onAdjustmentStarted
        self.onPreview = onPreview
        self.onRelease = onRelease
        let initial = min(Double(TimerRulerPolicy.modernMaximumMinutes), max(0, minutes.wrappedValue))
        _position = State(initialValue: CGFloat(initial) * (70 / 3))
        _lastBucket = State(initialValue: Int(floor(initial)))
        _lastPublishedMinute = State(initialValue: Int(initial.rounded()))
    }

    var body: some View {
        Canvas { context, size in draw(context: &context, size: size) }
            .frame(height: 48)
            .contentShape(Rectangle())
            .gesture(dragGesture)
            .onAppear { position = CGFloat(minutes) * pixelsPerMinute }
            .onChange(of: minutes) { _, value in
                if startPosition == nil { position = CGFloat(value) * pixelsPerMinute }
            }
    }

    private func draw(context: inout GraphicsContext, size: CGSize) {
        let zeroX = size.width / 2 - position
        drawStretch(context: &context, name: "timer_caliper_bg2_disable.png", rect: CGRect(origin: .zero, size: size))
        if enabled {
            let activeX = min(size.width, max(0, zeroX))
            drawStretch(context: &context, name: "timer_caliper_bg3.png", rect: CGRect(x: activeX, y: 0, width: size.width - activeX, height: size.height))
        }

        let first = max(0, Int(floor(-zeroX / pixelsPerMinute)) - 1)
        let last = min(TimerRulerPolicy.modernMaximumMinutes, Int(floor((size.width - zeroX) / pixelsPerMinute)) + 2)
        if first <= last {
            for minute in first...last {
                let x = zeroX + CGFloat(minute) * pixelsPerMinute
                let tick = SmartisanAssets.image(enabled ? "timer_scale_normal.png" : "timer_scale_disable.png")
                context.draw(context.resolve(Image(uiImage: tick)), in: CGRect(x: x, y: 0, width: pixelsPerMinute, height: 7))
                context.draw(
                    Text("\(minute)").font(.system(size: 8)).foregroundStyle(enabled ? Color(red: 115 / 255, green: 153 / 255, blue: 115 / 255) : Color(red: 115 / 255, green: 153 / 255, blue: 115 / 255).opacity(0.33)),
                    at: CGPoint(x: x, y: 16.5),
                    anchor: .center
                )
            }
        }

        let blank = SmartisanAssets.image("timer_blank.png")
        context.draw(context.resolve(Image(uiImage: blank)), in: CGRect(x: zeroX - 3 * pixelsPerMinute, y: (48 - 4) / 2, width: 52, height: 4))
        drawStretch(context: &context, name: "timer_caliper_bg1.png", rect: CGRect(origin: .zero, size: size))
        context.stroke(Path { path in path.move(to: CGPoint(x: size.width / 2, y: 0)); path.addLine(to: CGPoint(x: size.width / 2, y: size.height)) }, with: .color(ClockTheme.rulerRed), lineWidth: 0.66)
    }

    private var dragGesture: some Gesture {
        DragGesture(minimumDistance: 2)
            .onChanged { value in
                guard enabled else { return }
                if startPosition == nil {
                    onAdjustmentStarted()
                    startPosition = position
                    lastBucket = Int(floor(position / pixelsPerMinute))
                    lastPublishedMinute = TimerRulerPolicy.committedMinute(
                        at: position,
                        pixelsPerMinute: pixelsPerMinute,
                        maximumMinutes: TimerRulerPolicy.modernMaximumMinutes
                    )
                    SmartisanHaptics.prepareTick()
                }
                guard let startPosition else { return }
                let raw = startPosition - value.translation.width
                position = resisted(raw)
                onPreview(TimerRulerPolicy.minute(
                    at: position,
                    pixelsPerMinute: pixelsPerMinute,
                    maximumMinutes: TimerRulerPolicy.modernMaximumMinutes
                ))
                let bucket = Int(floor(position / pixelsPerMinute))
                if bucket != lastBucket {
                    lastBucket = bucket
                    SmartisanHaptics.tick()
                }
                if let changedMinute = TimerRulerPolicy.changedMinute(
                    previous: lastPublishedMinute,
                    position: position,
                    pixelsPerMinute: pixelsPerMinute,
                    maximumMinutes: TimerRulerPolicy.modernMaximumMinutes
                ) {
                    lastPublishedMinute = changedMinute
                    minutes = Double(changedMinute)
                }
            }
            .onEnded { value in
                guard let startPosition else { return }
                self.startPosition = nil
                let projected = startPosition - value.predictedEndTranslation.width
                let bounded = min(CGFloat(TimerRulerPolicy.modernMaximumMinutes) * pixelsPerMinute, max(0, projected))
                let targetMinute = TimerRulerPolicy.committedMinute(
                    at: bounded,
                    pixelsPerMinute: pixelsPerMinute,
                    maximumMinutes: TimerRulerPolicy.modernMaximumMinutes
                )
                withAnimation(.easeOut(duration: abs(value.predictedEndTranslation.width - value.translation.width) > 30 ? 0.78 : 0.30)) {
                    position = CGFloat(targetMinute) * pixelsPerMinute
                    minutes = Double(targetMinute)
                }
                onPreview(nil)
                DispatchQueue.main.asyncAfter(deadline: .now() + (abs(value.predictedEndTranslation.width - value.translation.width) > 30 ? 1.18 : 0.40)) {
                    onRelease(targetMinute)
                }
            }
    }

    private func resisted(_ raw: CGFloat) -> CGFloat {
        let maximum = CGFloat(TimerRulerPolicy.modernMaximumMinutes) * pixelsPerMinute
        if raw < 0 { return max(-166.67, raw / (1 + abs(raw) / 20)) }
        if raw > maximum { return min(maximum + 166.67, maximum + (raw - maximum) / (1 + (raw - maximum) / 20)) }
        return raw
    }

    private func drawStretch(context: inout GraphicsContext, name: String, rect: CGRect) {
        guard rect.width > 0 else { return }
        context.draw(context.resolve(Image(uiImage: SmartisanAssets.image(name))), in: rect)
    }
}

private struct TimerHeader: View, Equatable {
    let enabled: Bool
    @Binding var showsStylePicker: Bool

    static func == (lhs: TimerHeader, rhs: TimerHeader) -> Bool {
        lhs.enabled == rhs.enabled && lhs.showsStylePicker == rhs.showsStylePicker
    }

    var body: some View {
        SmartisanTitleBar(
            title: "计时器",
            trailing: SmartisanBarAction(
                image: "icon_setting_normal.png",
                pressedImage: "icon_setting_pressed.png",
                disabledImage: "icon_setting_disabled.png",
                enabled: enabled,
                accessibilityLabel: "计时器样式",
                action: { showsStylePicker = true }
            )
        )
    }
}

private struct TimerStylePicker: View {
    let mode: TimerView.Mode
    let select: (TimerView.Mode) -> Void
    let dismiss: () -> Void

    var body: some View {
        ZStack(alignment: .bottom) {
            Color.black.opacity(0.20).onTapGesture(perform: dismiss)
            VStack(spacing: 0) {
                HStack {
                    Text("计时器样式").font(.system(size: 13.5, weight: .bold)).foregroundStyle(ClockTheme.title)
                    Spacer()
                    Button("关闭", action: dismiss).font(.system(size: 13)).foregroundStyle(ClockTheme.secondaryText)
                }
                .padding(.horizontal, 18).frame(height: 48)
                .background(.white)
                styleRow(.modern, title: "水平滑尺")
                styleRow(.classic, title: "经典拉环")
            }
            .background(ClockTheme.pageGray)
            .transition(.move(edge: .bottom))
        }
        .ignoresSafeArea()
    }

    private func styleRow(_ value: TimerView.Mode, title: String) -> some View {
        Button { select(value) } label: {
            HStack {
                Text(title).font(.system(size: 16)).foregroundStyle(Color.black.opacity(0.36))
                Spacer()
                Image(uiImage: SmartisanAssets.image(mode == value ? "timer_style_selector_selected.png" : "timer_style_selector_unselected.png"))
                    .resizable().scaledToFit().frame(width: 32, height: 32)
            }
            .padding(.horizontal, 18).frame(height: 48)
            .background(.white)
            .overlay(alignment: .top) { Rectangle().fill(ClockTheme.divider).frame(height: 0.67) }
        }
        .buttonStyle(.plain)
    }
}
