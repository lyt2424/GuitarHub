import Foundation
import CoreMIDI
import Combine

/// CoreMIDI 封装：
/// - 创建一个名为 "GuitarHub" 的虚拟 MIDI 源，KORG Module 在它的 MIDI 输入里选中该端口即可接收。
/// - 同时监听系统里所有 MIDI 源（USB 声卡、蓝牙 MIDI、其他 App 的虚拟端口）。
/// - 如果检测到 KORG Module 自己暴露的虚拟目的端口，也可以直接投递。
final class MIDIService: ObservableObject {

    struct EndpointInfo: Identifiable, Hashable {
        var id: MIDIUniqueID
        var name: String
        var isVirtual: Bool
        var isOnline: Bool
    }

    enum RouteMode: String, Codable, CaseIterable, Identifiable {
        case auto
        case virtualOnly
        case directOnly
        var id: String { rawValue }
        var label: String {
            switch self {
            case .auto:        return "自动"
            case .virtualOnly: return "仅虚拟端口"
            case .directOnly:  return "仅直连目标"
            }
        }
    }

    @Published private(set) var destinations: [EndpointInfo] = []
    @Published private(set) var sources: [EndpointInfo] = []
    @Published private(set) var isReady = false
    @Published private(set) var statusText = "未启动"
    @Published private(set) var lastSendDescription = "—"

    /// (消息, 来源名)
    var onMessage: ((MIDIMessage, String) -> Void)?
    /// 发送到 Module 时额外回调，便于日志显示。
    var onSend: ((String) -> Void)?

    var routeMode: RouteMode = .auto
    var preferredDestinationName: String = "Module"

    private var client = MIDIClientRef()
    private var outputPort = MIDIPortRef()
    private var inputPort = MIDIPortRef()
    private var virtualSource = MIDIEndpointRef()
    private var parser = MIDIStreamParser()
    private var sourceParsers: [MIDIEndpointRef: MIDIStreamParser] = [:]
    private var refConSources: [UnsafeMutableRawPointer: MIDIEndpointRef] = [:]
    private var connectedSources: Set<MIDIEndpointRef> = []
    private var connectedDestinations: [MIDIEndpointRef] = []

    init() {
        setup()
    }

    deinit {
        if client != 0 { MIDIClientDispose(client) }
    }

    // MARK: - 初始化

    private func setup() {
        var status = MIDIClientCreateWithBlock("GuitarHub" as CFString, &client) { [weak self] _ in
            DispatchQueue.main.async {
                self?.refresh()
                self?.reconnectSources()
            }
        }
        guard status == noErr else {
            statusText = "MIDI 客户端创建失败 (\(status))"
            return
        }

        status = MIDIOutputPortCreate(client, "GuitarHub Out" as CFString, &outputPort)
        guard status == noErr else {
            statusText = "MIDI 输出端口创建失败 (\(status))"
            return
        }

        status = MIDIInputPortCreateWithBlock(client, "GuitarHub In" as CFString, &inputPort) { [weak self] packetList, srcConnRefCon in
            guard let self else { return }
            let sourceRef = srcConnRefCon.flatMap { self.refConSources[$0] } ?? 0
            self.handlePacketList(packetList, source: sourceRef)
        }
        guard status == noErr else {
            statusText = "MIDI 输入端口创建失败 (\(status))"
            return
        }

        status = MIDISourceCreate(client, "GuitarHub" as CFString, &virtualSource)
        if status != noErr {
            statusText = "虚拟 MIDI 源创建失败 (\(status))"
            return
        }

        MIDIObjectSetIntegerProperty(virtualSource, kMIDIPropertyUniqueID, 0x47485542)
        isReady = true
        statusText = "就绪：虚拟端口 GuitarHub"
        refresh()
        reconnectSources()
    }

    // MARK: - 端点枚举

    func refresh() {
        var dests: [EndpointInfo] = []
        for i in 0..<MIDIGetNumberOfDestinations() {
            let endpoint = MIDIGetDestination(i)
            if let info = endpointInfo(endpoint) { dests.append(info) }
        }
        var srcs: [EndpointInfo] = []
        for i in 0..<MIDIGetNumberOfSources() {
            let endpoint = MIDIGetSource(i)
            if let info = endpointInfo(endpoint) { srcs.append(info) }
        }
        destinations = dests.sorted { $0.name < $1.name }
        sources = srcs.sorted { $0.name < $1.name }

        connectedDestinations = destinations.compactMap { info in
            nameMatchesModule(info.name) ? endpoint(for: info.id) : nil
        }
        statusText = "就绪：\(destinations.count) 个目的端口 / \(sources.count) 个来源"
    }

