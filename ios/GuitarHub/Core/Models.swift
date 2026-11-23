import Foundation

// MARK: - 基础标识

typealias DeviceProfileID = String
typealias ModuleID = String

/// 协议编解码器类型。新增设备时优先复用现有 codec + 配置；确实不行的才写新 codec。
enum CodecKind: String, Codable, CaseIterable, Identifiable {
    /// Positive Grid Spark 私有二进制协议（msgpack 变体 + 7bit 打包）。
    case spark
    /// 通用 MIDI CC / PC 协议（Hotone Pulze 及大多数支持 BLE MIDI 的效果器）。
    case midiCC
    /// 用户自定义十六进制命令模板（预留）。
    case template

    var id: String { rawValue }
    var label: String {
        switch self {
        case .spark:    return "Spark 私有协议"
        case .midiCC:   return "MIDI CC / PC"
        case .template: return "十六进制模板"
        }
    }
}

// MARK: - 宽容解码工具
//
// 设备配置是给人手写的，缺字段应该落回默认值，而不是整份 JSON 解析失败。

private extension KeyedDecodingContainer {
    func value<T: Decodable>(_ key: Key, default fallback: T) -> T {
        guard let decoded = try? decodeIfPresent(T.self, forKey: key) else { return fallback }
        return decoded ?? fallback
    }

    func optional<T: Decodable>(_ key: Key) -> T? {
        (try? decodeIfPresent(T.self, forKey: key)) ?? nil
    }
}

// MARK: - 设备描述（可由 JSON 定义）

struct DeviceProfile: Identifiable, Codable, Hashable {
    var id: DeviceProfileID
    var name: String
    var vendor: String = ""
    var note: String = ""
    var transport: Transport
    var capabilities: Capabilities = Capabilities()
    var modules: [ModuleSpec] = []
    var presets: PresetConfig = PresetConfig()

    struct Transport: Codable, Hashable {
        var kind: Kind = .ble
        var codec: CodecKind = .midiCC
        var namePrefixes: [String] = []
        var serviceUUIDs: [String] = []
        var writeCharacteristic: String = ""
        var notifyCharacteristic: String = ""
        var chunkSize: Int = 20
        var chunkIntervalMs: Int = 8
        var blockHeader: Bool = false
        var midiChannel: Int = 1
        var tapTempoCC: Int? = nil

        enum Kind: String, Codable, CaseIterable, Identifiable {
            case ble
            case bleMIDI
            case usbMIDI
            var id: String { rawValue }
            var label: String {
                switch self {
                case .ble:     return "蓝牙私有协议"
                case .bleMIDI: return "蓝牙 MIDI"
                case .usbMIDI: return "USB MIDI"
                }
            }
        }

        enum CodingKeys: String, CodingKey {
            case kind, codec, namePrefixes, serviceUUIDs, writeCharacteristic, notifyCharacteristic
            case chunkSize, chunkIntervalMs, blockHeader, midiChannel, tapTempoCC
        }

