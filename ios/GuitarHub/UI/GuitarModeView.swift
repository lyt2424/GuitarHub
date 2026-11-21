import SwiftUI
import CoreBluetooth

struct GuitarModeView: View {
    @EnvironmentObject private var hub: DeviceHub
    @State private var showSettings = false
    @State private var showPedal = false

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.background.ignoresSafeArea()
                if let device = hub.selectedDevice {
                    GuitarDeviceView(device: device)
                } else {
                    Card {
                        Text("还没有加载设备配置。")
                            .foregroundStyle(.secondary)
                    }
                    .padding(14)
                }
            }
            .navigationTitle(hub.selectedDevice?.profile.name ?? "电吉他")
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

/// 单独一层，用 @ObservedObject 订阅设备，这样 presetName / modules 变化时界面会实时刷新。
private struct GuitarDeviceView: View {
    @ObservedObject var device: AmpDevice
    @Environment(\.verticalSizeClass) private var verticalSizeClass

    @State private var selectedModule: ModuleID?
    @State private var showPresets = false
    @State private var renaming = false
    @State private var draftName = ""

    // 鼓机播放状态（设备不回报，只在本机记）
    @State private var drumPlaying = false
    // Tap 计速
    @State private var tapTimes: [Date] = []
    @State private var tappedBPM: Double?

    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                presetCard
                moduleGrid
                drumPanel
                globalPanel
                parameterPanel
            }
            .padding(14)
        }
        .sheet(isPresented: $showPresets) {
            PresetListSheet(device: device) { index in
                device.selectPreset(index)
            }
        }
        .alert("音色显示名", isPresented: $renaming) {
            TextField("中文名", text: $draftName)
            Button("取消", role: .cancel) {}
            Button("保存") { device.renameCurrentPreset(draftName) }
        } message: {
            Text("留空则恢复默认名称。")
        }
    }

    // MARK: - 音色卡

    private var presetCard: some View {
        Card {
            VStack(spacing: 10) {
                HStack {
                    Text(device.status.label)
                        .font(.caption)
                        .foregroundStyle(device.status.isConnected ? Theme.onColor : .secondary)
                    Spacer()
                    Button {
                        showPresets = true
                    } label: {
                        Text("预设 \(device.presetIndex + 1) / \(device.effectivePresetCount)")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }

                if !device.status.isConnected {
                    HStack(spacing: 6) {
                        Image(systemName: "info.circle")
                        Text(bluetoothHint)
                    }
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
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

                HStack(spacing: 10) {
                    iconButton("chevron.left") { device.stepPreset(-1) }
                    iconButton("chevron.right") { device.stepPreset(1) }
                    iconButton("arrow.clockwise", size: 16) { device.requestState() }
                    Spacer(minLength: 0)
                    if device.profile.capabilities.tapTempo {
                        tapButton
                    }
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

    private func iconButton(_ systemImage: String, size: CGFloat = 18, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: size, weight: .bold))
                .frame(width: 56, height: 46)
                .background(Theme.cardHigh, in: RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
    }

    /// TAP 竖排：上面 TAP，下面当前 BPM。
    private var tapButton: some View {
        Button {
            handleTap()
        } label: {
            VStack(spacing: 1) {
                Text("TAP")
                    .font(.system(size: 13, weight: .heavy, design: .rounded))
                Text(bpmText)
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
            .frame(width: 60, height: 46)
            .background(Theme.cardHigh, in: RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
    }

    private var bpmText: String {
        if let tappedBPM {
            return "\(Int(tappedBPM.rounded())) BPM"
        }
        guard let drum = device.moduleState("drum") else { return "— BPM" }
        return "\(Int(drum.value(0, fallback: 120))) BPM"
    }

    /// 连点两下以上按间隔估算 BPM，并同步显示；同时照常发 Tap。
    private func handleTap() {
        let now = Date()
        tapTimes.append(now)
        if tapTimes.count > 6 { tapTimes.removeFirst(tapTimes.count - 6) }
        if tapTimes.count >= 2 {
            let intervals = zip(tapTimes.dropFirst(), tapTimes).map { pair in
                pair.0.timeIntervalSince(pair.1)
            }
            let valid = intervals.filter { $0 > 0.2 && $0 < 2.0 }
            if !valid.isEmpty {
                let average = valid.reduce(0, +) / Double(valid.count)
                let bpm = 60.0 / average
                if bpm >= 40, bpm <= 300 {
                    tappedBPM = bpm
                }
            }
        }
        device.tapTempo()
    }

    // MARK: - 鼓机

    @ViewBuilder
    private var drumPanel: some View {
        if device.profile.module("drum") != nil, device.moduleState("drum") != nil {
            Card {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text("鼓机").font(.headline)
                        Spacer()
                        Text("\(Int(device.value("drum", 0))) BPM")
                            .font(.footnote.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }

                    Button {
                        drumPlaying.toggle()
                        device.sendCC(61, drumPlaying ? 127 : 0)
                    } label: {
                        Label(drumPlaying ? "停止" : "播放",
                              systemImage: drumPlaying ? "stop.fill" : "play.fill")
                            .font(.footnote.weight(.semibold))
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(drumPlaying ? Theme.danger : Theme.onColor)

                    HStack(spacing: 10) {
                        Button {
                            bumpDrumStyle(-1)
                        } label: {
                            Label("上一个鼓机", systemImage: "backward.end")
                                .font(.footnote.weight(.semibold))
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)

                        Button {
                            bumpDrumStyle(1)
                        } label: {
                            Label("下一个鼓机", systemImage: "forward.end")
                                .font(.footnote.weight(.semibold))
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                    }

                    HStack(spacing: 10) {
                        Button {
                            adjustTempo(-1)
                        } label: {
                            Image(systemName: "minus")
                                .font(.footnote.weight(.bold))
                                .frame(width: 34, height: 34)
                                .background(Theme.cardHigh, in: RoundedRectangle(cornerRadius: 9))
                        }
                        .buttonStyle(.plain)

                        Slider(
                            value: Binding(
                                get: { device.value("drum", 0) },
                                set: {
                                    device.setParameter("drum", param: 0, value: $0)
                                    tappedBPM = nil
                                }
                            ),
                            in: 40...300,
                            step: 1
                        )
                        .tint(Theme.accent)

                        Button {
                            adjustTempo(1)
                        } label: {
                            Image(systemName: "plus")
                                .font(.footnote.weight(.bold))
                                .frame(width: 34, height: 34)
                                .background(Theme.cardHigh, in: RoundedRectangle(cornerRadius: 9))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private func adjustTempo(_ delta: Double) {
        let next = (device.value("drum", 0) + delta).clamped(to: 40...300)
        device.setParameter("drum", param: 0, value: next)
        tappedBPM = nil
    }

    /// 官方表里鼓机只有 CC67 风格号（0–99），用它实现“上一个 / 下一个鼓机”。
    private func bumpDrumStyle(_ delta: Int) {
        let current = Int(device.value("drum", 1))
        var next = current + delta
        if next < 0 { next = 99 }
        if next > 99 { next = 0 }
        device.setParameter("drum", param: 1, value: Double(next))
    }

    private var bluetoothHint: String {
        switch device.bluetoothState {
        case .poweredOn:
            if device.isScanning {
                return device.candidates.isEmpty
                    ? "正在搜索附近蓝牙设备…"
                    : "发现 \(device.candidates.count) 台设备，点名字连接"
            }
            return "点上方按钮开始搜索"
        case .unauthorized:
            return "蓝牙权限未开启：设置 → 隐私与安全性 → 蓝牙 → 吉他中枢"
        case .poweredOff:
            return "蓝牙已关闭，请在控制中心打开"
        case .unsupported:
            return "此设备不支持蓝牙"
        default:
            return "正在初始化蓝牙…"
        }
    }

    // MARK: - 颜色块

    private var moduleGrid: some View {
        let modules = device.modules.filter { !(device.profile.module($0.id)?.isGlobal ?? false) }
        // 横屏（verticalSizeClass == .compact）多放一列，演出时一屏看全。
        let columnCount = verticalSizeClass == .compact ? 4 : 3
        return LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: columnCount), spacing: 10) {
            ForEach(modules) { state in
                if let spec = device.profile.module(state.id) {
                    ModuleBlock(
                        spec: spec,
                        enabled: state.enabled,
                        selected: activeModule == state.id,
                        onToggle: {
                            selectedModule = state.id
                            device.toggleModule(state.id)
                        },
                        onEdit: {
                            selectedModule = state.id
                        }
                    )
                }
            }
        }
    }

    // MARK: - 全局模块（音量等）

    @ViewBuilder
    private var globalPanel: some View {
        let globals = device.modules.filter {
            (device.profile.module($0.id)?.isGlobal ?? false) && $0.id != "drum"
        }
        if !globals.isEmpty {
            Card {
                VStack(alignment: .leading, spacing: 10) {
                    SectionTitle(text: "全局")
                    ForEach(globals) { state in
                        if let spec = device.profile.module(state.id) {
                            Text(spec.name)
                                .font(.footnote.weight(.semibold))
                                .foregroundStyle(.secondary)
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
            }
        }
    }

    private var activeModule: ModuleID? {
        selectedModule ?? device.modules.first { !(device.profile.module($0.id)?.isGlobal ?? false) }?.id
    }

    // MARK: - 参数

    @ViewBuilder
    private var parameterPanel: some View {
        if let moduleID = activeModule,
           let spec = device.profile.module(moduleID),
           !device.visibleParams(moduleID).isEmpty {
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

// MARK: - 音色表

struct PresetListSheet: View {
    @ObservedObject var device: AmpDevice
    let onSelect: (Int) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var renamingIndex: Int?
    @State private var draft = ""

    var body: some View {
        NavigationStack {
            List {
                ForEach(0..<device.effectivePresetCount, id: \.self) { index in
                    Button {
                        onSelect(index)
                        dismiss()
                    } label: {
                        HStack(spacing: 10) {
                            Text("\(index + 1)")
                                .font(.caption.monospacedDigit())
                                .frame(width: 34, alignment: .leading)
                                .foregroundStyle(index == device.presetIndex ? Theme.accent : .secondary)

                            Text(device.displayName(at: index))
                                .font(.subheadline)
                                .foregroundStyle(.primary)

                            Spacer()

                            if index == device.presetIndex {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(Theme.accent)
                            }
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .swipeActions {
                        Button("改名") {
                            draft = device.displayName(at: index)
                            renamingIndex = index
                        }
                        .tint(Theme.accent)
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
            .alert("改名", isPresented: Binding(
                get: { renamingIndex != nil },
                set: { if !$0 { renamingIndex = nil } }
            )) {
                TextField("显示名", text: $draft)
                Button("取消", role: .cancel) {}
                Button("保存") {
                    if let index = renamingIndex {
                        device.renamePreset(draft, at: index)
                    }
                }
            } message: {
                Text("长按列表项左滑也可以改名。")
            }
        }
    }
}
