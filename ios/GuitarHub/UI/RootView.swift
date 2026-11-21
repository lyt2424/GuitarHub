import SwiftUI

struct RootView: View {
    @EnvironmentObject private var hub: DeviceHub

    var body: some View {
        Group {
            switch hub.mode {
            case .launch:
                LaunchView()
            case .guitar:
                GuitarModeView()
            case .keyboard:
                KeyboardModeView()
            }
        }
        .tint(Theme.accent)
    }
}

// MARK: - 启动页：两个入口

struct LaunchView: View {
    @EnvironmentObject private var hub: DeviceHub
    @State private var showSettings = false
    @State private var showDevices = false

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.background.ignoresSafeArea()
                VStack(alignment: .leading, spacing: 14) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("吉他中枢")
                            .font(.system(size: 34, weight: .bold))
                        Text("选择今天的入口")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.top, 12)

                    ModeCard(
                        icon: "guitars",
                        title: "电吉他模式",
                        subtitle: hub.selectedDevice?.profile.name ?? "音箱 / 效果器",
                        detail: hub.selectedDevice.map { $0.status.label } ?? "未选择设备",
                        color: Theme.accent
                    ) {
                        if let id = hub.selectedDeviceID {
                            hub.enterGuitar(id)
                        }
                    }

                    ModeCard(
                        icon: "pianokeys",
                        title: "键盘模式",
                        subtitle: "KORG Module",
                        detail: "Program Change 控制",
                        color: Color(red: 0.30, green: 0.62, blue: 1.0)
                    ) {
                        hub.enterKeyboard()
                    }

                    Spacer(minLength: 0)

                    HStack(spacing: 12) {
                        StatusDot(status: hub.pedalInput.status)
                        Text(hub.pedalInput.status.isConnected ? "踏板已连接" : "踏板未连接")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button {
                            showDevices = true
                        } label: {
                            Label("连接与调试", systemImage: "dot.radiowaves.left.and.right")
                                .font(.caption)
                        }
                        .buttonStyle(.bordered)
                    }
                    .padding(.bottom, 8)
                }
                .padding(20)
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        showSettings = true
                    } label: {
                        Image(systemName: "gearshape")
                    }
                }
            }
            .sheet(isPresented: $showSettings) {
                SettingsView().environmentObject(hub)
            }
            .sheet(isPresented: $showDevices) {
                DeviceView().environmentObject(hub)
            }
            .onAppear { hub.prepareAutoConnect() }
        }
    }
}

private struct ModeCard: View {
    let icon: String
    let title: String
    let subtitle: String
    let detail: String
    let color: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 16) {
                Image(systemName: icon)
                    .font(.system(size: 30, weight: .semibold))
                    .frame(width: 54, height: 54)
                    .background(RoundedRectangle(cornerRadius: 14).fill(color.opacity(0.18)))
                    .foregroundStyle(color)

                VStack(alignment: .leading, spacing: 3) {
                    Text(title).font(.title3.weight(.bold))
                    Text(subtitle).font(.subheadline).foregroundStyle(.secondary)
                    Text(detail).font(.caption2).foregroundStyle(.tertiary)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .foregroundStyle(.tertiary)
            }
            .padding(16)
            .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(Theme.card))
        }
        .buttonStyle(.plain)
    }
}
