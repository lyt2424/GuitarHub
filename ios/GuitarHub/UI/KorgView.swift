import SwiftUI

struct KorgView: View {
    @EnvironmentObject private var hub: DeviceHub

    var body: some View {
        NavigationStack {
            KorgScreen(korg: hub.korg, store: hub.store, midi: hub.midi)
                .background(Theme.background)
                .navigationTitle("音源")
                .navigationBarTitleDisplayMode(.inline)
        }
    }
}

struct KorgScreen: View {
    @ObservedObject var korg: KorgController
    @ObservedObject var store: AppStore
    @ObservedObject var midi: MIDIService

    private var setlist: KorgSetlist? { korg.setlist }

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                Card {
                    VStack(spacing: 10) {
                        Text("KORG MODULE")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                        Text(korg.currentName)
                            .font(.system(size: 48, weight: .bold, design: .rounded))
                            .minimumScaleFactor(0.35)
                            .lineLimit(1)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        HStack {
                            Text("PC \(korg.currentProgram) · 通道 \(korg.channel)")
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(.secondary)
                            Spacer()
                            Text(korg.lastSendDescription)
                                .font(.caption2.monospaced())
                                .foregroundStyle(.tertiary)
                        }
                        HStack(spacing: 10) {
                            BigControlButton(systemImage: "chevron.left", title: "上一音色") { korg.step(-1) }
                            BigControlButton(systemImage: "chevron.right", title: "下一音色") { korg.step(1) }
                            BigControlButton(systemImage: "paperplane", title: "重发") { korg.resendCurrent() }
                            BigControlButton(systemImage: "list.bullet", title: "下一音色表") { korg.nextSetlist() }
                            Spacer(minLength: 0)
                        }
                    }
                }

                outputCard
                setlistCard
            }
            .padding(16)
        }
    }

    private var outputCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 8) {
                SectionTitle(text: "MIDI 输出", trailing: "虚拟端口 GuitarHub")
                HStack(spacing: 8) {
                    StatusDot(status: midi.isReady ? .connected : .failed("未就绪"))
                    Text(midi.statusText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("刷新") { midi.refresh() }
                        .font(.caption)
                }

                // 快速测试：点 1–8 应让 Module 跳到 Set List 对应位置
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

                Text("在 KORG Module 里打开 Background Audio，并把 MIDI 输入选为 “GuitarHub”。如果 Module 的输入列表里没有这个端口，就先用本 App 控制音箱和踏板，Module 照常手动操作。")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
    }

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
                                Image(systemName: slot.program == korg.currentProgram ? "largecircle.fill.circle" : "circle")
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
