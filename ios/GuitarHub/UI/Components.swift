import SwiftUI

enum Theme {
    static let background = Color(red: 0.06, green: 0.06, blue: 0.07)
    static let card = Color(red: 0.12, green: 0.12, blue: 0.14)
    static let cardHigh = Color(red: 0.20, green: 0.20, blue: 0.22)
    static let accent = Color(red: 1.0, green: 0.45, blue: 0.12)
    static let accentSoft = Color(red: 1.0, green: 0.45, blue: 0.12).opacity(0.18)
    static let onColor = Color(red: 0.35, green: 0.85, blue: 0.55)
    static let offColor = Color(red: 0.45, green: 0.45, blue: 0.48)
    static let danger = Color(red: 1.0, green: 0.32, blue: 0.32)
}

extension Color {
    init?(hex: String) {
        var text = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.hasPrefix("#") { text.removeFirst() }
        guard text.count == 6, let value = UInt32(text, radix: 16) else { return nil }
        self.init(red: Double((value >> 16) & 0xFF) / 255.0,
                  green: Double((value >> 8) & 0xFF) / 255.0,
                  blue: Double(value & 0xFF) / 255.0)
    }

    /// 配置里没写颜色时的兜底：按 id 稳定分配一个颜色。
    static func module(_ spec: ModuleSpec) -> Color {
        if let color = Color(hex: spec.colorHex) { return color }
        let palette: [Color] = [
            Color(red: 0.92, green: 0.30, blue: 0.30),
            Color(red: 0.95, green: 0.58, blue: 0.15),
            Color(red: 0.30, green: 0.65, blue: 0.95),
            Color(red: 0.55, green: 0.45, blue: 0.95),
            Color(red: 0.25, green: 0.75, blue: 0.55),
            Color(red: 0.20, green: 0.70, blue: 0.75),
            Color(red: 0.85, green: 0.40, blue: 0.70)
        ]
        let hash = spec.id.unicodeScalars.reduce(0) { ($0 &* 31 &+ Int($1.value)) & 0x7FFF_FFFF }
        return palette[hash % palette.count]
    }
}

struct StatusDot: View {
    var status: ConnectionStatus

    var color: Color {
        switch status {
        case .connected:    return Theme.onColor
        case .scanning, .connecting: return Theme.accent
        case .failed:       return Theme.danger
        case .disconnected: return Theme.offColor
        }
    }

    var body: some View {
        Circle()
            .fill(color)
            .frame(width: 8, height: 8)
    }
}

struct Card<Content: View>: View {
    var padding: CGFloat = 16
    @ViewBuilder var content: () -> Content

    var body: some View {
        content()
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(Theme.card)
            )
    }
}

struct SectionTitle: View {
    var text: String
    var trailing: String? = nil

    var body: some View {
        HStack {
            Text(text)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            Spacer()
            if let trailing {
                Text(trailing)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
    }
}

struct BigControlButton: View {
    var systemImage: String
    var title: String
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: systemImage)
                Text(title)
            }
            .font(.subheadline.weight(.semibold))
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(Theme.cardHigh, in: Capsule())
        }
        .buttonStyle(.plain)
    }
}

/// 颜色块：一眼看开关状态。点主体切换开关，点右上角小图标进入参数编辑。
struct ModuleBlock: View {
    let spec: ModuleSpec
    let enabled: Bool
    let selected: Bool
    let onToggle: () -> Void
    let onEdit: () -> Void

    private var fill: Color {
        enabled ? Color.module(spec) : Theme.cardHigh
    }

    var body: some View {
        ZStack(alignment: .topTrailing) {
            VStack(spacing: 2) {
                Text(spec.badge)
                    .font(.system(size: 25, weight: .heavy, design: .rounded))
                Text(spec.name)
                    .font(.system(size: 11, weight: .medium))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Text(enabled ? "ON" : "OFF")
                    .font(.system(size: 9, weight: .bold, design: .rounded))
                    .opacity(enabled ? 0.85 : 0.5)
            }
            .foregroundStyle(enabled ? Color.white : Color.white.opacity(0.32))
            .frame(maxWidth: .infinity)
            .frame(height: 84)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous).fill(fill)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(selected ? Color.white.opacity(0.85) : Color.clear, lineWidth: 2)
            )
            .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .onTapGesture(perform: onToggle)

            Button(action: onEdit) {
                Image(systemName: "slider.horizontal.3")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.white.opacity(0.9))
                    .padding(6)
                    .background(Circle().fill(Color.black.opacity(0.28)))
            }
            .buttonStyle(.plain)
            .padding(5)
        }
    }
}