        init() {}

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            kind = c.value(.kind, default: .ble)
            codec = c.value(.codec, default: .midiCC)
            namePrefixes = c.value(.namePrefixes, default: [])
            serviceUUIDs = c.value(.serviceUUIDs, default: [])
            writeCharacteristic = c.value(.writeCharacteristic, default: "")
            notifyCharacteristic = c.value(.notifyCharacteristic, default: "")
            chunkSize = c.value(.chunkSize, default: 20)
            chunkIntervalMs = c.value(.chunkIntervalMs, default: 8)
            blockHeader = c.value(.blockHeader, default: false)
            midiChannel = c.value(.midiChannel, default: 1)
            tapTempoCC = c.optional(.tapTempoCC)
        }
    }

    struct Capabilities: Codable, Hashable {
        var stateReadback: Bool = false
        var presetNames: Bool = false
        var presetCount: Int = 4
        var tapTempo: Bool = false
        var savePreset: Bool = false

        enum CodingKeys: String, CodingKey {
            case stateReadback, presetNames, presetCount, tapTempo, savePreset
        }

        init() {}

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            stateReadback = c.value(.stateReadback, default: false)
            presetNames = c.value(.presetNames, default: false)
            presetCount = c.value(.presetCount, default: 4)
            tapTempo = c.value(.tapTempo, default: false)
            savePreset = c.value(.savePreset, default: false)
        }
    }

    struct PresetConfig: Codable, Hashable {
        var startNumber: Int = 0
        var wrap: Bool = true
        /// 有些设备不支持 PC 换音色，只认 CC“上一个/下一个”。
        var stepCCNext: Int? = nil
        var stepCCPrev: Int? = nil

        enum CodingKeys: String, CodingKey { case startNumber, wrap, stepCCNext, stepCCPrev }

        init() {}

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            startNumber = c.value(.startNumber, default: 0)
            wrap = c.value(.wrap, default: true)
            stepCCNext = c.optional(.stepCCNext)
            stepCCPrev = c.optional(.stepCCPrev)
        }
    }

    enum CodingKeys: String, CodingKey {
        case id, name, vendor, note, transport, capabilities, modules, presets
    }

    init(id: String, name: String, transport: Transport) {
        self.id = id
        self.name = name
        self.transport = transport
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = c.value(.id, default: "")
        name = c.value(.name, default: "")
        vendor = c.value(.vendor, default: "")
        note = c.value(.note, default: "")
        transport = c.value(.transport, default: Transport())
        capabilities = c.value(.capabilities, default: Capabilities())
        modules = c.value(.modules, default: [])
        presets = c.value(.presets, default: PresetConfig())
    }

    // MARK: 查询

    func module(_ id: ModuleID) -> ModuleSpec? {
        modules.first { $0.id == id }
    }

    func parameter(module: ModuleID, param: Int) -> ParameterSpec? {
        self.module(module)?.params.first { $0.id == param }
    }

    func moduleBySlot(_ slot: Int) -> ModuleSpec? {
        modules.first { $0.slot == slot }
    }

    var defaultModules: [ModuleState] {
        modules.map { spec in
            var values: [Int: Double] = [:]
            for p in spec.params { values[p.id] = p.initialValue }
            return ModuleState(id: spec.id, enabled: spec.defaultEnabled, values: values)
        }
    }

    /// 简单校验，避免一份坏 JSON 让 App 在运行时崩溃。
    func validate() -> [String] {
        var issues: [String] = []
        if id.isEmpty { issues.append("id 不能为空") }
        if name.isEmpty { issues.append("name 不能为空") }
        if modules.isEmpty { issues.append("modules 不能为空") }

        var seen = Set<String>()
        for m in modules {
            if !seen.insert(m.id).inserted {
                issues.append("模块 id 重复：\(m.id)")
            }
            if m.params.isEmpty && m.bypass.kind == .none && !m.isGlobal {
                issues.append("模块 \(m.id) 既没有参数也没有开关映射")
            }
            for p in m.params where p.mapping.kind == .cc && p.mapping.cc == nil {
                issues.append("模块 \(m.id) 参数 \(p.id) 缺少 cc")
            }
            for p in m.params where p.mapping.kind == .sparkParam && (p.mapping.slot == nil || p.mapping.param == nil) {
                issues.append("模块 \(m.id) 参数 \(p.id) 缺少 slot/param")
            }
        }
        return issues
    }
}

// MARK: - 模块 / 参数 / 映射

struct ModuleSpec: Identifiable, Codable, Hashable {
    var id: ModuleID
    var name: String
    /// 颜色块上的三字母代码，例如 AMP / FX1 / REV。
    var shortName: String = ""
    /// 颜色块颜色，#RRGGBB。
    var colorHex: String = ""
    /// 设备协议里的槽位号（Spark 的 pedal index 0…6）。
    var slot: Int? = nil
    var bypass: BypassMapping = BypassMapping()
    var params: [ParameterSpec] = []
    var defaultEnabled: Bool = true
    /// 全局模块（音量、速度等），不参与"开关"语义。
    var isGlobal: Bool = false

