import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var hub: DeviceHub

    var body: some View {
        NavigationStack {
            SettingsContent(store: hub.store,
                            profiles: hub.profiles,
                            hub: hub)
                .navigationTitle("设置")
        }
    }
}

private struct SettingsContent: View {
    @ObservedObject var store: AppStore
    @ObservedObject var profiles: ProfileStore
    let hub: DeviceHub

    var body: some View {
        Form {
            Section {
                Toggle("召回音色时整包下发参数", isOn: Binding(
                    get: { store.data.settings.pushFullStateOnRecall },
                    set: { store.data.settings.pushFullStateOnRecall = $0 }
                ))
                Toggle("自动把设备状态存进预设库", isOn: Binding(
                    get: { store.data.settings.autoCapture },
                    set: { store.data.settings.autoCapture = $0 }
                ))
            } header: {
                Text("演出")
            } footer: {
                Text("Spark 能从音箱读回完整音色，所以默认以音箱为准；Pulze 这类不能读回的设备，靠本地预设库记住每个音色的开关与音量。")
            }

            Section {
                ForEach(profiles.profiles) { profile in
                    VStack(alignment: .leading, spacing: 3) {
                        Text(profile.name).font(.subheadline)
                        Text("\(profile.transport.kind.label) · \(profile.transport.codec.label)")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                Button("重新加载设备配置") { hub.reloadProfiles() }
                ForEach(profiles.issues, id: \.self) { issue in
                    Text(issue)
                        .font(.caption2)
                        .foregroundStyle(Theme.danger)
                }
            } header: {
                Text("设备配置")
            } footer: {
                Text("把新的设备 JSON 放进「文件」App → 我的 iPhone → 吉他Control → Profiles，再点上面按钮即可加载，不用重新编译。同名 id 会覆盖内置配置。")
            }

            Section("关于") {
                LabeledContent("版本", value: "1.0.0")
                Text("协议来源：Paul Hamshere 的 Spark 逆向文档与 SparkIO4 实现；Hotone 官方 Pulze MIDI Control Information List（Firmware V1.0.6）。以上均为个人学习用途，请遵守设备厂商的使用条款。")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }
}
