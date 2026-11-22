import SwiftUI

struct DeviceView: View {
    @EnvironmentObject private var hub: DeviceHub

    var body: some View {
        NavigationStack {
            List {
                ForEach(hub.devices) { device in
                    Section {
                        DeviceConnectionSection(device: device, hub: hub)
                    } header: {
                        HStack(spacing: 8) {
                            StatusDot(status: device.status)
                            Text(device.profile.name)
                            Spacer()
                            Text(device.status.label)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    } footer: {
                        if !device.profile.note.isEmpty {
                            Text(device.profile.note)
                        }
                    }
                }

                Section("踏板输入") {
                    NavigationLink {
                        PedalView()
                    } label: {
                        Label("蓝牙 MIDI 踏板设置", systemImage: "shoe.2")
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(Theme.background)
            .navigationTitle("设备")
        }
        .onAppear {
            Diagnostics.trafficVisible = true
            hub.devices.forEach { $0.publishTrafficHistory() }
        }
        .onDisappear { Diagnostics.trafficVisible = false }
    }
}

private struct DeviceConnectionSection: View {
    @ObservedObject var device: AmpDevice
    let hub: DeviceHub

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if !(hub.mode == .guitar && hub.selectedDeviceID == device.profile.id) {
                Text("当前演出模式不是它；连接会自动切换过去，并断开另一台。")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 10) {
                if device.status.isConnected {
                    Button(role: .destructive) {
                        device.disconnect()
                    } label: {
                        Label("断开", systemImage: "xmark.circle")
                    }
                    .buttonStyle(.bordered)

                    NavigationLink {
                        DeviceDetailView(device: device)
                    } label: {
                        Label("音色与调试", systemImage: "slider.horizontal.3")
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(Theme.accent)
                } else {
                    Button {
                        hub.selectForConnection(device)
                        device.startScan()
                    } label: {
                        Label(device.isScanning ? "搜索中…" : "搜索设备", systemImage: "dot.radiowaves.left.and.right")
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(Theme.accent)
                    .disabled(device.isScanning)

                    Button {
                        hub.enterGuitar(device.profile.id)
                    } label: {
                        Label("重连上次", systemImage: "arrow.clockwise")
                    }
                    .buttonStyle(.bordered)

                    NavigationLink {
                        DeviceDetailView(device: device)
                    } label: {
                        Image(systemName: "info.circle")
                    }
                    .buttonStyle(.bordered)
                }
                Spacer()
            }

            if let error = device.lastError {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(Theme.danger)
            }

            if !device.status.isConnected, !device.candidates.isEmpty {
                VStack(spacing: 6) {
                    ForEach(device.candidates) { candidate in
                        Button {
                            hub.connect(device, to: candidate.id)
                        } label: {
                            HStack {
                                Text(candidate.name)
                                    .font(.subheadline)
                                Spacer()
                                Text("\(candidate.rssi) dBm")
                                    .font(.caption2.monospacedDigit())
                                    .foregroundStyle(.secondary)
                                Image(systemName: "chevron.right")
                                    .font(.caption)
                                    .foregroundStyle(.tertiary)
                            }
                        }
                        .buttonStyle(.plain)
                        .padding(.vertical, 4)
                    }
                }
            } else if !device.status.isConnected, device.isScanning {
                ProgressView()
                    .frame(maxWidth: .infinity)
            }
        }
        .padding(.vertical, 4)
    }
}

struct DeviceDetailView: View {
    @ObservedObject var device: AmpDevice

    var body: some View {
        List {
            if !device.profileText.isEmpty {
                Section("GATT") {
                    Text(device.profileText)
                        .font(.caption2.monospaced())
                        .textSelection(.enabled)
                }
            }

            ForEach(device.modules) { state in
                if let spec = device.profile.module(state.id) {
                    Section {
                        if spec.bypass.kind != .none && !spec.isGlobal {
                            Toggle(isOn: Binding(
                                get: { device.isModuleEnabled(state.id) },
                                set: { device.setModule(state.id, enabled: $0) }
                            )) {
                                Text(spec.name)
                            }
                            .tint(Theme.onColor)
                        } else {
                            Text(spec.name)
                                .font(.headline)
                        }

                        ForEach(device.visibleParams(state.id)) { param in
                            VStack(spacing: 2) {
                                HStack {
                                    Text(param.name).font(.footnote)
                                    Spacer()
                                    Text("\(Int(device.value(state.id, param.id).rounded()))\(param.unit)")
                                        .font(.footnote.monospacedDigit())
                                        .foregroundStyle(.secondary)
                                }
                                Slider(
                                    value: Binding(
                                        get: { device.value(state.id, param.id) },
                                        set: { device.setParameter(state.id, param: param.id, value: $0) }
                                    ),
                                    in: param.minValue...param.maxValue,
                                    step: max(param.step, 0.01)
                                )
                                .tint(Theme.accent)
                            }
                        }
                    }
                }
            }

            Section("原始收发（最近 80 条）") {
                if device.traffic.isEmpty {
                    Text("暂无数据").font(.caption).foregroundStyle(.secondary)
                } else {
                    ForEach(Array(device.traffic.suffix(80).enumerated()), id: \.offset) { _, line in
                        Text(line)
                            .font(.caption2.monospaced())
                            .textSelection(.enabled)
                    }
                }
            }

            Section("日志") {
                ForEach(Array(device.logLines.suffix(80).enumerated()), id: \.offset) { _, line in
                    Text(line)
                        .font(.caption2.monospaced())
                }
            }
        }
        .navigationTitle(device.profile.name)
        .navigationBarTitleDisplayMode(.inline)
    }
}