    var badge: String {
        if !shortName.isEmpty { return shortName.uppercased() }
        return String(id.prefix(3)).uppercased()
    }

    enum CodingKeys: String, CodingKey {
        case id, name, shortName, colorHex, slot, bypass, params, defaultEnabled, isGlobal
    }

    init(id: ModuleID, name: String) {
        self.id = id
        self.name = name
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = c.value(.id, default: "")
        name = c.value(.name, default: "")
        shortName = c.value(.shortName, default: "")
        colorHex = c.value(.colorHex, default: "")
        slot = c.optional(.slot)
        bypass = c.value(.bypass, default: BypassMapping())
        params = c.value(.params, default: [])
        defaultEnabled = c.value(.defaultEnabled, default: true)
        isGlobal = c.value(.isGlobal, default: false)
    }
}

struct BypassMapping: Codable, Hashable {
    var kind: Kind = .none
    var cc: Int? = nil
    var onValue: Int = 127
    var offValue: Int = 0
    var slot: Int? = nil

    enum Kind: String, Codable, CaseIterable, Identifiable {
        case none
        case cc
        case sparkSlot
        var id: String { rawValue }
        var label: String {
            switch self {
            case .none:      return "不可开关"
            case .cc:        return "MIDI CC"
            case .sparkSlot: return "Spark 槽位"
            }
        }
    }

    enum CodingKeys: String, CodingKey { case kind, cc, onValue, offValue, slot }

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        kind = c.value(.kind, default: .none)
        cc = c.optional(.cc)
        onValue = c.value(.onValue, default: 127)
        offValue = c.value(.offValue, default: 0)
        slot = c.optional(.slot)
    }
}

struct ParameterSpec: Identifiable, Codable, Hashable {
    var id: Int
    var name: String
    var minValue: Double = 0
    var maxValue: Double = 100
    var unit: String = ""
    var step: Double = 1
    /// 双极性参数（EQ 的 -50…+50）在界面上从中间向两边显示。
    var bipolar: Bool = false
    var mapping: ParamMapping = ParamMapping()
    var defaultValue: Double? = nil

    var initialValue: Double {
        defaultValue ?? (bipolar ? (minValue + maxValue) / 2 : minValue)
    }

    func clamp(_ value: Double) -> Double {
        min(max(value, minValue), maxValue)
    }

    enum CodingKeys: String, CodingKey {
        case id, name, minValue, maxValue, unit, step, bipolar, mapping, defaultValue
    }

    init(id: Int, name: String, minValue: Double = 0, maxValue: Double = 100) {
        self.id = id
        self.name = name
        self.minValue = minValue
        self.maxValue = maxValue
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let decodedID = c.value(.id, default: 0)
        id = decodedID
        name = c.value(.name, default: "参数 \(decodedID)")
        minValue = c.value(.minValue, default: 0)
        maxValue = c.value(.maxValue, default: 100)
        unit = c.value(.unit, default: "")
        step = c.value(.step, default: 1)
        bipolar = c.value(.bipolar, default: false)
        mapping = c.value(.mapping, default: ParamMapping())
        defaultValue = c.optional(.defaultValue)
    }
}

struct ParamMapping: Codable, Hashable {
    var kind: Kind = .readOnly
    var cc: Int? = nil
    var cc2: Int? = nil
    var ccMin: Int = 0
    var ccMax: Int = 127
    var slot: Int? = nil
    var param: Int? = nil

    enum Kind: String, Codable, CaseIterable, Identifiable {
        case readOnly
        case cc
        /// 14 位参数（如 BPM）：cc 是 MSB，cc2 是 LSB。
        case ccPair
        case sparkParam
        var id: String { rawValue }
        var label: String {
            switch self {
            case .readOnly:   return "只读"
            case .cc:         return "MIDI CC"
            case .ccPair:     return "MIDI CC（双字节）"
            case .sparkParam: return "Spark 参数"
            }
        }
    }

