import Foundation
import Combine

/// 把踏板（BLE MIDI 或系统 MIDI）的 CC / Note / PC 映射成对音箱、KORG Module 的操作。
final class PedalRouter: ObservableObject {

    @Published var lastEvent: String = "等待踏板…"
    @Published private(set) var pressCount: Int = 0
    @Published private(set) var logLines: [String] = []

    var onFeedback: ((String) -> Void)?

    private let store: AppStore
    private let korg: KorgController
    private var devices: [DeviceProfileID: AmpDevice] = [:]
    private var activeDeviceID: DeviceProfileID?
    private var keyboardMode = false
    private var drumPlaying: [DeviceProfileID: Bool] = [:]

    init(store: AppStore, korg: KorgController) {
        self.store = store
        self.korg = korg
    }

    func attach(devices: [AmpDevice]) {
        self.devices = Dictionary(uniqueKeysWithValues: devices.map { ($0.profile.id, $0) })
    }

    /// 进入某个入口后，只让当前模式相关的映射生效。
    func setActive(deviceID: DeviceProfileID?, keyboard: Bool) {
        self.activeDeviceID = deviceID
        self.keyboardMode = keyboard
    }

    // MARK: - 入口

    func handle(_ message: MIDIMessage, source: String) {
        guard let bank = store.activeBank else { return }
        for mapping in bank.mappings where mapping.enabled {
            guard matches(mapping.trigger, message) else { continue }
            let continuous = isContinuous(mapping.trigger)
            perform(mapping.action, value: continuous ? Int(message.data2) : 127)
            pressCount += 1
            let text = "\(source) · \(mapping.trigger.label) → \(mapping.displayTitle)"
            lastEvent = text
            onFeedback?(text)
            log(text)
            return
        }
    }

    private func isContinuous(_ trigger: PedalTrigger) -> Bool {
        if case .expression = trigger { return true }
        return false
    }

    private func matches(_ trigger: PedalTrigger, _ message: MIDIMessage) -> Bool {
        switch trigger {
        case .cc(let number):
            return message.type == 0xB0 && Int(message.data1) == number && message.data2 >= 64
        case .expression(let number):
            return message.type == 0xB0 && Int(message.data1) == number
        case .note(let number):
            return message.type == 0x90 && Int(message.data1) == number && message.data2 > 0
        case .pc(let number):
            return message.type == 0xC0 && Int(message.data1) == number
        }
    }

    // MARK: - 执行

    private func perform(_ action: PedalAction, value: Int) {
        switch action {
        case .none:
            break

        case .ampModule(let device, let module):
            guard isActive(device) else { return skip(device) }
            devices[device]?.toggleModule(module)

        case .ampPresetStep(let device, let delta):
            guard isActive(device) else { return skip(device) }
            devices[device]?.stepPreset(delta)

        case .ampPreset(let device, let index):
            guard isActive(device) else { return skip(device) }
            devices[device]?.selectPreset(index)

        case .ampTapTempo(let device):
            guard isActive(device) else { return skip(device) }
            devices[device]?.tapTempo()

        case .ampParamFollow(let device, let module, let param):
            guard isActive(device) else { return skip(device) }
            guard let amp = devices[device],
                  let spec = amp.profile.parameter(module: module, param: param) else { return }
            let span = spec.maxValue - spec.minValue
            let mapped = spec.minValue + Double(value) / 127.0 * span
            amp.setParameter(module, param: param, value: mapped)

        case .korgProgram(let program):
            guard keyboardMode else { return skip("KORG") }
            korg.select(program: program)

        case .korgStep(let delta):
            guard keyboardMode else { return skip("KORG") }
            korg.step(delta)

        case .korgSetlistNext:
            guard keyboardMode else { return skip("KORG") }
            korg.nextSetlist()

        case .drumToggle(let device):
            guard isActive(device) else { return skip(device) }
            guard let amp = devices[device] else { return }
            let playing = drumPlaying[device] ?? false
            amp.sendCC(61, playing ? 0 : 127)
            drumPlaying[device] = !playing
            log("鼓机 \(playing ? "停止" : "播放")")

        case .drumStep(let device, let delta):
            guard isActive(device) else { return skip(device) }
            guard let amp = devices[device] else { return }
            let current = Int(amp.value("drum", 1))
            var next = current + delta
            if next < 0 { next = 99 }
            if next > 99 { next = 0 }
            amp.setParameter("drum", param: 1, value: Double(next))

        case .bankStep(let delta):
            cycleBank(delta)
        }
    }

    private func isActive(_ deviceID: DeviceProfileID) -> Bool {
        deviceID == activeDeviceID
    }

    private func skip(_ deviceID: String) {
        lastEvent = "已忽略：当前不是 \(deviceID) 模式"
    }

    private func cycleBank(_ delta: Int) {
        let banks = store.data.pedalBanks
        guard banks.count > 1 else { return }
        let currentID = store.activeBank?.id
        let index = banks.firstIndex { $0.id == currentID } ?? 0
        let next = ((index + delta) % banks.count + banks.count) % banks.count
        store.data.activeBankID = banks[next].id
        log("切换到踏板组：\(banks[next].name)")
    }

    func log(_ text: String) {
        logLines.append(text)
        if logLines.count > 200 { logLines.removeFirst(logLines.count - 200) }
    }

    /// 给"自定义面板"这类界面直接调用。
    func trigger(_ mapping: PedalMapping, value: Int = 127) {
        perform(mapping.action, value: value)
        pressCount += 1
        lastEvent = "手动 · \(mapping.trigger.label) → \(mapping.displayTitle)"
    }
}
