import SwiftUI

@main
struct GuitarHubApp: App {
    @StateObject private var hub = DeviceHub()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(hub)
                .preferredColorScheme(.dark)
        }
    }
}
