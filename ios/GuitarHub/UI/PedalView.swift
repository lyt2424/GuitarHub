import SwiftUI

struct PedalView: View {
    @EnvironmentObject private var hub: DeviceHub
    @State private var editing: PedalMapping?
    @State private var showingNew = false

    private var bank: PedalBank? { hub.store.activeBank }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    PedalConnectionCard(input: hub.pedalInput)
                } header: {
                    Text("蓝牙 MIDI 踏板")
                } footer: {
                    Text("踏板直连本 App（不经过系统蓝牙 MIDI），因此可以由 App 决定转发给音箱还是 KORG。常用型号：iRig BlueBoard、M-Vave Chocolate、XSONIC Airstep、Hotone Pulze Control。")
                }

                Section("踏板组") {
                    Picker("当前组", selection: Binding(
                        get: { hub.store.data.activeBankID ?? bank?.id },
                        set: { hub.store.data.activeBankID = $0 }
                    )) {
                        ForEach(hub.store.data.pedalBanks) { item in
                            Text(item.name).tag(Optional(item.id))
                        }
                    }
                }

                if let bank {
                    Section {
                        ForEach(bank.mappings) { mapping in
                            Button {
                                editing = mapping
                            } label: {
                                HStack {
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(mapping.trigger.label)
                                            .font(.caption.monospaced())
                                            .foregroundStyle(Theme.accent)
                                        Text(mapping.displayTitle)
                                            .font(.subheadline)
                                    }
                                    Spacer()
                                    Image(systemName: "chevron.right")
                                        .font(.caption)
                                        .foregroundStyle(.tertiary)
                                }
                            }
                            .buttonStyle(.plain)
                        }
                        .onDelete { offsets in
                            var copy = bank
                            copy.mappings.remove(atOffsets: offsets)
                            hub.store.updateBank(copy)
                        }
                    } header: {
                        HStack {
                            Text("映射")
                            Spacer()
                            Button {
                                showingNew = true
                            } label: {
                                Image(systemName: "plus.circle")
                            }
                        }
                    }
                }

                Section("实时监视") {
                    HStack {
                        Text(hub.pedal.lastEvent)
                            .font(.caption.monospaced())
                        Spacer()
                        Text("\(hub.pedal.pressCount) 次")
                            .font(.caption2.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                    ForEach(Array(hub.pedal.logLines.suffix(20).enumerated()), id: \.offset) { _, line in
                        Text(line)
                            .font(.caption2.monospaced())
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(Theme.background)
            .navigationTitle("踏板")
            .sheet(item: $editing) { mapping in
                MappingEditor(mapping: mapping) { updated in
                    guard var copy = hub.store.activeBank,
                          let index = copy.mappings.firstIndex(where: { $0.id == updated.id }) else { return }
                    copy.mappings[index] = updated
                    hub.store.updateBank(copy)
                }
            }
            .sheet(isPresented: $showingNew) {
                MappingEditor(mapping: nil) { created in
                    guard var copy = hub.store.activeBank else { return }
                    copy.mappings.append(created)
                    hub.store.updateBank(copy)
                }
            }
        }
    }
}

private struct PedalConnectionCard: View {
    @ObservedObject var input: BLEMIDIPedal
    @EnvironmentObject private var hub: DeviceHub

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                StatusDot(status: input.status)
                Text(input.status.label)
                    .font(.subheadline)
                Spacer()
                if input.status.isConnected {
                    Button("断开") { input.disconnect() }
                        .font(.caption)
                } else {
                    Button(input.isScanning ? "搜索中…" : "搜索踏板") { input.startScan() }
                        .font(.caption)
                        .disabled(input.isScanning)
                    Button("重连") { input.connectLast() }
                        .font(.caption)
                }
            }

            if !input.candidates.isEmpty, !input.status.isConnected {
                ForEach(input.candidates) { candidate in
                    Button {
                        input.connect(to: candidate.id)
                    } label: {
                        HStack {
                            Text(candidate.name).font(.footnote)
                            Spacer()
                            Text("\(candidate.rssi) dBm")
                                .font(.caption2.monospacedDigit())
                                .foregroundStyle(.secondary)
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - 映射编辑器

enum ActionKind: String, CaseIterable, Identifiable, Hashable {
    case none, ampModule, ampPresetStep, ampPreset, ampTapTempo, ampParamFollow
    case korgProgram, korgStep, korgSetlistNext, bankStep

    var id: String { rawValue }
    var label: String {
        switch self {
        case .none:            return "无动作"
        case .ampModule:       return "切换模块开关"
        case .ampPresetStep:   return "上/下一个音色"
        case .ampPreset:       return "跳到指定音色"
        case .ampTapTempo:     return "Tap Tempo"
        case .ampParamFollow:  return "表情踏板跟随参数"
        case .korgProgram:     return "Module 指定音色"
        case .korgStep:        return "Module 上/下一个音色"
        case .korgSetlistNext: return "Module 下一音色表"
        case .bankStep:        return "切换踏板组"
        }
    }
}

struct MappingEditor: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var hub: DeviceHub

    let original: PedalMapping?
    let onSave: (PedalMapping) -> Void

    @State private var triggerKind: Int = 0        // 0=CC 1=表情 2=Note 3=PC
    @State private var number: Int = 20
    @State private var actionKind: ActionKind = .ampModule
    @State private var deviceID: DeviceProfileID = ""
    @State private var moduleID: ModuleID = ""
    @State private var index: Int = 0
    @State private var delta: Int = 1

    init(mapping: PedalMapping?, onSave: @escaping (PedalMapping) -> Void) {
        self.original = mapping
        self.onSave = onSave
        if let mapping {
            _triggerKind = State(initialValue: Self.kindIndex(mapping.trigger))
            _number = State(initialValue: Self.number(mapping.trigger))
            _actionKind = State(initialValue: Self.actionKind(mapping.action))
            switch mapping.action {
            case .ampModule(let device, let module):
                _deviceID = State(initialValue: device)
                _moduleID = State(initialValue: module)
            case .ampPresetStep(let device, let delta):
                _deviceID = State(initialValue: device)
                _delta = State(initialValue: delta)
            case .ampPreset(let device, let value):
                _deviceID = State(initialValue: device)
                _index = State(initialValue: value)
            case .ampTapTempo(let device):
                _deviceID = State(initialValue: device)
            case .ampParamFollow(let device, let module, _):
                _deviceID = State(initialValue: device)
                _moduleID = State(initialValue: module)
            case .korgProgram(let program):
                _index = State(initialValue: program)
            case .korgStep(let value):
                _delta = State(initialValue: value)
            default:
                break
            }
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("触发") {
                    Picker("类型", selection: $triggerKind) {
                        Text("CC（踩钉）").tag(0)
                        Text("CC（表情）").tag(1)
                        Text("Note").tag(2)
                        Text("PC").tag(3)
                    }
                    Stepper("编号 \(number)", value: $number, in: 0...127)
                }

                Section("动作") {
                    Picker("动作", selection: $actionKind) {
                        ForEach(ActionKind.allCases) { kind in
                            Text(kind.label).tag(kind)
                        }
                    }

                    if actionKind != .none && actionKind != .korgProgram
                        && actionKind != .korgStep && actionKind != .korgSetlistNext
                        && actionKind != .bankStep {
                        Picker("设备", selection: $deviceID) {
                            ForEach(hub.devices) { device in
                                Text(device.profile.name).tag(device.profile.id)
                            }
                        }
                        .onAppear {
                            if deviceID.isEmpty { deviceID = hub.devices.first?.profile.id ?? "" }
                        }
                    }

                    if actionKind == .ampModule || actionKind == .ampParamFollow {
                        Picker("模块", selection: $moduleID) {
                            ForEach(modules) { module in
                                Text(module.name).tag(module.id)
                            }
                        }
                        .onAppear {
                            if moduleID.isEmpty { moduleID = modules.first?.id ?? "" }
                        }
                    }

                    if actionKind == .ampPreset || actionKind == .korgProgram {
                        Stepper("目标编号 \(index)", value: $index, in: 0...127)
                    }
                    if actionKind == .ampPresetStep || actionKind == .korgStep || actionKind == .bankStep {
                        Stepper("步进 \(delta > 0 ? "+1" : "-1")", value: $delta, in: -1...1)
                    }
                }
            }
            .navigationTitle(original == nil ? "新增映射" : "编辑映射")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        onSave(build())
                        dismiss()
                    }
                }
            }
        }
        .onAppear {
            if deviceID.isEmpty { deviceID = hub.devices.first?.profile.id ?? "" }
            if moduleID.isEmpty { moduleID = modules.first?.id ?? "" }
        }
    }

    private var modules: [ModuleSpec] {
        hub.device(id: deviceID)?.profile.modules ?? []
    }

    private func build() -> PedalMapping {
        let trigger: PedalTrigger
        switch triggerKind {
        case 1: trigger = .expression(number: number)
        case 2: trigger = .note(number: number)
        case 3: trigger = .pc(number: number)
        default: trigger = .cc(number: number)
        }

        let action: PedalAction
        switch actionKind {
        case .none: action = .none
        case .ampModule: action = .ampModule(device: deviceID, module: moduleID)
        case .ampPresetStep: action = .ampPresetStep(device: deviceID, delta: delta >= 0 ? 1 : -1)
        case .ampPreset: action = .ampPreset(device: deviceID, index: index)
        case .ampTapTempo: action = .ampTapTempo(device: deviceID)
        case .ampParamFollow:
            action = .ampParamFollow(device: deviceID, module: moduleID, param: 0)
        case .korgProgram: action = .korgProgram(program: index)
        case .korgStep: action = .korgStep(delta: delta >= 0 ? 1 : -1)
        case .korgSetlistNext: action = .korgSetlistNext
        case .bankStep: action = .bankStep(delta: delta >= 0 ? 1 : -1)
        }
        return PedalMapping(id: original?.id ?? UUID(), trigger: trigger, action: action)
    }

    private static func kindIndex(_ trigger: PedalTrigger) -> Int {
        switch trigger {
        case .cc: return 0
        case .expression: return 1
        case .note: return 2
        case .pc: return 3
        }
    }

    private static func number(_ trigger: PedalTrigger) -> Int {
        switch trigger {
        case .cc(let n), .expression(let n), .note(let n), .pc(let n): return n
        }
    }

    private static func actionKind(_ action: PedalAction) -> ActionKind {
        switch action {
        case .none: return .none
        case .ampModule: return .ampModule
        case .ampPresetStep: return .ampPresetStep
        case .ampPreset: return .ampPreset
        case .ampTapTempo: return .ampTapTempo
        case .ampParamFollow: return .ampParamFollow
        case .korgProgram: return .korgProgram
        case .korgStep: return .korgStep
        case .korgSetlistNext: return .korgSetlistNext
        case .bankStep: return .bankStep
        }
    }
}