    private func endpoint(for uniqueID: MIDIUniqueID) -> MIDIEndpointRef? {
        for i in 0..<MIDIGetNumberOfDestinations() {
            let e = MIDIGetDestination(i)
            var uid: Int32 = 0
            if MIDIObjectGetIntegerProperty(e, kMIDIPropertyUniqueID, &uid) == noErr, uid == uniqueID {
                return e
            }
        }
        for i in 0..<MIDIGetNumberOfSources() {
            let e = MIDIGetSource(i)
            var uid: Int32 = 0
            if MIDIObjectGetIntegerProperty(e, kMIDIPropertyUniqueID, &uid) == noErr, uid == uniqueID {
                return e
            }
        }
        return nil
    }

    private func nameMatchesModule(_ name: String) -> Bool {
        let lowered = name.lowercased()
        return lowered.contains("module") || lowered.contains("korg") || lowered.contains(preferredDestinationName.lowercased())
    }

    private func endpointInfo(_ endpoint: MIDIEndpointRef) -> EndpointInfo? {
        guard endpoint != 0 else { return nil }
        var unmanaged: Unmanaged<CFString>?
        var name = "未命名"
        if MIDIObjectGetStringProperty(endpoint, kMIDIPropertyDisplayName, &unmanaged) == noErr,
           let value = unmanaged?.takeRetainedValue() {
            name = value as String
        }
        var uid: Int32 = 0
        _ = MIDIObjectGetIntegerProperty(endpoint, kMIDIPropertyUniqueID, &uid)
        var online: Int32 = 1
        _ = MIDIObjectGetIntegerProperty(endpoint, kMIDIPropertyOffline, &online)
        return EndpointInfo(id: uid, name: name, isVirtual: name.contains("GuitarHub"), isOnline: online == 0)
    }

    private func reconnectSources() {
        for i in 0..<MIDIGetNumberOfSources() {
            let source = MIDIGetSource(i)
            guard source != virtualSource, !connectedSources.contains(source) else { continue }
            let refCon = UnsafeMutableRawPointer(bitPattern: Int(source))
            guard let refCon else { continue }
            refConSources[refCon] = source
            if MIDIPortConnectSource(inputPort, source, refCon) == noErr {
                connectedSources.insert(source)
                statusText = "已连接 \(connectedSources.count) 个 MIDI 来源"
            }
        }
    }

    // MARK: - 接收

    private func handlePacketList(_ packetList: UnsafePointer<MIDIPacketList>, source: MIDIEndpointRef) {
        let parser: MIDIStreamParser
        if let existing = sourceParsers[source] {
            parser = existing
        } else {
            let created = MIDIStreamParser()
            sourceParsers[source] = created
            parser = created
        }

        let sourceName = endpointInfo(source)?.name ?? "未知来源"
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
                if !messages.isEmpty {
                    DispatchQueue.main.async { [weak self] in
                        guard let self else { return }
                        for message in messages {
                            self.onMessage?(message, sourceName)
                        }
                    }
                }
            }
            packetPtr = MIDIPacketNext(packetPtr)
        }
    }

    // MARK: - 发送

    /// 发送一组 MIDI 消息；自动按路由模式选择虚拟端口与/或直连目的端口。
    func send(_ messages: [MIDIMessage], description: String? = nil) {
        guard isReady, !messages.isEmpty else { return }
        let bytes = messages.flatMap { $0.bytes }
        guard !bytes.isEmpty, bytes.count <= 256 else { return }

        var packetList = MIDIPacketList()
        var packet = MIDIPacketListInit(&packetList)
        let added = bytes.withUnsafeBufferPointer { buffer -> UnsafeMutablePointer<MIDIPacket>? in
            guard let base = buffer.baseAddress else { return nil }
            return MIDIPacketListAdd(&packetList,
                                     MemoryLayout<MIDIPacketList>.size,
                                     packet,
                                     0,
                                     ByteCount(bytes.count),
                                     base)
        }
        guard added != nil else { return }

        let useDirect: Bool
        switch routeMode {
        case .auto:        useDirect = !connectedDestinations.isEmpty
        case .directOnly:  useDirect = true
        case .virtualOnly: useDirect = false
        }

        if useDirect {
            for destination in connectedDestinations {
                MIDISend(outputPort, destination, &packetList)
            }
        }
        if !useDirect || routeMode == .auto {
            MIDIReceived(virtualSource, &packetList)
        }

        let desc = description ?? bytes.map { String(format: "%02X", $0) }.joined(separator: " ")
        lastSendDescription = desc
        onSend?(desc)
    }

    func sendProgramChange(channel: Int, program: Int) {
        let msg = MIDIMessage.programChange(channel: channel, program: program)
        send([msg], description: "PC ch\(channel) #\(program)")
    }

    func sendControlChange(channel: Int, number: Int, value: Int) {
        let msg = MIDIMessage.controlChange(channel: channel, number: number, value: value)
        send([msg], description: "CC ch\(channel) #\(number) = \(value)")
    }
}
