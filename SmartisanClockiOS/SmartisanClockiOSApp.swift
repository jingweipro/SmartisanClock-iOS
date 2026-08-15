import SwiftUI

@main
struct SmartisanClockiOSApp: App {
    @StateObject private var alarmStore = AlarmStore()
    @StateObject private var cityStore = CityStore()
    @StateObject private var alarmService = AlarmKitService()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(alarmStore)
                .environmentObject(cityStore)
                .environmentObject(alarmService)
                .preferredColorScheme(.light)
                .task { SmartisanAssets.registerFonts() }
        }
    }
}
