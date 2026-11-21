import SwiftUI

struct KeyboardModeView: View {
    @EnvironmentObject private var hub: DeviceHub
    @State private var showSettings = false
    @State private var showPedal = false

    var body: some View {
        NavigationStack {
            KorgScreen(korg: hub.korg, store: hub.store, midi: hub.midi, ble: hub.bleMIDI)
                .background(Theme.background)
                .navigationTitle("键盘模式")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .navigationBarLeading) {
                        Button {
                            hub.backToLaunch()
                        } label: {
                            Image(systemName: "chevron.left")
                        }
                    }
                    ToolbarItem(placement: .navigationBarTrailing) {
                        HStack(spacing: 14) {
                            Button {
                                showPedal = true
                            } label: {
                                Image(systemName: "shoe.2")
                            }
                            Button {
                                showSettings = true
                            } label: {
                                Image(systemName: "gearshape")
                            }
                        }
                    }
                }
                .sheet(isPresented: $showSettings) {
                    SettingsView().environmentObject(hub)
                }
                .sheet(isPresented: $showPedal) {
                    PedalView().environmentObject(hub)
                }
        }
    }
}
