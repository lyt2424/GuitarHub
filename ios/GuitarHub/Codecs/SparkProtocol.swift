import Foundation

/// Spark 私有协议：块/分块结构 + 7bit 打包 + msgpack 变体。
///
/// 依据公开逆向资料：
/// - paulhamsh/SparkIO4（SparkIO.ino / SparkComms.ino）
/// - paulhamsh/Spark-Bluetooth-Message-Format（Spark Protocol Description v3.2）
///
/// 结构要点：
///   蓝牙块：     [01 FE + 14 字节块头]（Mini/GO 可能没有） + 若干分块
///   分块：       F0 01 seq chksum cmd sub  <7bit 打包的 payload>  F7
///   打包：       每 8 字节一组，第 1 字节是按位掩码，其后 7 字节的低 7 位是数据，
///                掩码对应位为 1 时表示该字节的真实值要 |0x80。
///   校验：       异或（xor）payload 的所有字节。
///   消息头：     cmd sub len_hi len_lo (校验错误数) (序号) —— 只在解包后的逻辑消息里出现。
enum SparkProtocol {

    /// 单块最多 32 字节（4 组 × 8），扣除 4 个掩码和 3 字节分块头 = 25 字节数据。
    static let maxChunkData = 25

    // MARK: - 编码（App → 音箱）

    /// 把一条逻辑消息（不含 6 字节头）打包成一个分块。
    static func frame(cmd: UInt8, sub: UInt8, payload: [UInt8], sequence: UInt8) -> [UInt8] {
        var packed: [UInt8] = []
        var index = 0
        while index < payload.count {
            let end = min(index + 7, payload.count)
            var mask: UInt8 = 0
            for offset in 0..<(end - index) where payload[index + offset] & 0x80 != 0 {
                mask |= UInt8(1) << UInt8(offset)
            }
            packed.append(mask)
            for offset in index..<end {
                packed.append(payload[offset] & 0x7F)
            }
            index = end
        }
        let checksum = packed.reduce(UInt8(0)) { $0 ^ $1 }
        return [0xF0, 0x01, sequence, checksum, cmd, sub] + packed + [0xF7]
    }

    // MARK: - 解码（音箱 → App）

    struct Message {
        var cmd: UInt8
        var sub: UInt8
        var payload: [UInt8]
        var cmdSub: UInt16 { UInt16(cmd) << 8 | UInt16(sub) }
    }

    final class Decoder {
        private var buffer: [UInt8] = []
        private var pending: [UInt8: (total: Int, parts: [Int: [UInt8]])] = [:]
        private var sequenceCounter = 0

        /// 返回本次新解出的完整消息。
        func feed(_ data: [UInt8]) -> [Message] {
            buffer.append(contentsOf: data)
            var messages: [Message] = []

            while true {
                // 去掉 Spark 40 的 16 字节块头
                if buffer.count >= 16, buffer[0] == 0x01, buffer[1] == 0xFE {
                    buffer.removeFirst(16)
                    continue
                }
                guard let end = buffer.firstIndex(of: 0xF7) else { break }
                let frame = Array(buffer[0...end])
                buffer.removeFirst(end + 1)
                messages.append(contentsOf: parseFrame(frame))
                if buffer.count > 8192 { buffer.removeAll() }
            }
            return messages
        }

        private func parseFrame(_ frame: [UInt8]) -> [Message] {
            var messages: [Message] = []
            var index = 0
            while index + 5 < frame.count {
                guard frame[index] == 0xF0, frame[index + 1] == 0x01 else {
                    index += 1
                    continue
                }
                let sequence = frame[index + 2]
                let checksum = frame[index + 3]
                let cmd = frame[index + 4]
                let sub = frame[index + 5]

                var cursor = index + 6
                var packed: [UInt8] = []
                while cursor < frame.count, frame[cursor] != 0xF7 {
                    packed.append(frame[cursor])
                    cursor += 1
                }

                let calculated = packed.reduce(UInt8(0)) { $0 ^ $1 }
                if calculated != checksum {
                    // 文档明确指出音箱发出的数据可能不可靠：校验错也继续解析。
                }

                let unpacked = Self.unpack(packed, cmd: cmd, sub: sub)
                let isPreset = (sub == 0x01 && (cmd == 0x01 || cmd == 0x03))
                if isPreset {
                    let total = max(1, Int(unpacked.total))
                    let partIndex = max(0, Int(unpacked.index))
                    var entry = pending[sequence] ?? (total: total, parts: [:])
                    entry.total = total
                    entry.parts[partIndex] = unpacked.data
                    pending[sequence] = entry
                    if entry.parts.count >= total {
                        var payload: [UInt8] = []
                        for i in 0..<total {
                            if let part = entry.parts[i] { payload.append(contentsOf: part) }
                        }
                        pending.removeValue(forKey: sequence)
                        messages.append(Message(cmd: cmd, sub: sub, payload: payload))
                    }
                } else {
                    messages.append(Message(cmd: cmd, sub: sub, payload: unpacked.data))
                }

                index = cursor + 1
            }
            return messages
        }

