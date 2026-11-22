import Foundation
import CoreBluetooth
import Combine

/// 面向 UI 的单台设备状态容器：BLE 会话 + 协议编解码器 + 本地预设库。
enum Diagnostics {
    /// 设备调试页可见时才记录原始收发，避免演出界面被调试数据拖慢。
    static var trafficEnabled = false
}

final class AmpDevice: ObservableObject, Identifiable {

    let profile: DeviceProfile
    let session: BLESession
    let codec: DeviceCodec
    private let store: AppStore
    private var bag = Set<AnyCancellable>()

    @Published private(set) var status: ConnectionStatus = .disconnected
    @Published private(set) var bluetoothState: CBManagerState = .unknown
    @Published private(set) var candidates: [DiscoveredDevice] = []
    @Published private(set) var profileText: String = ""
    @Published private(set) var isScanning: Bool = false
    @Published private(set) var presetName: String = "—"
    @Published private(set) var presetIndex: Int = 0
    @Published private(set) var modules: [ModuleState] = []
    @Published private(set) var logLines: [String] = []
    @Published private(set) var lastError: String?
    /// 最近一次收发的原始字节（十六进制），用于调试与逆向新设备。
    @Published private(set) var traffic: [String] = []

    var id: String { profile.id }
    var isConnected: Bool { status.isConnected }

    init(profile: DeviceProfile, session: BLESession, codec: DeviceCodec, store: AppStore) {
        self.profile = profile
        self.session = session
        self.codec = codec
        self.store = store

        let lastIndex = store.library(profile.id).lastUsedPreset
        self.presetIndex = lastIndex
        self.presetName = store.alias(profile.id, index: lastIndex)
            ?? store.snapshot(profile.id, index: lastIndex)?.name
            ?? "音色 \(lastIndex + 1)"
        self.modules = profile.defaultModules
        if let snap = store.snapshot(profile.id, index: lastIndex) {
            self.modules = Self.merge(snapshot: snap.modules, profile: profile)
        }
        // 恢复上次的全局参数（音量等）。
        for i in self.modules.indices {
            guard let spec = profile.module(self.modules[i].id), spec.isGlobal else { continue }
            for p in spec.params {
                let key = Self.globalKey(profile.id, spec.id, p.id)
                if let saved = UserDefaults.standard.object(forKey: key) as? Double {
                    self.modules[i].values[p.id] = p.clamp(saved)
                }
            }
        }

        session.$status
            .receive(on: RunLoop.main)
            .sink { [weak self] value in self?.status = value }
            .store(in: &bag)
        session.$discovered
            .receive(on: RunLoop.main)
            .sink { [weak self] value in self?.candidates = value }
            .store(in: &bag)
        session.$bluetoothState
            .receive(on: RunLoop.main)
            .sink { [weak self] value in self?.bluetoothState = value }
            .store(in: &bag)
        session.$profile
            .receive(on: RunLoop.main)
            .sink { [weak self] value in self?.profileText = value }
            .store(in: &bag)
        session.$isScanning
            .receive(on: RunLoop.main)
            .sink { [weak self] value in self?.isScanning = value }
            .store(in: &bag)

        codec.eventHandler = { [weak self] event in
            DispatchQueue.main.async { self?.handle(event) }
        }
        session.onData = { [weak self] data in
            self?.recordTraffic(direction: "←", data: data)
            self?.codec.didReceive(data)
        }
        session.onSend = { [weak self] data in
            self?.recordTraffic(direction: "→", data: data)
        }
        session.onConnect = { [weak self] in
            guard let self else { return }
            self.codec.didConnect()
            if self.profile.capabilities.stateReadback {
                self.codec.requestState()
            }
        }
        session.onDisconnect = { [weak self] _ in self?.codec.didDisconnect() }
        session.onLog = { [weak self] message in self?.log(message) }
    }

    // MARK: - 连接

    func startScan() {
        lastError = nil
        session.startScan()
    }

    func stopScan() {
        session.stopScan()
    }

    func connect(to id: UUID) {
        lastError = nil
        UserDefaults.standard.set(id.uuidString, forKey: "last.\(profile.id)")
        session.connect(to: id)
    }

    func connectLast() {
        guard let raw = UserDefaults.standard.string(forKey: "last.\(profile.id)"),
              let uuid = UUID(uuidString: raw) else {
            startScan()
            return
        }
        session.connect(to: uuid)
        // 设备不在附近时，2 秒后自动转扫描。
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { [weak self] in
            guard let self else { return }
            if !self.status.isConnected, !self.status.isBusy {
                self.startScan()
            }
        }
    }

    func disconnect() {
        session.disconnect()
    }