    enum CodingKeys: String, CodingKey { case kind, cc, cc2, ccMin, ccMax, slot, param }

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        kind = c.value(.kind, default: .readOnly)
        cc = c.optional(.cc)
        cc2 = c.optional(.cc2)
        ccMin = c.value(.ccMin, default: 0)
        ccMax = c.value(.ccMax, default: 127)
        slot = c.optional(.slot)
        param = c.optional(.param)
    }
}

// MARK: - 运行状态

struct ModuleState: Identifiable, Hashable, Codable {
    var id: ModuleID
    var enabled: Bool
    var values: [Int: Double]

    func value(_ param: Int, fallback: Double = 0) -> Double {
        values[param] ?? fallback
    }
}

struct AmpSnapshot: Identifiable, Hashable, Codable {
    var presetIndex: Int
    var name: String
    var modules: [ModuleState]
    var updatedAt: Date

    var id: Int { presetIndex }

    func module(_ id: ModuleID) -> ModuleState? {
        modules.first { $0.id == id }
    }
}

enum ConnectionStatus: Equatable {
    case disconnected
    case scanning
    case connecting
    case connected
    case failed(String)

    var label: String {
        switch self {
        case .disconnected:  return "未连接"
        case .scanning:      return "搜索中…"
        case .connecting:    return "连接中…"
        case .connected:     return "已连接"
        case .failed(let m): return "失败：\(m)"
        }
    }

    var isConnected: Bool {
        if case .connected = self { return true }
        return false
    }

    var isBusy: Bool {
        switch self {
        case .scanning, .connecting: return true
        default: return false
        }
    }
}

// MARK: - BLE 扫描结果

struct DiscoveredDevice: Identifiable, Hashable {
    var id: UUID
    var name: String
    var rssi: Int
    var serviceSummary: String = ""
}

// MARK: - 编解码器事件

enum TransportEvent {
    case connected
    case disconnected(String?)
    case stateLoaded(AmpSnapshot)
    case presetName(String)
    case presetIndex(Int)
    case moduleChanged(module: ModuleID, enabled: Bool)
    case paramChanged(module: ModuleID, param: Int, value: Double)
    case log(String)
    case error(String)
}

// MARK: - 编解码器协议
//
// 每个 codec 负责把设备私有协议翻译成统一语义。数值统一用 App 的显示单位
// （一般 0…100），由 codec 换算成设备单位（Spark 0…1、MIDI 0…127 等）。

protocol DeviceCodec: AnyObject {
    var profile: DeviceProfile { get }
    var eventHandler: ((TransportEvent) -> Void)? { get set }

    func didConnect()
    func didDisconnect()
    func didReceive(_ data: Data)

    func requestState()
    func selectPreset(_ index: Int)
    func setModule(_ module: ModuleID, enabled: Bool)
    func setParameter(_ module: ModuleID, param: Int, value: Double)
    func tapTempo()
    /// 直接发一个 CC（鼓机播放/停止这类瞬时命令用）。
    func sendControlChange(_ number: Int, value: Int)
}

extension DeviceCodec {
    func requestState() {}
    func tapTempo() {}
    func sendControlChange(_ number: Int, value: Int) {}
}

// MARK: - App 入口模式

/// 启动页直接选设备，同一时刻只连一台。
enum AppMode: String {
    case launch
    case guitar
}

enum BankNames {
    static let spark = "Spark Mini"
    static let pulze = "Pulze Mini"
}

// MARK: - 工具

enum ValueScale {
    static func toMIDI(_ value: Double, min: Double = 0, max: Double = 100) -> Int {
        guard max > min else { return 0 }
        let ratio = (value - min) / (max - min)
        return Int((ratio * 127.0).rounded().clamped(to: 0...127))
    }

    static func fromMIDI(_ value: Int) -> Double {
        Double(value.clamped(to: 0...127)) / 127.0 * 100.0
    }
}

extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self {
        min(max(self, range.lowerBound), range.upperBound)
    }
}
