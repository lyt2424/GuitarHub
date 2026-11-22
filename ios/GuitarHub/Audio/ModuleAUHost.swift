import Foundation
import AVFoundation
import CoreMIDI
import Combine

/// 把 KORG Module 作为 AUv3 插件加载进来，直接读它的预设和参数。
/// 同时把 CoreMIDI 的输入（键盘 USB MIDI）转发给插件。
final class ModuleAUHost: ObservableObject {

    @Published private(set) var status = "未加载"
    @Published private(set) var isReady = false
    @Published private(set) var presets: [AUAudioUnitPreset] = []
    @Published private(set) var currentIndex: Int = 0
    @Published private(set) var currentName = "—"
    @Published private(set) var parameters: [AUParameter] = []
    @Published private(set) var discoveredComponents: [String] = []

    private let engine = AVAudioEngine()
    private var unit: AVAudioUnit?
    private var au: AUAudioUnit?
    private var midiClient = MIDIClientRef()
    private var midiPort = MIDIPortRef()
    private var connectedSources: Set<MIDIEndpointRef> = []
    private let parser = MIDIStreamParser()
    private var sourceParsers: [MIDIEndpointRef: MIDIStreamParser] = [:]

    // MARK: - 加载

    func load() {
        guard !isReady else { return }
        status = "正在查找 KORG Module 插件…"

        // 列出系统里所有 AUv3 组件，便于诊断。
        // 注意：必须用 components(matching:)，直接写 .components 会和同名方法产生歧义。
        // 全类型枚举：有些插件的注册类型不是 aumu，先全部列出来再筛。
        let query = AudioComponentDescription(
            componentType: 0,
            componentSubType: 0,
            componentManufacturer: 0,
            componentFlags: 0,
            componentFlagsMask: 0
        )
        let all = AVAudioUnitComponentManager.shared().components(matching: query)
        discoveredComponents = all.map { "\($0.name) · \($0.manufacturerName)" }

        let candidates = all.filter { component in
            let name = component.name.lowercased()
            let maker = component.manufacturerName.lowercased()
            let isInstrument = component.audioComponentDescription.componentType == kAudioUnitType_MusicDevice
            return isInstrument && (name.contains("module") || maker.contains("korg"))
        }

        // 同时装了免费版和 Pro 时，优先选名字带 Pro 的。
        guard let component = candidates.first(where: { $0.name.lowercased().contains("pro") })
                ?? candidates.first else {
            status = "没有找到 KORG Module 插件。请确认装的是 Module Pro，并先打开它一次。"
            return
        }

        status = "正在加载 \(component.name)…"
        AVAudioUnit.instantiate(with: component.audioComponentDescription, options: []) { [weak self] unit, error in
            guard let self else { return }
            if let error {
                DispatchQueue.main.async { self.status = "加载失败：\(error.localizedDescription)" }
                return
            }
            guard let unit else {
                DispatchQueue.main.async { self.status = "加载失败：插件无返回" }
                return
            }
            DispatchQueue.main.async { self.attach(unit) }
        }
    }

    private func attach(_ unit: AVAudioUnit) {
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .default, options: [.mixWithOthers])
            try session.setActive(true)
        } catch {
            status = "音频会话失败：\(error.localizedDescription)"
            return
        }

        self.unit = unit
        engine.attach(unit)
        engine.connect(unit, to: engine.mainMixerNode, format: nil)
        engine.prepare()

        do {
            try engine.start()
        } catch {
            status = "音频引擎启动失败：\(error.localizedDescription)"
            return
        }

        au = unit.auAudioUnit
        presets = unit.auAudioUnit.factoryPresets ?? []
        parameters = unit.auAudioUnit.parameterTree?.allParameters ?? []
        if let preset = unit.auAudioUnit.currentPreset,
           let index = presets.firstIndex(where: { $0.number == preset.number }) {
            currentIndex = index
            currentName = preset.name
        } else if let first = presets.first {
            currentIndex = 0
            currentName = first.name
            unit.auAudioUnit.currentPreset = first
        } else {
            currentName = unit.name
        }

        isReady = true
        status = "已加载 \(unit.name) · \(presets.count) 个预设"
        startMIDIInput()
    }

    // MARK: - 预设

    func select(_ index: Int) {
        guard isReady, !presets.isEmpty else { return }
        let clamped = index.clamped(to: 0...(presets.count - 1))
        let preset = presets[clamped]
        au?.currentPreset = preset
        currentIndex = clamped
        currentName = preset.name
    }

    func step(_ delta: Int) {
        guard !presets.isEmpty else { return }
        let count = presets.count
        let next = ((currentIndex + delta) % count + count) % count
        select(next)
    }

    // MARK: - MIDI 输入

    private func startMIDIInput() {
        guard midiClient == 0 else { return }
        var status = MIDIClientCreateWithBlock("GuitarHub AU" as CFString, &midiClient) { _ in }
        guard status == noErr else { return }
        status = MIDIInputPortCreateWithBlock(midiClient, "GuitarHub AU In" as CFString, &midiPort) { [weak self] packetList, _ in
            guard let self else { return }
            self.handle(packetList, source: 0)
        }
        guard status == noErr else { return }
        connectAllSources()
    }

    private func connectAllSources() {
        for index in 0..<MIDIGetNumberOfSources() {
            let source = MIDIGetSource(index)
            guard !connectedSources.contains(source) else { continue }
            var name: Unmanaged<CFString>?
            MIDIObjectGetStringProperty(source, kMIDIPropertyDisplayName, &name)
            let display = (name?.takeRetainedValue() as String?) ?? ""
            // 跳过我们自己的虚拟端口，避免回环
            if display.contains("GuitarHub") { continue }
            if MIDIPortConnectSource(midiPort, source, nil) == noErr {
                connectedSources.insert(source)
            }
        }
    }

    private func handle(_ packetList: UnsafePointer<MIDIPacketList>, source: MIDIEndpointRef) {
        let dataOffset = MemoryLayout<MIDIPacketList>.offset(of: \.packet) ?? 8
        let dataInnerOffset = MemoryLayout<MIDIPacket>.offset(of: \.data) ?? 8
        var packetPtr = UnsafeRawPointer(packetList)
            .advanced(by: dataOffset)
            .assumingMemoryBound(to: MIDIPacket.self)

        for _ in 0..<packetList.pointee.numPackets {
            let length = Int(packetPtr.pointee.length)
            if length > 0, length <= 256 {
                let bytesPtr = UnsafeRawPointer(packetPtr)
                    .advanced(by: dataInnerOffset)
                    .assumingMemoryBound(to: UInt8.self)
                let bytes = Array(UnsafeBufferPointer(start: bytesPtr, count: length))
                let messages = parser.feed(bytes)
                for message in messages {
                    sendToAU(message)
                }
            }
            packetPtr = UnsafePointer(MIDIPacketNext(packetPtr))
        }
    }

    private func sendToAU(_ message: MIDIMessage) {
        guard let au, let block = au.scheduleMIDIEventBlock else { return }
        let bytes = message.bytes
        bytes.withUnsafeBufferPointer { buffer in
            guard let base = buffer.baseAddress else { return }
            block(AUEventSampleTimeImmediate, 0, bytes.count, base)
        }
    }
}
