import SwiftUI

struct KorgView: View {
    @EnvironmentObject private var hub: DeviceHub

    var body: some View {
        NavigationStack {
            KorgScreen(korg: hub.korg, store: hub.store, midi: hub.midi, ble: hub.bleMIDI)
                .background(Theme.background)
                .navigationTitle("键盘模式")
                .navigationBarTitleDisplayMode(.inline)
        }
    }
}

struct KorgScreen: View {
    @ObservedObject var korg: KorgController
    @ObservedObject var store: AppStore
    @ObservedObject var midi: MIDIService
    @ObservedObject var ble: BLEMIDIPeripheral

    @EnvironmentObject private var hub: DeviceHub
    @Environment(\.verticalSizeClass) private var verticalSizeClass
    @State private var showPedal = false

    private var setlist: KorgSetlist? { korg.setlist }
    private var transpose: Int { store.data.settings.korgTranspose ?? 0 }
    private var isLandscape: Bool { verticalSizeClass == .compact }

    private static let notes = ["C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"]

    private var keyName: String {
        let index = ((transpose % 12) + 12) % 12
        return Self.notes[index]
    }

    private var bleEnabled: Bool { store.data.settings.korgBLEOutput ?? false }

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                heroCard
                outputCard
                setlistCard
            }
            .padding(16)
        }
        .onAppear {
            if bleEnabled { ble.start() }
        }
        .sheet(isPresented: $showPedal) {
            PedalView().environmentObject(hub)
        }
    }

    // MARK: - 大字音色 + 调性

    private var heroCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("KORG MODULE")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.75))
                Spacer()
                keyBadge
            }

            Text(korg.currentName)
                .font(.system(size: isLandscape ? 64 : 50, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
                .minimumScaleFactor(0.35)
                .lineLimit(1)

            HStack(spacing: 12) {
                Text("PC \(korg.currentProgram)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.white.opacity(0.7))
                Spacer()
                Button {
                    korg.step(-1)
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.headline.weight(.bold))
                        .frame(width: 46, height: 38)
                        .background(Color.white.opacity(0.18), in: RoundedRectangle(cornerRadius: 10))
                }
                .buttonStyle(.plain)
                Button {
                    korg.step(1)
                } label: {
                    Image(systemName: "chevron.right")
                        .font(.headline.weight(.bold))
                        .frame(width: 46, height: 38)
                        .background(Color.white.opacity(0.18), in: RoundedRectangle(cornerRadius: 10))
                }
                .buttonStyle(.plain)
                Button {
                    korg.resendCurrent()
                } label: {
                    Image(systemName: "paperplane")
                        .font(.subheadline.weight(.bold))
                        .frame(width: 46, height: 38)
                        .background(Color.white.opacity(0.18), in: RoundedRectangle(cornerRadius: 10))
                }
                .buttonStyle(.plain)
            }
            .foregroundStyle(.white)
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(LinearGradient(colors: [Color(red: 0.24, green: 0.52, blue: 0.95),
                                              Color(red: 0.55, green: 0.28, blue: 0.85)],
                                     startPoint: .topLeading,
                                     endPoint: .bottomTrailing))
        )
    }

    private var keyBadge: some View {
        HStack(spacing: 8) {
            VStack(spacing: 0) {
                Text("1 = \(keyName)")
                    .font(.system(size: 20, weight: .heavy, design: .rounded))
                    .foregroundStyle(.white)
                Text("调性")
                    .font(.system(size: 9))
                    .foregroundStyle(.white.opacity(0.7))
            }
            VStack(spacing: 2) {
                Button { changeTranspose(1) } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 10, weight: .bold))
                        .frame(width: 24, height: 18)
                        .background(Color.white.opacity(0.22), in: RoundedRectangle(cornerRadius: 5))
                }
                .buttonStyle(.plain)
                Button { changeTranspose(-1) } label: {
                    Image(systemName: "minus")
                        .font(.system(size: 10, weight: .bold))
                        .frame(width: 24, height: 18)
                        .background(Color.white.opacity(0.22), in: RoundedRectangle(cornerRadius: 5))
                }
                .buttonStyle(.plain)
            }
            .foregroundStyle(.white)
        }
    }

    private func changeTranspose(_ delta: Int) {
        let next = ((store.data.settings.korgTranspose ?? 0) + delta).clamped(to: -11...11)
        store.data.settings.korgTranspose = next
    }

    // MARK: - 输出

    private var outputCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 10) {
                SectionTitle(text: "输出方式", trailing: bleEnabled ? "BLE 外设" : "本机虚拟端口")

                Toggle("蓝牙 MIDI 广播（给 iPad 用）", isOn: Binding(
                    get: { bleEnabled },
                    set: { newValue in
                        store.data.settings.korgBLEOutput = newValue
                        if newValue { ble.start() } else { ble.stop() }
                    }
                ))
                .font(.footnote)
                .tint(Theme.onColor)

                if bleEnabled {
                    HStack(spacing: 8) {
                        StatusDot(status: ble.hasSubscribers ? .connected : .scanning)
                        Text(ble.statusText)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text("\(ble.subscriberCount) 台")
                            .font(.caption2.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                    Text("在 iPad 的 Module → 设置 → Bluetooth MIDI 里找到并连接 “舞台Control MIDI”。")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                } else {
                    HStack(spacing: 8) {
                        StatusDot(status: midi.isReady ? .connected : .failed("未就绪"))
                        Text(midi.statusText)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button("刷新") { midi.refresh() }
                            .font(.caption)
                    }
                }

                HStack(spacing: 6) {
                    ForEach(1...8, id: \.self) { number in
                        Button("\(number)") {
                            korg.select(program: number - 1)
                        }
                        .font(.caption.weight(.semibold))
                        .frame(width: 30, height: 30)
                        .background(Theme.cardHigh, in: RoundedRectangle(cornerRadius: 8))
                        .buttonStyle(.plain)
                    }
                    Spacer(minLength: 0)
                }
            }
        }
    }

    // MARK: - 音色表

    private var setlistCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 10) {
                SectionTitle(text: "音色表", trailing: "\(korg.slots.count) 个槽位")

                if let setlist {
                    TextField("音色表名称", text: Binding(
                        get: { setlist.name },
                        set: { newValue in
                            var copy = setlist
                            copy.name = newValue
                            store.updateKorgSetlist(copy)
                        }
                    ))
                    .textFieldStyle(.roundedBorder)

                    ForEach(Array(korg.slots.enumerated()), id: \.element.id) { index, slot in
                        HStack(spacing: 10) {
                            Text("\(slot.program)")
                                .font(.caption.monospacedDigit())
                                .frame(width: 34, alignment: .leading)
                                .foregroundStyle(slot.program == korg.currentProgram ? Theme.accent : .secondary)

                            TextField("显示名", text: bindingForName(index: index))
                                .textFieldStyle(.plain)
                                .font(.subheadline)

                            Button {
                                korg.select(program: slot.program)
                            } label: {
                                Image(systemName: slot.program == korg.currentProgram
                                      ? "largecircle.fill.circle" : "circle")
                                    .foregroundStyle(Theme.accent)
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(.vertical, 2)
                    }

                    Button {
                        addSlot()
                    } label: {
                        Label("添加槽位", systemImage: "plus.circle")
                            .font(.footnote)
                    }
                }
            }
        }
    }

    private func bindingForName(index: Int) -> Binding<String> {
        Binding(
            get: {
                guard let list = setlist, index < list.slots.count else { return "" }
                return list.slots[index].name
            },
            set: { newValue in
                guard var list = setlist, index < list.slots.count else { return }
                list.slots[index].name = newValue
                store.updateKorgSetlist(list)
                korg.refreshFromStore()
            }
        )
    }

    private func addSlot() {
        guard var list = setlist else { return }
        let next = (list.slots.map(\.program).max() ?? -1) + 1
        list.slots.append(KorgSlot(program: next, name: "音色 \(next + 1)"))
        store.updateKorgSetlist(list)
        korg.refreshFromStore()
    }
}

