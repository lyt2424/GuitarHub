import SwiftUI

@main
struct GuitarHubApp: App {
    @StateObject private var hub = DeviceHub()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(hub)
                .preferredColorScheme(.dark)
                .onChange(of: scenePhase) { phase in
                    if phase == .active {
                        hub.onAppActive()
                    }
                }
        }
    }
}
