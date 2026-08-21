import SwiftUI

@main
struct SmartisanClockiOSApp: App {
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var alarmStore: AlarmStore
    @StateObject private var cityStore: CityStore
    @StateObject private var alarmService: AlarmKitService
    @StateObject private var timerCoordinator: TimerCoordinator

    init() {
        let service = AlarmKitService()
        _alarmStore = StateObject(wrappedValue: AlarmStore())
        _cityStore = StateObject(wrappedValue: CityStore())
        _alarmService = StateObject(wrappedValue: service)
        _timerCoordinator = StateObject(wrappedValue: TimerCoordinator(service: service))
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(alarmStore)
                .environmentObject(cityStore)
                .environmentObject(alarmService)
                .environmentObject(timerCoordinator)
                .preferredColorScheme(.light)
                .task {
                    SmartisanAssets.registerFonts()
                    await reconcileTimer()
                    startAutomationTimerIfRequested()
                }
                .onChange(of: scenePhase) { _, phase in
                    guard phase == .active else { return }
                    Task { await reconcileTimer() }
                }
        }
    }

    private func reconcileTimer() async {
        await timerCoordinator.reconcile(ordinaryAlarmIDs: Set(alarmStore.alarms.map(\.id)))
    }

    private func startAutomationTimerIfRequested() {
#if DEBUG
        let arguments = ProcessInfo.processInfo.arguments
        guard timerCoordinator.session == nil,
              let index = arguments.firstIndex(of: "-SmartisanTimerTestDurationSeconds"),
              arguments.indices.contains(index + 1),
              let duration = TimeInterval(arguments[index + 1]),
              duration > 0 else { return }
        timerCoordinator.start(duration: duration)
#endif
    }
}
