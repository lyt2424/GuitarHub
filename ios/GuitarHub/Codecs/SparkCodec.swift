import Foundation

/// Spark Mini / 40 / GO 的控制编解码器。
///
/// 命令字（App → 音箱，均以 0x01 开头）：
///   0x0115  模块开关      前缀字符串(模块名) + 0xC3/0xC2
///   0x0104  参数修改      前缀字符串(模块名) + 参数号 + 浮点(0…1)
///   0x0138  切换硬件预设  当前预设号 + 目标预设号
///   0x0163  Tap Tempo     （待实机验证）
/// 请求（0x02 开头）：
///   0x0201  读取预设      预设号高/低字节 + 30 个 0；0x0100 表示"当前状态"
///   0x0210  当前硬件预设号
///   0x0211  音箱名
///   0x0223  序列号
///   0x022f  固件版本
final class SparkCodec: DeviceCodec {

    let profile: DeviceProfile
    var eventHandler: ((TransportEvent) -> Void)?

    private weak var session: BLESession?
    private let decoder = SparkProtocol.Decoder()
    private var sequence: UInt8 = 0
    private var preset: SparkPreset?
    private var pendingParams: [String: Double] = [:]
    private var receivedAny = false
    private var usedBlockHeader = false
    private var pendingParamValues: [String: Double] = [:]
    private var pendingParamWork: [String: DispatchWorkItem] = [:]
    /// 主动读取某个预设时记下目标号；回包里的 curr 可能是旧值，不能拿来当显示号。
    private var expectedPresetIndex: Int?
    private var presetRetryCount = 0
    /// App 主动切档的目标；只对 App 发起的切档做失败补发，硬件旋钮不碰。
    private var pendingAppSwitch: Int?
    private var appSwitchRetryCount = 0

    init(profile: DeviceProfile, session: BLESession) {
        self.profile = profile
        self.session = session
    }

    // MARK: - 生命周期

