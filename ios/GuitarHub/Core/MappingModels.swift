import Foundation

// MARK: - KORG Module 音色表
//
// Module 通过 Program Change 按 Set List 顺序切换音色，App 维护"槽位表"：
// 第 n 个槽位 = 发送 PC n + 一个用户填写的显示名。

struct KorgSlot: Codable, Identifiable, Hashable {
    var id: UUID = UUID()
    var program: Int
    var name: String
    var memo: String = ""
}

struct KorgSetlist: Codable, Identifiable, Hashable {
    var id: UUID = UUID()
    var name: String
    /// 1…16
    var midiChannel: Int = 1
    var slots: [KorgSlot] = []

    static func starter() -> KorgSetlist {
        KorgSetlist(
            name: "默认音色表",
            midiChannel: 1,
            slots: (0..<12).map { i in
                KorgSlot(program: i, name: "音色 \(i + 1)", memo: "")
            }
        )
    }

    func slot(program: Int) -> KorgSlot? {
        slots.first { $0.program == program }
    }
}

// MARK: - 踏板映射

enum PedalTrigger: Codable, Hashable {
    /// 踩下时 CC 值 ≥ 64 触发一次。
    case cc(number: Int)
    /// 表情踏板：持续跟随 CC 值。
    case expression(number: Int)
    case note(number: Int)
    case pc(number: Int)

    var label: String {
        switch self {
        case .cc(let n):         return "CC \(n)"
        case .expression(let n): return "CC \(n)（表情）"
        case .note(let n):       return "Note \(n)"
        case .pc(let n):         return "PC \(n)"
        }
    }
}

enum PedalAction: Codable, Hashable {
    case none
    /// 切换某个模块的开关（混响 / 延迟 / 均衡…）
    case ampModule(device: DeviceProfileID, module: ModuleID)
    /// 上一个 / 下一个音色
    case ampPresetStep(device: DeviceProfileID, delta: Int)
    /// 直接跳到一个音色
    case ampPreset(device: DeviceProfileID, index: Int)
    case ampTapTempo(device: DeviceProfileID)
    /// 表情踏板跟随某个参数
    case ampParamFollow(device: DeviceProfileID, module: ModuleID, param: Int)

    case korgProgram(program: Int)
    case korgStep(delta: Int)
    case korgSetlistNext

    case bankStep(delta: Int)

    var label: String {
        switch self {
        case .none:
            return "无动作"
        case .ampModule(let d, let m):
            return "\(d) · 切换 \(m)"
        case .ampPresetStep(let d, let delta):
            return "\(d) · \(delta > 0 ? "下一音色" : "上一音色")"
        case .ampPreset(let d, let index):
            return "\(d) · 音色 \(index + 1)"
        case .ampTapTempo(let d):
            return "\(d) · Tap Tempo"
        case .ampParamFollow(let d, let m, let p):
            return "\(d) · \(m) 参数 \(p)"
        case .korgProgram(let p):
            return "Module · 音色 \(p + 1)"
        case .korgStep(let delta):
            return "Module · \(delta > 0 ? "下一音色" : "上一音色")"
        case .korgSetlistNext:
            return "Module · 下一音色表"
        case .bankStep(let delta):
            return "踏板 · \(delta > 0 ? "下一组" : "上一组")"
        }
    }
}

struct PedalMapping: Codable, Identifiable, Hashable {
    var id: UUID = UUID()
    var trigger: PedalTrigger
    var action: PedalAction
    var enabled: Bool = true
    /// 自定义显示名，空则用 action 的描述。
    var title: String = ""

    var displayTitle: String {
        title.isEmpty ? action.label : title
    }
}

struct PedalBank: Codable, Identifiable, Hashable {
    var id: UUID = UUID()
    var name: String
    var mappings: [PedalMapping] = []

    /// 三套默认踏板组，名字与设备配置名 / 键盘模式对应，切换入口时自动选中。
    static func sparkStarter() -> PedalBank {
        ampStarter(device: "spark-mini", name: "Spark Mini")
    }

    static func pulzeStarter() -> PedalBank {
        PedalBank(
            name: "Pulze Mini",
            mappings: [
                PedalMapping(trigger: .cc(number: 20), action: .ampModule(device: "pulze-mini", module: "eq")),
                PedalMapping(trigger: .cc(number: 21), action: .ampModule(device: "pulze-mini", module: "fx1")),
                PedalMapping(trigger: .cc(number: 22), action: .ampModule(device: "pulze-mini", module: "fx2")),
                PedalMapping(trigger: .cc(number: 23), action: .ampPresetStep(device: "pulze-mini", delta: 1)),
                PedalMapping(trigger: .expression(number: 12), action: .ampParamFollow(device: "pulze-mini", module: "volume", param: 0))
            ]
        )
    }

