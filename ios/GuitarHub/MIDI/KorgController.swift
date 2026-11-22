import Foundation
import Combine

/// KORG Module 的控制端。
///
/// Module 没有对外广播"当前音色名"的机制，因此 App 以"节目单槽位"为唯一事实来源：
/// 每个槽位 = 一个 Program Change 编号 + 一个用户填写的显示名。
///
/// 投递方式：本 App 创建一个虚拟 MIDI 端口 "GuitarHub"，Module 在后台运行
/// （设置里打开 Background Audio）并在 MIDI 输入中选中该端口即可收到 PC。
final class KorgController: ObservableObject {

    @Published private(set) var currentProgram: Int = 0
    @Published private(set) var currentName: String = "—"
    @Published private(set) var currentMemo: String = ""
    @Published private(set) var lastSentAt: Date?
    @Published private(set) var lastSendDescription = "—"

    let midi: MIDIService
    private let store: AppStore

    init(midi: MIDIService, store: AppStore) {
        self.midi = midi
        self.store = store
        let saved = UserDefaults.standard.integer(forKey: "korg.lastProgram")
        self.currentProgram = saved
        applyName(for: saved)
    }

    // MARK: - 读

    var setlist: KorgSetlist? { store.activeKorgSetlist }
    var slots: [KorgSlot] { setlist?.slots.sorted { $0.program < $1.program } ?? [] }
    var channel: Int { (setlist?.midiChannel ?? store.data.settings.korgChannel).clamped(to: 1...16) }

    func slot(for program: Int) -> KorgSlot? { setlist?.slot(program: program) }
    var currentSlotIndex: Int? { slots.firstIndex { $0.program == currentProgram } }

    // MARK: - 控制

    func select(program: Int, sendMIDI: Bool = true) {
        let clamped = program.clamped(to: 0...127)
        currentProgram = clamped
        UserDefaults.standard.set(clamped, forKey: "korg.lastProgram")
        applyName(for: clamped)
        if sendMIDI { sendPC(clamped) }
        lastSentAt = Date()
    }

    func step(_ delta: Int, sendMIDI: Bool = true) {
        guard !slots.isEmpty else {
            select(program: currentProgram + delta, sendMIDI: sendMIDI)
            return
        }
        let index = currentSlotIndex ?? 0
        let count = slots.count
        let next = ((index + delta) % count + count) % count
        select(program: slots[next].program, sendMIDI: sendMIDI)
    }

    func nextSetlist() {
        let lists = store.data.korgSetlists
        guard lists.count > 1, let active = store.activeKorgSetlist,
              let index = lists.firstIndex(where: { $0.id == active.id }) else { return }
        let next = lists[(index + 1) % lists.count]
        store.data.activeKorgSetlistID = next.id
        if let first = next.slots.sorted(by: { $0.program < $1.program }).first {
            select(program: first.program)
        }
    }

    func resendCurrent() {
        sendPC(currentProgram)
        lastSentAt = Date()
    }

    /// 界面上手动改完名字后刷新大屏。
    func refreshFromStore() {
        applyName(for: currentProgram)
    }

    private func applyName(for program: Int) {
        if let slot = slot(for: program) {
            currentName = slot.name
            currentMemo = slot.memo
        } else {
            currentName = "音色 \(program + 1)"
            currentMemo = ""
        }
    }

    private func sendMessage(_ message: MIDIMessage, description: String) {
        midi.send([message], description: description)
        lastSendDescription = description
    }

    private func sendPC(_ program: Int) {
        let base = store.data.settings.korgPCBase ?? 0
        let value = (program + base).clamped(to: 0...127)
        sendMessage(MIDIMessage.programChange(channel: channel, program: value),
                    description: "PC ch\(channel) #\(value)")
    }

    /// 用标准 RPN 2（Master Coarse Tuning）移调，单位半音，中心 64。
    func sendTranspose(_ semitones: Int) {
        let ch = channel
        let value = (64 + semitones).clamped(to: 0...127)
        let steps: [(Int, Int)] = [(101, 0), (100, 2), (6, value), (38, 0)]
        for (index, step) in steps.enumerated() {
            DispatchQueue.main.asyncAfter(deadline: .now() + Double(index) * 0.02) { [weak self] in
                guard let self else { return }
                self.sendMessage(MIDIMessage.controlChange(channel: ch, number: step.0, value: step.1),
                                 description: "RPN2 ch\(ch) \(semitones > 0 ? "+" : "")\(semitones)")
            }
        }
    }

    /// 依次在 1–16 通道发 PC 0，用来找出 Module 实际监听的通道。
    func sweepChannels() {
        let base = store.data.settings.korgPCBase ?? 0
        for offset in 0..<16 {
            DispatchQueue.main.asyncAfter(deadline: .now() + Double(offset) * 0.25) { [weak self] in
                guard let self else { return }
                let ch = offset + 1
                let message = MIDIMessage.programChange(channel: ch, program: base)
                self.sendMessage(message, description: "扫描 ch\(ch) PC \(base)")
            }
        }
    }
}