    // MARK: - 音色

    var effectivePresetCount: Int {
        // 能读回状态的设备（Spark）以设备真实预设数为准，避免切到不存在的档位。
        if profile.capabilities.stateReadback {
            return max(1, profile.capabilities.presetCount)
        }
        let maxStored = (store.library(profile.id).snapshots.keys.max() ?? 0) + 1
        return max(profile.capabilities.presetCount, maxStored)
    }

    func selectPreset(_ index: Int) {
        guard index >= 0 else { return }
        presetIndex = index
        lastError = nil

        if profile.capabilities.stateReadback {
            codec.selectPreset(index)
            // 给音箱一点时间完成切换，再读回状态，否则会读到旧音色。
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [weak self] in
                self?.codec.requestState()
            }
            store.setLastUsedPreset(index, for: profile.id)
            return
        }

        codec.selectPreset(index)

        // 全局模块（音量等）不属于任何预设：切音色前后保持原值，也不参与整包下发。
        let globals = modules.filter { profile.module($0.id)?.isGlobal ?? false }

        if let snap = store.snapshot(profile.id, index: index) {
            presetName = store.alias(profile.id, index: index) ?? snap.name
            modules = Self.merge(snapshot: snap.modules, profile: profile)
        } else {
            presetName = store.alias(profile.id, index: index) ?? "音色 \(index + 1)"
            modules = profile.defaultModules
        }
        for saved in globals {
            if let i = modules.firstIndex(where: { $0.id == saved.id }) {
                modules[i] = saved
            }
        }

