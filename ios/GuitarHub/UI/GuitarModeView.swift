import SwiftUI

struct GuitarModeView: View {
    @EnvironmentObject private var hub: DeviceHub

    @State private var selectedModule: ModuleID?
    @State private var showSettings = false
    @State private var showPresets = false
    @State private var renaming = false
    @State private var draftName = ""

    private var device: AmpDevice? { hub.selectedDevice }

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.background.ignoresSafeArea()
                ScrollView {
                    VStack(spacing: 12) {
                        if let device {
                            presetCard(device)
                            moduleGrid(device)
                            parameterPanel(device)
                        } else {
                            Card {
                                Text("还没有加载设备配置。")
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .padding(14)
                }
            }
            .navigationTitle(device?.profile.name ?? "电吉他")
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
                        Menu {
                            ForEach(hub.guitarDevices) { item in
                                Button {
                                    hub.enterGuitar(item.profile.id)
                                } label: {
                                    Label("\(item.profile.name)\(item.status.isConnected ? "（已连接）" : "")",
                                          systemImage: item.profile.id == hub.selectedDeviceID ? "checkmark" : "circle")
                                }
                            }
                        } label: {
                            Image(systemName: "hifispeaker.2")
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
            .sheet(isPresented: $showPresets) {
                if let device {
                    PresetListSheet(device: device) { index in
                        device.selectPreset(index)
                    }
                }
            }
            .alert("音色显示名", isPresented: $renaming) {
                TextField("中文名", text: $draftName)
                Button("取消", role: .cancel) {}
                Button("保存") {
                    device?.renameCurrentPreset(draftName)
                }
            } message: {
                Text("留空则恢复设备原名。")
            }
        }
    }

    // MARK: - 音色卡

    private func presetCard(_ device: AmpDevice) -> some View {
        Card {
            VStack(spacing: 10) {
                HStack {
                    Text(device.status.label)
                        .font(.caption)
                        .foregroundStyle(device.status.isConnected ? Theme.onColor : .secondary)
                    Spacer()
                    Text("预设 \(device.presetIndex + 1) / \(device.effectivePresetCount)")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                    Button {
                        showPresets = true
                    } label: {
                        Image(systemName: "list.bullet")
                            .font(.caption)
                    }
                }

                HStack(alignment: .firstTextBaseline) {
                    Text(device.presetName)
                        .font(.system(size: 42, weight: .bold, design: .rounded))
                        .minimumScaleFactor(0.35)
                        .lineLimit(1)
                    Spacer()
                    Button {
                        draftName = device.presetName
                        renaming = true
                    } label: {
                        Image(systemName: "pencil")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .contentShape(Rectangle())
                .onTapGesture {
                    draftName = device.presetName
                    renaming = true
                }

                HStack(spacing: 9) {
                    BigControlButton(systemImage: "chevron.left", title: "上一") {
                        device.stepPreset(-1)
                    }
                    BigControlButton(systemImage: "chevron.right", title: "下一") {
                        device.stepPreset(1)
                    }
                    BigControlButton(systemImage: "arrow.clockwise", title: "读取") {
                        device.requestState()
                    }
                    if device.profile.capabilities.tapTempo {
                        BigControlButton(systemImage: "metronome", title: "Tap") {
                            device.tapTempo()
                        }
                    }
                    Spacer(minLength: 0)
                }

                if !device.status.isConnected {
                    Button {
                        if device.isScanning { device.stopScan() } else { device.startScan() }
                    } label: {
                        Label(device.isScanning ? "搜索中…" : "搜索并连接 \(device.profile.name)",
                              systemImage: "dot.radiowaves.left.and.right")
                            .font(.footnote.weight(.semibold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 8)
                            .background(Theme.cardHigh, in: Capsule())
                    }
                    .buttonStyle(.plain)

                    if !device.candidates.isEmpty {
                        VStack(spacing: 6) {
                            ForEach(device.candidates) { candidate in
                                Button {
                                    device.connect(to: candidate.id)
                                } label: {
                                    HStack {
                                        Text(candidate.name)
                                            .font(.footnote.weight(.medium))
                                        Spacer()
                                        Text("\(candidate.rssi) dBm")
                                            .font(.caption2.monospacedDigit())
                                            .foregroundStyle(.secondary)
                                        Image(systemName: "chevron.right")
                                            .font(.caption2)
                                            .foregroundStyle(.tertiary)
                                    }
                                    .padding(.vertical, 6)
                                    .padding(.horizontal, 10)
                                    .background(Theme.cardHigh, in: RoundedRectangle(cornerRadius: 10))
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    } else if device.isScanning {
                        ProgressView().frame(maxWidth: .infinity)
                    }
                }
            }
        }
    }

    // MARK: - 颜色块

    private func moduleGrid(_ device: AmpDevice) -> some View {
        let modules = device.modules.filter { !(device.profile.module($0.id)?.isGlobal ?? false) }
        return LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 3), spacing: 10) {
            ForEach(modules) { state in
                if let spec = device.profile.module(state.id) {
                    ModuleBlock(
                        spec: spec,
                        enabled: state.enabled,
                        selected: activeModule(device) == state.id,
                        onToggle: {
                            selectedModule = state.id
                            device.toggleModule(state.id)
                        },
                        onEdit: {
                            selectedModule = state.id
                        }
                    )
                    .disabled(!device.status.isConnected)
                    .opacity(device.status.isConnected ? 1 : 0.6)
                }
            }
        }
    }

    private func activeModule(_ device: AmpDevice) -> ModuleID? {
        selectedModule ?? device.modules.first { !(device.profile.module($0.id)?.isGlobal ?? false) }?.id
    }

    // MARK: - 参数

    @ViewBuilder
    private func parameterPanel(_ device: AmpDevice) -> some View {
        if let moduleID = activeModule(device),
           let spec = device.profile.module(moduleID) {
            let params = device.visibleParams(moduleID)
            Card {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text(spec.name).font(.headline)
                        Text(spec.badge)
                            .font(.caption2.monospaced())
                            .foregroundStyle(.secondary)
                        Spacer()
                        if spec.bypass.kind != .none {
                            Toggle("", isOn: Binding(
                                get: { device.isModuleEnabled(moduleID) },
                                set: { device.setModule(moduleID, enabled: $0) }
                            ))
                            .labelsHidden()
                            .tint(Theme.onColor)
                        }
                    }

                    if params.isEmpty {
                        Text("该模块没有可调参数（设备未上报，或官方协议未开放）。")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(params) { param in
                            VStack(spacing: 2) {
                                HStack {
                                    Text(param.name).font(.footnote)
                                    Spacer()
                                    Text("\(Int(device.value(moduleID, param.id).rounded()))\(param.unit)")
                                        .font(.footnote.monospacedDigit())
                                        .foregroundStyle(.secondary)
                                }
                                Slider(
                                    value: Binding(
                                        get: { device.value(moduleID, param.id) },
                                        set: { device.setParameter(moduleID, param: param.id, value: $0) }
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
        }
    }
}

// MARK: - 音色表（可改名、可跳转）

struct PresetListSheet: View {
    @ObservedObject var device: AmpDevice
    let onSelect: (Int) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                ForEach(0..<device.effectivePresetCount, id: \.self) { index in
                    HStack(spacing: 10) {
                        Text("\(index + 1)")
                            .font(.caption.monospacedDigit())
                            .frame(width: 34, alignment: .leading)
                            .foregroundStyle(index == device.presetIndex ? Theme.accent : .secondary)

                        TextField("显示名", text: Binding(
                            get: { device.displayName(at: index) },
                            set: { device.renamePreset($0, at: index) }
                        ))
                        .font(.subheadline)

                        if index == device.presetIndex {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(Theme.accent)
                        }
                    }
                    .contentShape(Rectangle())
                    .onTapGesture {
                        onSelect(index)
                        dismiss()
                    }
                }
            }
            .navigationTitle("音色表")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { dismiss() }
                }
            }
        }
    }
}
