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
    static func decode(_ data: Data) -> [UInt8] {
        let bytes = [UInt8](data)
        var out: [UInt8] = []
        var index = 0
        while index < bytes.count {
            let header = bytes[index]
            guard header & 0x80 != 0 else {
                index += 1
                continue
            }
            index += 1
            // 时间戳低字节
            if index < bytes.count, bytes[index] & 0x80 == 0 {
                index += 1
            }
            while index < bytes.count, bytes[index] & 0x80 == 0 {
                out.append(bytes[index])
                index += 1
            }
        }
        return out
    }

    /// 把纯 MIDI 字节封装成一个 BLE MIDI 包（时间戳取当前毫秒的低 13 位）。
    static func encode(_ midi: [UInt8]) -> Data {
        guard !midi.isEmpty else { return Data() }
        let timestamp = UInt16(Date().timeIntervalSince1970 * 1000) & 0x1FFF
        var out: [UInt8] = [
            0x80 | UInt8((timestamp >> 7) & 0x3F),
            0x80 | UInt8(timestamp & 0x7F)
        ]
        out.append(contentsOf: midi)
        return Data(out)
    }
}
