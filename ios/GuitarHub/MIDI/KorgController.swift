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
    weak var blePeripheral: BLEMIDIPeripheral?
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

    private func sendPC(_ program: Int) {
        let base = store.data.settings.korgPCBase ?? 0
        let value = (program + base).clamped(to: 0...127)
        let message = MIDIMessage.programChange(channel: channel, program: value)
        let useBLE = (store.data.settings.korgBLEOutput ?? false) && (blePeripheral?.hasSubscribers ?? false)
        if useBLE {
            blePeripheral?.send(message.bytes)
        } else {
            midi.send([message], description: "PC ch\(channel) #\(value)")
        }
        let description = useBLE ? "PC #\(value)（BLE）" : "PC ch\(channel) #\(value)"
        lastSendDescription = description
    }
}
