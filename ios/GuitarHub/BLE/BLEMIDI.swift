import Foundation
import CoreBluetooth

/// BLE MIDI 规范（Apple 定义）：
///   服务 03B80E5A-EDE8-4B33-A751-6CE34EC4C700
///   特征 7772E5DB-3868-4112-A1A9-F2669D106BF3
/// 数据包格式：<header bit7=1><timestamp low bit7=0><midi bytes…>，
/// 高位字节的时间戳与数据交错出现，所以解包时要跳过所有 ≥0x80 的字节。
enum BLEMIDI {
    static let serviceUUID = CBUUID(string: "03B80E5A-EDE8-4B33-A751-6CE34EC4C700")
    static let characteristicUUID = CBUUID(string: "7772E5DB-3868-4112-A1A9-F2669D106BF3")

    /// 去掉 BLE MIDI 的头与时间戳，只留下纯 MIDI 字节流。
    ///
    /// 每个 BLE 通知通常是：包头(bit7=1) + 时间戳 + MIDI 消息。
    /// 时间戳低字节按规范 bit7=0，但不少硬件（Chocolate 等）会发成 0x80–0xFF，
    /// 不能按 bit7 判断，否则会把 MIDI 状态字节一起丢掉。
    static func decode(_ data: Data) -> [UInt8] {
        let bytes = [UInt8](data)
        guard bytes.count > 2 else { return [] }

        // 跳过包头和时间戳，从第一个 MIDI 状态字节开始。
        var index = 2
        while index < bytes.count, bytes[index] & 0x80 == 0 {
            index += 1
        }
        guard index < bytes.count else { return [] }
        return Array(bytes[index...])
    }

    /// 把纯 MIDI 字节封装成一个 BLE MIDI 包（时间戳取当前毫秒的低 13 位）。
    static func encode(_ midi: [UInt8]) -> Data {
        guard !midi.isEmpty else { return Data() }
        // 注意：毫秒时间戳约 1.8e12，必须先取模再转 UInt16，否则运行时直接崩。
        let millis = UInt64(Date().timeIntervalSince1970 * 1000)
        let timestamp = UInt16(millis & 0x1FFF)
        // 包头最高位=1；时间戳低 7 位的最高位必须为 0（0x00…0x7F）。
        var out: [UInt8] = [
            0x80 | UInt8((timestamp >> 7) & 0x3F),
            UInt8(timestamp & 0x7F)
        ]
        out.append(contentsOf: midi)
        return Data(out)
    }
}
