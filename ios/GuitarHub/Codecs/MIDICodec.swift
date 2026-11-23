import Foundation

/// 通用 MIDI CC / PC 编解码器。
///
/// 适用于所有"官方开放了 MIDI 实现"的设备（Hotone Pulze Mini 是典型：
/// 官方 MIDI 表只提供块开关、音量、换音色、鼓机/速度，没有逐个效果参数）。
/// 设备能力完全由 profile JSON 描述，新增同类设备不需要改代码。
final class MIDICodec: DeviceCodec {

    let profile: DeviceProfile
    var eventHandler: ((TransportEvent) -> Void)?

    private weak var session: BLESession?
    private let parser = MIDIStreamParser()
    private var channel: Int { profile.transport.midiChannel.clamped(to: 1...16) }
    private var lastProgram: Int = 0

    init(profile: DeviceProfile, session: BLESession) {
        self.profile = profile
        self.session = session
    }

    // MARK: - 生命周期

    func didConnect() {
        eventHandler?(.connected)
        eventHandler?(.log("已连接（\(profile.name)），使用 MIDI 通道 \(channel)"))
        eventHandler?(.log("该设备通过 MIDI 只暴露：块开关 / 音量 / 换音色 / 速度。参数级编辑需要用官方 App 或逆向其私有协议。"))
    }

    func didDisconnect() {
        eventHandler?(.disconnected(nil))
    }

    func didReceive(_ data: Data) {
        let bytes = profile.transport.kind == .bleMIDI ? BLEMIDI.decode(data) : [UInt8](data)
        for message in parser.feed(bytes) {
            handle(message)
        }
    }

    private func handle(_ message: MIDIMessage) {
        switch message.type {
        case 0xB0:
            let number = Int(message.data1)
            let value = Int(message.data2)
            if let module = profile.modules.first(where: { $0.bypass.kind == .cc && $0.bypass.cc == number }) {
                let on = value >= 64
                eventHandler?(.moduleChanged(module: module.id, enabled: on))
            }
            if let (module, param) = paramForCC(number) {
                let display = param.minValue + Double(value) / 127.0 * (param.maxValue - param.minValue)
                eventHandler?(.paramChanged(module: module.id, param: param.id, value: display))
            }
        case 0xC0:
            lastProgram = Int(message.data1)
            eventHandler?(.presetIndex(lastProgram))
        default:
            break
        }
    }

    // MARK: - 控制

    /// 让 App 的“当前音色号”归零（用户先把音箱手动调到组内第 1 个，再点同步）。
    func resetPresetCounter() {
        lastProgram = 0
        eventHandler?(.log("预设计数已归零"))
    }

    func selectPreset(_ index: Int) {
        let clamped = index.clamped(to: 0...127)

        // Pulze 这类设备：CC 只移动列表光标，用 PC 才真正加载音色。
        if profile.presets.useProgramChange == true {
            lastProgram = clamped
            sendProgramChange(clamped)
            eventHandler?(.log("→ PC #\(clamped + 1) 加载音色"))
            return
        }

        // 其他设备按手册用 CC 上/下一个。
        if let next = profile.presets.stepCCNext, let prev = profile.presets.stepCCPrev {
            var delta = clamped - lastProgram
            if delta > 64 { delta -= 128 }
            if delta < -64 { delta += 128 }
            let cc = delta >= 0 ? next : prev
            for _ in 0..<abs(delta) {
                sendCC(cc, 127)
            }
            lastProgram = clamped
            eventHandler?(.log("→ 换音色：CC \(cc) × \(abs(delta))，目标 #\(clamped + 1)"))
        } else {
            lastProgram = clamped
            sendProgramChange(clamped)
        }
    }

    func setModule(_ module: ModuleID, enabled: Bool) {
        guard let spec = profile.module(module), let cc = spec.bypass.cc else { return }
        sendCC(cc, enabled ? spec.bypass.onValue : spec.bypass.offValue)
    }

    func setParameter(_ module: ModuleID, param: Int, value: Double) {
        guard let spec = profile.parameter(module: module, param: param) else { return }

        // 14 位参数（BPM 之类）：MSB/LSB 两个 CC。
        if spec.mapping.kind == .ccPair,
           let msbCC = spec.mapping.cc,
           let lsbCC = spec.mapping.cc2 {
            let bpm = Int(value.rounded().clamped(to: 40...300))
            let msb: Int
            let lsb: Int
            if bpm < 128 {
                msb = 0
                lsb = bpm
            } else if bpm < 256 {
                msb = 1
                lsb = bpm - 128
            } else {
                msb = 2
                lsb = bpm - 256
            }
            sendCC(msbCC, msb)
            sendCC(lsbCC, lsb)
            return
        }

        guard let cc = spec.mapping.cc else { return }
        let span = spec.maxValue - spec.minValue
        let ratio = span > 0 ? (value - spec.minValue) / span : 0
        let midi = Int((ratio * 127).rounded()).clamped(to: 0...127)
        sendCC(cc, midi)
    }

    func tapTempo() {
        guard let cc = profile.transport.tapTempoCC else { return }
        sendCC(cc, 127)
    }

    func sendControlChange(_ number: Int, value: Int) {
        sendCC(number, value)
    }

    // MARK: - 发送

    private func sendCC(_ number: Int, _ value: Int) {
        guard let session else { return }
        let message = MIDIMessage.controlChange(channel: channel, number: number, value: value)
        session.send(BLEMIDI.encode(message.bytes))
        eventHandler?(.log("→ CC \(number) = \(value)"))
    }

    private func sendProgramChange(_ program: Int) {
        guard let session else { return }
        let message = MIDIMessage.programChange(channel: channel, program: program)
        session.send(BLEMIDI.encode(message.bytes))
        eventHandler?(.log("→ PC \(program)"))
    }

    private func paramForCC(_ cc: Int) -> (ModuleSpec, ParameterSpec)? {
        for module in profile.modules {
            if let param = module.params.first(where: { $0.mapping.kind == .cc && $0.mapping.cc == cc }) {
                return (module, param)
            }
        }
        return nil
    }
}