    func didConnect() {
        eventHandler?(.connected)
        eventHandler?(.log("Spark 已连接，读取音箱信息与当前音色…"))
        requestName()
        requestPresetNumber()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
            self?.requestState()
        }
        // Spark 40 需要 16 字节块头，Mini/GO 可能不需要。
        // 先不带块头；1.2 秒内没有任何回包就带块头重试一次。
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { [weak self] in
            guard let self, !self.receivedAny else { return }
            self.usedBlockHeader = true
            self.eventHandler?(.log("没有收到回包，改用带块头再试一次"))
            self.requestState(blockHeader: true)
        }
    }

    func didDisconnect() {
        eventHandler?(.disconnected(nil))
    }

    // MARK: - 接收

    func didReceive(_ data: Data) {
        let messages = decoder.feed([UInt8](data))
        if !messages.isEmpty { receivedAny = true }
        for message in messages {
            handle(message)
        }
    }

    private func handle(_ message: SparkProtocol.Message) {
        switch message.cmdSub {
        case 0x0101, 0x0301:
            guard let parsed = SparkPresetParser.parse(message.payload) else {
                eventHandler?(.log("预设解析失败（\(message.payload.count) 字节）"))
                return
            }
            apply(parsed)

        case 0x0311:
            var reader = SparkPayloadReader(message.payload)
            let name = reader.string()
            if !name.isEmpty {
                preset?.name = name
                eventHandler?(.presetName(name))
            }

        // Spark MINI 的 0x0310 回报恒为 0，不能拿来当当前预设号，交给 0x0301 的 curr 字段。

        case 0x0115, 0x0315:
            handleOnOff(message.payload)

        case 0x0104, 0x0337:
            handleParameter(message.payload)

        case 0x0138:
            // App 发起的切档：载荷是 [旧档, 新档]。
            guard message.payload.count >= 2 else { return }
            let index = Int(message.payload[1])
            preset?.currentPreset = index
            preset?.presetNumber = index
            eventHandler?(.presetIndex(index))
            eventHandler?(.log("音箱切到预设 \(index + 1)"))
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [weak self] in
                self?.requestPreset(index)
            }

        case 0x0338:
            // 音箱硬件旋钮主动上报：载荷是 [旧档, 新档]，第二个字节才是新档。
            guard message.payload.count >= 2 else { return }
            pendingAppSwitch = nil
            let index = Int(message.payload[1])
            preset?.currentPreset = index
            preset?.presetNumber = index
            eventHandler?(.presetIndex(index))
            eventHandler?(.log("硬件旋钮切到预设 \(index + 1)"))
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [weak self] in
                self?.requestPreset(index)
            }

        case 0x0363:
            var reader = SparkPayloadReader(message.payload)
            let bpm = reader.float(expected: 20...400)
            eventHandler?(.log("Tap Tempo：\(Int(bpm)) BPM"))

        default:
            let hex = message.payload.prefix(16).map { String(format: "%02X", $0) }.joined(separator: " ")
            eventHandler?(.log("未处理消息 \(String(format: "%04X", message.cmdSub)) [\(hex)]"))
        }
    }

    private func handleOnOff(_ payload: [UInt8]) {
        var reader = SparkPayloadReader(payload)
        let pedalName = reader.string()
        let on = reader.byte() == 0xC3
        guard let moduleSpec = self.module(forPedalName: pedalName) else { return }
        if let slot = moduleSpec.slot, slot < (preset?.pedals.count ?? 0) {
            var pedals = preset?.pedals ?? []
            pedals[slot].enabled = on
            preset?.pedals = pedals
        }
        eventHandler?(.moduleChanged(module: moduleSpec.id, enabled: on))
    }

    private func handleParameter(_ payload: [UInt8]) {
        var reader = SparkPayloadReader(payload)
        let pedalName = reader.string()
        guard let paramIndex = reader.byte() else { return }
        let value = reader.float(expected: 0...1)
        guard let moduleSpec = self.module(forPedalName: pedalName) else { return }
        var display = Double(value) * 100
        if let spec = moduleSpec.params.first(where: { $0.mapping.param == Int(paramIndex) }) {
            let ratio = Double(value)
            display = spec.minValue + ratio * (spec.maxValue - spec.minValue)
        }
        if let slot = moduleSpec.slot, slot < (preset?.pedals.count ?? 0) {
            var pedals = preset?.pedals ?? []
            if Int(paramIndex) < pedals[slot].params.count {
                pedals[slot].params[Int(paramIndex)] = value
                preset?.pedals = pedals
            }
        }
        eventHandler?(.paramChanged(module: moduleSpec.id, param: Int(paramIndex), value: display))
    }

    private func apply(_ parsed: SparkPreset) {
        // 空包（踏板数 0、名字空）通常是切换过程中的半包，不能拿来覆盖界面。
        guard !parsed.pedals.isEmpty, !parsed.name.isEmpty else {
            eventHandler?(.log("忽略空预设回报（踏板 \(parsed.pedals.count) 个）"))
            return
        }
        preset = parsed
        eventHandler?(.log("预设回报 curr=\(parsed.currentPreset) num=\(parsed.presetNumber) name=「\(parsed.name)」踏板=\(parsed.pedals.count)"))
        // 优先用“我们请求的那个号”，避免回包里的旧 curr 把界面带偏。
        // 主动读取某档时，回包就是那档的内容；不要把回包里可能滞后的 curr 当成显示号。
        let rawIndex = expectedPresetIndex
            ?? (parsed.currentPreset < profile.capabilities.presetCount
                ? parsed.currentPreset
                : parsed.presetNumber)
        if let expected = expectedPresetIndex {
            preset?.currentPreset = expected
        } else if parsed.currentPreset < profile.capabilities.presetCount {
            preset?.currentPreset = parsed.currentPreset
        }

        // App 发起的切档：回报的当前档不是目标，说明命令被丢了，补发一次。
        if let pending = pendingAppSwitch, pending != parsed.currentPreset {
            eventHandler?(.log("App 切档未生效：目标 \(pending + 1)，实际 \(parsed.currentPreset + 1)"))
            if appSwitchRetryCount < 1 {
                appSwitchRetryCount += 1
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in
                    self?.selectPreset(pending)
                }
            }
            expectedPresetIndex = nil
            return
        }
        if pendingAppSwitch == parsed.currentPreset {
            pendingAppSwitch = nil
            appSwitchRetryCount = 0
        }
        expectedPresetIndex = nil
        let index = min(max(0, rawIndex), max(0, profile.capabilities.presetCount - 1))
        var modules: [ModuleState] = []

        for spec in profile.modules {
            guard let slot = spec.slot else {
                // 全局模块（Spark 没有），保留默认值
                var values: [Int: Double] = [:]
                for p in spec.params { values[p.id] = p.initialValue }
                modules.append(ModuleState(id: spec.id, enabled: spec.defaultEnabled, values: values))
                continue
            }
            guard slot < parsed.pedals.count else { continue }
            let pedal = parsed.pedals[slot]
            var values: [Int: Double] = [:]
            for p in spec.params {
                guard let paramIndex = p.mapping.param, paramIndex < pedal.params.count else { continue }
                let ratio = Double(pedal.params[paramIndex])
                values[p.id] = p.minValue + ratio * (p.maxValue - p.minValue)
            }
            modules.append(ModuleState(id: spec.id, enabled: pedal.enabled, values: values))
        }

        let displayName = parsed.name.isEmpty ? "音色 \(index + 1)" : parsed.name
        let snapshot = AmpSnapshot(presetIndex: index, name: displayName, modules: modules, updatedAt: Date())
        eventHandler?(.stateLoaded(snapshot))
        eventHandler?(.presetIndex(index))

        for (i, pedal) in parsed.pedals.enumerated() {
            eventHandler?(.log("槽位 \(i)：\(pedal.name) \(pedal.enabled ? "开" : "关")，参数 \(pedal.params.count) 个"))
        }
    }

    // MARK: - 发送

    func requestState(blockHeader: Bool = false) {
        // 读“当前状态”时不要带目标预设号，回包里的 curr 才是真实档位。
        expectedPresetIndex = nil
        // 0x0201 + 0x0100 + 30 个 0 → 音箱回传当前音色
        var payload: [UInt8] = [0x01, 0x00]
        payload.append(contentsOf: [UInt8](repeating: 0, count: 30))
        send(cmd: 0x02, sub: 0x01, payload: payload, blockHeader: blockHeader)
    }

    /// 读取指定硬件预设的完整状态（切档后用它，不能只读“当前状态”）。
    func requestPreset(_ index: Int) {
        let target = min(max(0, index), max(0, profile.capabilities.presetCount - 1))
        expectedPresetIndex = target
        presetRetryCount = 0
        var payload: [UInt8] = [0x00, UInt8(clamping: target)]
        payload.append(contentsOf: [UInt8](repeating: 0, count: 30))
        eventHandler?(.log("读取预设 \(target + 1) 的状态"))
        send(cmd: 0x02, sub: 0x01, payload: payload)
    }

    func requestName() {
        send(cmd: 0x02, sub: 0x11, payload: [])
    }

    func requestPresetNumber() {
        send(cmd: 0x02, sub: 0x10, payload: [])
    }

    func requestSerial() {
        send(cmd: 0x02, sub: 0x23, payload: [])
    }

    func requestFirmware() {
        send(cmd: 0x02, sub: 0x2F, payload: [])
    }

    func selectPreset(_ index: Int) {
        let maxIndex = max(0, profile.capabilities.presetCount - 1)
        let target = min(max(0, index), maxIndex)
        // Spark 的切档命令第一个字节固定为 0，不是“当前预设号”。
        // 传当前号会让音箱直接忽略命令（从第 1 档以外开始尤其明显）。
        send(cmd: 0x01, sub: 0x38, payload: [0x00, UInt8(target & 0xFF)])
        pendingAppSwitch = target
        appSwitchRetryCount = 0
    }

    func setModule(_ module: ModuleID, enabled: Bool) {
        guard let spec = profile.module(module), let slot = spec.slot else { return }
        guard let name = pedalName(slot: slot) else {
            eventHandler?(.log("未知模块名，无法切换 \(module)"))
            return
        }
        var payload = Self.prefixedString(name)
        payload.append(enabled ? 0xC3 : 0xC2)
        send(cmd: 0x01, sub: 0x15, payload: payload)
    }

    func setParameter(_ module: ModuleID, param: Int, value: Double) {
        // 拖动滑杆时每帧都发会把 BLE 队列打满，这里按 50ms 合并，只发最后一次的值。
        let key = "\(module)-\(param)"
        pendingParamValues[key] = value
        pendingParamWork[key]?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self, let latest = self.pendingParamValues.removeValue(forKey: key) else { return }
            self.sendParameterNow(module, param: param, value: latest)
        }
        pendingParamWork[key] = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05, execute: work)
    }

    private func sendParameterNow(_ module: ModuleID, param: Int, value: Double) {
        guard let spec = profile.parameter(module: module, param: param),
              spec.mapping.kind == .sparkParam,
              let pedalIndex = spec.mapping.slot,
              let paramIndex = spec.mapping.param else { return }
        guard let name = pedalName(slot: pedalIndex) else { return }
        let span = spec.maxValue - spec.minValue
        let ratio = span > 0 ? (value - spec.minValue) / span : 0
        var payload = Self.prefixedString(name)
        payload.append(UInt8(clamping: paramIndex))
        payload.append(contentsOf: Self.floatBytes(Float(ratio)))
        send(cmd: 0x01, sub: 0x04, payload: payload)
    }

    func tapTempo() {
        send(cmd: 0x01, sub: 0x63, payload: [])
    }

    private func send(cmd: UInt8, sub: UInt8, payload: [UInt8], blockHeader: Bool = false) {
        sequence = sequence &+ 1
        var frame = SparkProtocol.frame(cmd: cmd, sub: sub, payload: payload, sequence: sequence)
        if blockHeader {
            frame = SparkProtocol.blockHeader + frame
        }
        let chunkSize = profile.transport.chunkSize > 0 ? profile.transport.chunkSize : 20
        // Spark 对写入节奏比较敏感，12ms 比 8ms 稳。
        let interval = max(0.012, Double(profile.transport.chunkIntervalMs) / 1000.0)
        session?.sendChunked(Data(frame), chunkSize: chunkSize, interval: interval)
        // 参数命令每秒会发很多条，不逐条写日志，否则 UI 会跟着卡。
        if !(cmd == 0x01 && sub == 0x04) {
            let hex = frame.prefix(24).map { String(format: "%02X", $0) }.joined(separator: " ")
            eventHandler?(.log("→ \(String(format: "%02X%02X", cmd, sub)) \(hex)\(frame.count > 24 ? " …" : "")"))
        }
    }

    // MARK: - 辅助

    private func pedalName(slot: Int) -> String? {
        if let preset, slot < preset.pedals.count {
            let name = preset.pedals[slot].name
            if !name.isEmpty { return name }
        }
        guard slot >= 0, slot < Self.fallbackPedalNames.count else { return nil }
        return Self.fallbackPedalNames[slot]
    }

    private func module(forPedalName name: String) -> ModuleSpec? {
        guard let preset else { return nil }
        guard let slot = preset.pedals.firstIndex(where: { $0.name == name }) else { return nil }
        return profile.moduleBySlot(slot)
    }

    static func prefixedString(_ string: String) -> [UInt8] {
        let bytes = Array(string.utf8.prefix(31))
        return [UInt8(bytes.count), UInt8(0xA0 + bytes.count)] + bytes
    }

    static func floatBytes(_ value: Float) -> [UInt8] {
        let bits = value.bitPattern
        return [0xCA,
                UInt8((bits >> 24) & 0xFF),
                UInt8((bits >> 16) & 0xFF),
                UInt8((bits >> 8) & 0xFF),
                UInt8(bits & 0xFF)]
    }

    /// 读不到预设时的兜底模块名（大多数 Spark 音色通用）。
    static let fallbackPedalNames: [String] = [
        "bias.noisegate",
        "LA2AComp",
        "Booster",
        "Twin",
        "Cloner",
        "VintageDelay",
        "bias.reverb"
    ]
}