    static func korgStarter() -> PedalBank {
        PedalBank(
            name: BankNames.keyboard,
            mappings: [
                PedalMapping(trigger: .cc(number: 20), action: .korgStep(delta: 1)),
                PedalMapping(trigger: .cc(number: 21), action: .korgStep(delta: -1)),
                PedalMapping(trigger: .cc(number: 22), action: .korgSetlistNext),
                PedalMapping(trigger: .cc(number: 23), action: .korgProgram(program: 0))
            ]
        )
    }

    static func starter(device: DeviceProfileID) -> PedalBank {
        ampStarter(device: device, name: "A 组")
    }

    static func ampStarter(device: DeviceProfileID, name: String) -> PedalBank {
        PedalBank(
            name: name,
            mappings: [
                PedalMapping(trigger: .cc(number: 20), action: .ampModule(device: device, module: "reverb")),
                PedalMapping(trigger: .cc(number: 21), action: .ampModule(device: device, module: "delay")),
                PedalMapping(trigger: .cc(number: 22), action: .ampPresetStep(device: device, delta: 1)),
                PedalMapping(trigger: .cc(number: 23), action: .ampPresetStep(device: device, delta: -1)),
                PedalMapping(trigger: .cc(number: 24), action: .korgStep(delta: 1)),
                PedalMapping(trigger: .cc(number: 25), action: .korgStep(delta: -1)),
                PedalMapping(trigger: .expression(number: 12), action: .ampParamFollow(device: device, module: "reverb", param: 0))
            ]
        )
    }
}

// MARK: - MIDI 基础类型

struct MIDIMessage: Equatable, Hashable {
    var status: UInt8
    var data1: UInt8
    var data2: UInt8

    var type: UInt8 { status & 0xF0 }
    /// 1…16
    var channel: Int { Int(status & 0x0F) + 1 }

    static func controlChange(channel: Int, number: Int, value: Int) -> MIDIMessage {
        MIDIMessage(status: 0xB0 | UInt8((channel - 1) & 0x0F),
                    data1: UInt8(clamping: number),
                    data2: UInt8(clamping: value))
    }

    static func programChange(channel: Int, program: Int) -> MIDIMessage {
        MIDIMessage(status: 0xC0 | UInt8((channel - 1) & 0x0F),
                    data1: UInt8(clamping: program),
                    data2: 0)
    }

    static func noteOn(channel: Int, note: Int, velocity: Int) -> MIDIMessage {
        MIDIMessage(status: 0x90 | UInt8((channel - 1) & 0x0F),
                    data1: UInt8(clamping: note),
                    data2: UInt8(clamping: velocity))
    }

    var bytes: [UInt8] {
        switch type {
        case 0xC0, 0xD0: return [status, data1]
        default:         return [status, data1, data2]
        }
    }
}

/// 处理 running status、SysEx 与实时字节的流式 MIDI 解析器。
final class MIDIStreamParser {
    private var runningStatus: UInt8 = 0
    private var pending: [UInt8] = []
    private var inSysEx = false

    func reset() {
        runningStatus = 0
        pending.removeAll()
        inSysEx = false
    }

    func feed(_ bytes: [UInt8]) -> [MIDIMessage] {
        var out: [MIDIMessage] = []
        for byte in bytes {
            if byte >= 0xF8 { continue }   // 实时消息不参与解析

            if inSysEx {
                if byte == 0xF7 { inSysEx = false }
                continue
            }
            if byte == 0xF0 { inSysEx = true; continue }

            if byte >= 0x80 {
                runningStatus = byte
                pending.removeAll()
                if byte >= 0xF0 { runningStatus = 0 }
                continue
            }

            guard runningStatus != 0 else { continue }
            pending.append(byte)

            let expected: Int
            switch runningStatus & 0xF0 {
            case 0xC0, 0xD0: expected = 1
            default:         expected = 2
            }

            if pending.count == expected {
                out.append(MIDIMessage(status: runningStatus, data1: pending[0],
                                       data2: expected == 2 ? pending[1] : 0))
                pending.removeAll()
            }
        }
        return out
    }
}
