import SwiftUI
import AVFoundation

struct ModuleHostView: View {
    @ObservedObject var host: ModuleAUHost
    @EnvironmentObject private var hub: DeviceHub
    @State private var search = ""

    private var filtered: [(Int, AUAudioUnitPreset)] {
        let all = Array(host.presets.enumerated()).map { ($0.offset, $0.element) }
        guard !search.isEmpty else { return all }
        return all.filter { $0.1.name.localizedCaseInsensitiveContains(search) }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                heroCard

                if !host.isReady {
                    Card {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(host.status)
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                            Button("重新加载 KORG Module") { host.load() }
                                .font(.footnote)
                                .buttonStyle(.borderedProminent)
                                .tint(Theme.accent)

                            if !host.discoveredComponents.isEmpty {
                                Divider()
                                HStack(spacing: 10) {
                                    Button("复制组件列表") {
                                        UIPasteboard.general.string = host.componentsDump
                                    }
                                    .font(.caption)
                                    .buttonStyle(.bordered)

                                    Button("导出文件") {
                                        _ = host.exportComponents()
                                    }
                                    .font(.caption)
                                    .buttonStyle(.bordered)
                                }

                                Text("系统里已发现的 AUv3 组件（\(host.discoveredComponents.count) 个）：")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                ForEach(Array(host.discoveredComponents.prefix(12).enumerated()), id: \.offset) { _, line in
                                    Text(line)
                                        .font(.system(size: 10, design: .monospaced))
                                        .foregroundStyle(.tertiary)
                                }
                            }
                        }
                    }
                } else {
                    if !host.parameters.isEmpty { parameterCard }
                    presetCard
                }
            }
            .padding(16)
        }
        .onAppear { host.load() }
    }

    private var heroCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("KORG MODULE · AUv3")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.75))
                Spacer()
                Text("\(host.currentIndex + 1) / \(max(host.presets.count, 1))")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.white.opacity(0.7))
            }

            Text(host.currentName)
                .font(.system(size: 46, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
                .minimumScaleFactor(0.35)
                .lineLimit(1)

            HStack(spacing: 12) {
                Button { host.step(-1) } label: {
                    Image(systemName: "chevron.left")
                        .font(.headline.weight(.bold))
                        .frame(width: 52, height: 40)
                        .background(Color.white.opacity(0.18), in: RoundedRectangle(cornerRadius: 10))
                }
                .buttonStyle(.plain)
                Button { host.step(1) } label: {
                    Image(systemName: "chevron.right")
                        .font(.headline.weight(.bold))
                        .frame(width: 52, height: 40)
                        .background(Color.white.opacity(0.18), in: RoundedRectangle(cornerRadius: 10))
                }
                .buttonStyle(.plain)
                Spacer()
            }
            .foregroundStyle(.white)
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(LinearGradient(colors: [Color(red: 0.20, green: 0.48, blue: 0.92),
                                              Color(red: 0.52, green: 0.26, blue: 0.82)],
                                     startPoint: .topLeading,
                                     endPoint: .bottomTrailing))
        )
    }

    private var parameterCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 12) {
                SectionTitle(text: "常用参数", trailing: "\(host.parameters.count) 个")
                ForEach(host.parameters.prefix(8), id: \.address) { param in
                    VStack(spacing: 2) {
                        HStack {
                            Text(param.displayName).font(.footnote)
                            Spacer()
                            Text(String(format: "%.2f", param.value))
                                .font(.footnote.monospacedDigit())
                                .foregroundStyle(.secondary)
                        }
                        Slider(
                            value: Binding(
                                get: { Double(param.value) },
                                set: { param.value = AUValue($0) }
                            ),
                            in: Double(param.minValue)...Double(param.maxValue)
                        )
                        .tint(Theme.accent)
                    }
                }
            }
        }
    }

    private var presetCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 10) {
                SectionTitle(text: "音色列表", trailing: "\(host.presets.count) 个")

                TextField("搜索音色", text: $search)
                    .textFieldStyle(.roundedBorder)

                LazyVStack(spacing: 0) {
                    ForEach(filtered, id: \.1.number) { index, preset in
                        Button {
                            host.select(index)
                        } label: {
                            HStack {
                                Text("\(index + 1)")
                                    .font(.caption.monospacedDigit())
                                    .frame(width: 40, alignment: .leading)
                                    .foregroundStyle(index == host.currentIndex ? Theme.accent : .secondary)
                                Text(preset.name)
                                    .font(.subheadline)
                                    .foregroundStyle(.primary)
                                Spacer()
                                if index == host.currentIndex {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundStyle(Theme.accent)
                                }
                            }
                            .padding(.vertical, 7)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)

                        if index != filtered.last?.0 {
                            Divider().opacity(0.3)
                        }
                    }
                }
            }
        }
    }
}