        /// 解包 + 去掉分块头。返回 (总块数, 块序号, 数据)。
        static func unpack(_ packed: [UInt8], cmd: UInt8, sub: UInt8) -> (total: UInt8, index: UInt8, data: [UInt8]) {
            var data: [UInt8] = []
            var total: UInt8 = 1
            var partIndex: UInt8 = 0
            var bits: UInt8 = 0
            var bitmask: UInt8 = 1
            var counter = 0
            let isPreset = (sub == 0x01 && (cmd == 0x01 || cmd == 0x03))

            for byte in packed {
                if counter % 8 == 0 {
                    bits = byte
                    bitmask = 1
                } else {
                    var value = byte
                    if bits & bitmask != 0 { value |= 0x80 }
                    bitmask = bitmask &<< 1

                    if isPreset, counter >= 1, counter <= 3 {
                        if counter == 1 { total = value }
                        if counter == 2 { partIndex = value }
                    } else {
                        data.append(value)
                    }
                }
                counter += 1
                if cmd == 0x03, sub == 0x01, counter == 32 { counter = 0 }
                if cmd == 0x01, sub == 0x01, counter == 150 { counter = 0 }
            }
            return (total, partIndex, data)
        }

        func nextSequence() -> UInt8 {
            sequenceCounter = (sequenceCounter + 1) % 256
            return UInt8(sequenceCounter)
        }
    }
}

// MARK: - 预设结构

struct SparkPedal {
    var name: String
    var enabled: Bool
    var params: [Float]
}

struct SparkPreset {
    var currentPreset: Int = 0
    var presetNumber: Int = 0
    var uuid: String = ""
    var name: String = ""
    var version: String = ""
    var description: String = ""
    var icon: String = ""
    var bpm: Float = 120
    var pedals: [SparkPedal] = []
}

/// msgpack 变体读取器。Spark 的字符串/浮点格式并不完全标准（见 SparkIO.ino）。
struct SparkPayloadReader {
    private let bytes: [UInt8]
    private var pos = 0

    init(_ bytes: [UInt8]) { self.bytes = bytes }

    var isAtEnd: Bool { pos >= bytes.count }

    mutating func byte() -> UInt8? {
        guard pos < bytes.count else { return nil }
        defer { pos += 1 }
        return bytes[pos]
    }

    /// 有些整数字段前会多一个 0xCC。
    mutating func uint() -> UInt8? {
        guard var value = byte() else { return nil }
        if value == 0xCC {
            guard let next = byte() else { return nil }
            value = next
        }
        return value
    }

    /// 字符串：0xA0+len，或 0xD9 len，或 0x00 0xA0+len。
    mutating func string() -> String {
        guard var marker = byte() else { return "" }
        var length = 0
        if marker == 0xD9 {
            length = Int(byte() ?? 0)
        } else if marker >= 0xA0, marker < 0xC0 {
            length = Int(marker - 0xA0)
        } else {
            marker = byte() ?? 0
            length = marker >= 0xA0 ? Int(marker - 0xA0) : 0
        }
        guard length > 0, pos + length <= bytes.count else { return "" }
        let slice = bytes[pos..<(pos + length)]
        pos += length
        return String(bytes: slice.map { ($0 >= 0x20 && $0 <= 0x7E) ? $0 : 0x20 }, encoding: .utf8) ?? ""
    }

    /// 浮点：0xCA + 4 字节。按大端解释；若明显越界则回退到小端。
    mutating func float(expected: ClosedRange<Float>? = nil) -> Float {
        guard byte() == 0xCA else { return 0 }
        guard pos + 4 <= bytes.count else { return 0 }
        let b = Array(bytes[pos..<(pos + 4)])
        pos += 4
        let be = Float(bitPattern: UInt32(b[0]) << 24 | UInt32(b[1]) << 16 | UInt32(b[2]) << 8 | UInt32(b[3]))
        let le = Float(bitPattern: UInt32(b[3]) << 24 | UInt32(b[2]) << 16 | UInt32(b[1]) << 8 | UInt32(b[0]))
        if let range = expected {
            if range.contains(be) { return be }
            if range.contains(le) { return le }
            return be
        }
        return be
    }

    mutating func skip(_ count: Int) {
        pos = min(bytes.count, pos + count)
    }
}

// MARK: - 预设解析

enum SparkPresetParser {

    static func parse(_ payload: [UInt8]) -> SparkPreset? {
        var reader = SparkPayloadReader(payload)
        var preset = SparkPreset()

        guard let current = reader.byte(), let number = reader.byte() else { return nil }
        preset.currentPreset = Int(current)
        preset.presetNumber = Int(number)
        preset.uuid = reader.string()
        preset.name = reader.string()
        preset.version = reader.string()
        preset.description = reader.string()
        preset.icon = reader.string()
        preset.bpm = reader.float(expected: 20...400)

        guard let pedalCountByte = reader.byte() else { return preset }
        let pedalCount = Int(pedalCountByte) - 0x90
        guard pedalCount > 0, pedalCount <= 16 else { return preset }

        for _ in 0..<pedalCount {
            var pedal = SparkPedal(name: reader.string(), enabled: false, params: [])
            pedal.enabled = reader.byte() == 0xC3
            guard let paramCountByte = reader.byte() else { break }
            let paramCount = Int(paramCountByte) - 0x90
            guard paramCount > 0, paramCount <= 32 else { break }
            for _ in 0..<paramCount {
                _ = reader.byte()   // 参数序号
                _ = reader.byte()   // 0x91
                pedal.params.append(reader.float(expected: 0...1))
            }
            preset.pedals.append(pedal)
        }
        _ = reader.byte()   // 预设校验和
        return preset
    }
}