        if store.data.settings.pushFullStateOnRecall {
            pushAll()
        }
        store.setLastUsedPreset(index, for: profile.id)
        scheduleCapture()
        log("召回音色 \(index + 1)：\(presetName)")
    }

    func stepPreset(_ delta: Int) {
        let count = max(1, effectivePresetCount)
        let next = ((presetIndex + delta) % count + count) % count
        selectPreset(next)
    }

    /// 用户自定义显示名（中文）。清空则恢复设备/预设原名。
    func renameCurrentPreset(_ name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        store.setAlias(trimmed.isEmpty ? nil : trimmed, for: profile.id, index: presetIndex)
        if trimmed.isEmpty {
            presetName = store.snapshot(profile.id, index: presetIndex)?.name ?? "音色 \(presetIndex + 1)"
        } else {
            presetName = trimmed
        }
        scheduleCapture()
    }

    /// 给音色表里的任意一项改名（不需要先切过去）。
    func renamePreset(_ name: String, at index: Int) {
        store.setAlias(name, for: profile.id, index: index)
        if index == presetIndex {
            presetName = store.alias(profile.id, index: index) ?? presetName
        }
    }

    func displayName(at index: Int) -> String {
        store.alias(profile.id, index: index)
            ?? store.snapshot(profile.id, index: index)?.name
            ?? "音色 \(index + 1)"
    }

    // MARK: - 模块与参数

    func moduleState(_ id: ModuleID) -> ModuleState? {
        modules.first { $0.id == id }
    }

    func isModuleEnabled(_ id: ModuleID) -> Bool {
        moduleState(id)?.enabled ?? false
    }

    func toggleModule(_ id: ModuleID) {
        setModule(id, enabled: !isModuleEnabled(id))
    }

    func setModule(_ id: ModuleID, enabled: Bool) {
        guard let index = modules.firstIndex(where: { $0.id == id }) else { return }
        modules[index].enabled = enabled
        codec.setModule(id, enabled: enabled)
        scheduleCapture()
    }

    func value(_ module: ModuleID, _ param: Int) -> Double {
        guard let spec = profile.parameter(module: module, param: param) else { return 0 }
        return moduleState(module)?.value(param, fallback: spec.initialValue) ?? spec.initialValue
    }

    func setParameter(_ module: ModuleID, param: Int, value: Double) {
        guard let spec = profile.parameter(module: module, param: param),
              let index = modules.firstIndex(where: { $0.id == module }) else { return }
        let clamped = spec.clamp(value)
        modules[index].values[param] = clamped
        codec.setParameter(module, param: param, value: clamped)
        if profile.module(module)?.isGlobal ?? false {
            // 全局参数记在本机，重启 App 后保持。
            UserDefaults.standard.set(clamped, forKey: Self.globalKey(profile.id, module, param))
        }
        scheduleCapture()
    }

    private static func globalKey(_ profileID: DeviceProfileID, _ module: ModuleID, _ param: Int) -> String {
        "global.\(profileID).\(module).\(param)"
    }

    /// 界面上实际要显示的参数：只显示设备报告过 / 配置里定义过的。
    func visibleParams(_ module: ModuleID) -> [ParameterSpec] {
        guard let spec = profile.module(module) else { return [] }
        guard let state = moduleState(module), !state.values.isEmpty else { return spec.params }
        return spec.params.filter { state.values[$0.id] != nil }
    }

    private func setLocalModule(_ id: ModuleID, enabled: Bool) {
        guard let index = modules.firstIndex(where: { $0.id == id }) else { return }
        modules[index].enabled = enabled
    }

    private func setLocalParam(_ module: ModuleID, _ param: Int, _ value: Double) {
        guard let index = modules.firstIndex(where: { $0.id == module }) else { return }
        modules[index].values[param] = value
    }

    func tapTempo() {
        codec.tapTempo()
        log("Tap Tempo")
    }

    /// 鼓机播放/停止之类的瞬时 CC。
    func sendCC(_ number: Int, _ value: Int) {
        codec.sendControlChange(number, value: value)
    }

    func requestState() {
        codec.requestState()
    }

    func pushAll() {
        guard status.isConnected else { return }
        for module in modules {
            if profile.module(module.id)?.isGlobal ?? false { continue }
            if let moduleSpec = profile.module(module.id), moduleSpec.bypass.kind != .none {
                codec.setModule(module.id, enabled: module.enabled)
            }
            guard let spec = profile.module(module.id) else { continue }
            for p in spec.params {
                codec.setParameter(module.id, param: p.id,
                                   value: module.value(p.id, fallback: p.initialValue))
            }
        }
    }

    // MARK: - 事件

    private func handle(_ event: TransportEvent) {
        switch event {
        case .connected:
            status = .connected
        case .disconnected(let reason):
            if let reason { lastError = reason }
        case .stateLoaded(let snap):
            presetIndex = snap.presetIndex
            presetName = store.alias(profile.id, index: snap.presetIndex) ?? snap.name
            modules = Self.merge(snapshot: snap.modules, profile: profile)
            scheduleCapture()
            log("已读取音色：\(snap.name)")
        case .presetName(let name):
            presetName = store.alias(profile.id, index: presetIndex) ?? name
            scheduleCapture()
        case .presetIndex(let index):
            presetIndex = index
            store.setLastUsedPreset(index, for: profile.id)
        case .moduleChanged(let module, let enabled):
            setLocalModule(module, enabled: enabled)
            scheduleCapture()
        case .paramChanged(let module, let param, let value):
            setLocalParam(module, param, value)
            scheduleCapture()
        case .log(let message):
            log(message)
        case .error(let message):
            lastError = message
            log("错误：\(message)")
        }
    }

    private var captureWork: DispatchWorkItem?

    /// 拖动参数时不要每一帧都写盘：合并到停止操作 0.6 秒后再存。
    private func scheduleCapture() {
        guard store.data.settings.autoCapture else { return }
        captureWork?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.capture() }
        captureWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6, execute: work)
    }

    private func capture() {
        guard store.data.settings.autoCapture, status.isConnected else { return }
        // 全局模块不写进预设库，避免下次切回来时把音量改掉。
        let stored = modules.filter { !(profile.module($0.id)?.isGlobal ?? false) }
        store.save(modules: stored, name: presetName, index: presetIndex, for: profile.id)
    }

    private func log(_ message: String) {
        let stamp = Self.timeFormatter.string(from: Date())
        logLines.append("[\(stamp)] \(message)")
        if logLines.count > 300 { logLines.removeFirst(logLines.count - 300) }
    }

    private func recordTraffic(direction: String, data: Data) {
        // 只在设备调试页打开时记录，避免滑杆拖动时每包都触发界面刷新。
        guard Diagnostics.trafficEnabled else { return }
        let hex = data.map { String(format: "%02X", $0) }.joined(separator: " ")
        traffic.append("\(direction) \(hex)")
        if traffic.count > 200 { traffic.removeFirst(traffic.count - 200) }
    }

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss"
        return f
    }()

    private static func merge(snapshot: [ModuleState], profile: DeviceProfile) -> [ModuleState] {
        profile.modules.map { spec in
            guard let saved = snapshot.first(where: { $0.id == spec.id }) else {
                var values: [Int: Double] = [:]
                for p in spec.params { values[p.id] = p.initialValue }
                return ModuleState(id: spec.id, enabled: spec.defaultEnabled, values: values)
            }
            var values: [Int: Double] = [:]
            for p in spec.params {
                let raw = saved.value(p.id, fallback: p.initialValue)
                values[p.id] = p.clamp(raw)
            }
            return ModuleState(id: spec.id, enabled: saved.enabled, values: values)
        }
    }
}
