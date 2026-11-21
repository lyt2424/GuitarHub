import Foundation
import CoreBluetooth
import Combine

/// 一个 BLE 连接会话：负责扫描、连接、服务/特征发现、收发数据。
///
/// - 适配器（DeviceAdapter）只关心字节流，不直接碰 CoreBluetooth。
/// - 对未知设备（Pulze / MG-50）会把发现到的 GATT 结构写进 `profile`，方便逆向。
final class BLESession: NSObject, ObservableObject {

    @Published private(set) var status: ConnectionStatus = .disconnected
    @Published private(set) var discovered: [DiscoveredDevice] = []
    @Published private(set) var profile: String = ""
    @Published private(set) var connectedName: String?
    @Published private(set) var isScanning: Bool = false
    @Published private(set) var mtu: Int = 20

    /// 只保留名字匹配的外设；nil 表示全部保留。
    var nameFilter: ((String) -> Bool)?
    /// 只扫描这些服务；nil 表示扫描全部。
    var serviceFilter: [CBUUID]?

    var onConnect: (() -> Void)?
    var onDisconnect: ((String?) -> Void)?
    var onData: ((Data) -> Void)?
    var onLog: ((String) -> Void)?
    /// 每次发现 GATT 结构后回调，便于调试界面展示。
    var onProfile: ((String) -> Void)?

    private var central: CBCentralManager?
    private var target: CBPeripheral?
    private var writeChar: CBCharacteristic?
    private var notifyChars: [CBCharacteristic] = []
    private var known: [UUID: CBPeripheral] = [:]
    private var connectTimeout: DispatchWorkItem?
    private var scanTimeout: DispatchWorkItem?
    private var autoReconnect = true
    private var pendingScan = false
    private var expectedServiceCount = 0
    private var discoveredServiceCount = 0
    private var didFinishDiscovery = false

    // MARK: - 生命周期

    private func ensureCentral() {
        guard central == nil else { return }
        central = CBCentralManager(delegate: self, queue: .main)
    }

    func startScan() {
        ensureCentral()
        guard let central else { return }
        guard central.state == .poweredOn else {
            if central.state == .unknown {
                // 首次启动时状态还没就绪，等 poweredOn 回调后自动开始扫描。
                pendingScan = true
                log("等待蓝牙就绪…")
            } else {
                log("蓝牙状态：\(stateName(central.state))，暂时无法扫描")
                status = .disconnected
            }
            return
        }
        discovered.removeAll()
        profile = ""
        didFinishDiscovery = false
        writeChar = nil
        notifyChars.removeAll()
        isScanning = true
        status = .scanning
        central.scanForPeripherals(withServices: serviceFilter,
                                   options: [CBCentralManagerScanOptionAllowDuplicatesKey: false])
        log("开始扫描…")
        scanTimeout?.cancel()
        let item = DispatchWorkItem { [weak self] in
            guard let self, self.isScanning else { return }
            self.stopScan()
            self.log("扫描超时，已停止。请确认设备已开机并处于可连接状态。")
        }
        scanTimeout = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 20, execute: item)
    }

    func stopScan() {
        central?.stopScan()
        isScanning = false
        scanTimeout?.cancel()
        if status == .scanning { status = .disconnected }
    }

    func connect(to id: UUID) {
        ensureCentral()
        guard let central else { return }
        // 优先用扫描缓存；App 重启后缓存为空，再尝试系统已缓存的外设。
        let cached = central.retrievePeripherals(withIdentifiers: [id])
        guard let peripheral = known[id] ?? cached.first else {
            status = .failed("找不到该设备，请重新搜索")
            return
        }
        known[id] = peripheral
        stopScan()
        autoReconnect = true
        target = peripheral
        peripheral.delegate = self
        status = .connecting
        log("正在连接 \(peripheral.name ?? "未知设备")…")
        central.connect(peripheral, options: nil)

        connectTimeout?.cancel()
        let item = DispatchWorkItem { [weak self] in
            guard let self, self.status == .connecting else { return }
            self.status = .failed("连接超时")
            self.central?.cancelPeripheralConnection(peripheral)
        }
        connectTimeout = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 15, execute: item)
    }

    func disconnect() {
        autoReconnect = false
        connectTimeout?.cancel()
        if let target {
            central?.cancelPeripheralConnection(target)
        }
        target = nil
        writeChar = nil
        notifyChars.removeAll()
        status = .disconnected
        connectedName = nil
    }

    // MARK: - 发送

    var canSend: Bool {
        status == .connected && writeChar != nil
    }

    func send(_ data: Data, withResponse: Bool = false) {
        guard let target, let char = writeChar else {
            log("尚未就绪，已丢弃 \(data.count) 字节")
            return
        }
        let type: CBCharacteristicWriteType
        if withResponse, char.properties.contains(.write) {
            type = .withResponse
        } else if char.properties.contains(.writeWithoutResponse) {
            type = .withoutResponse
        } else {
            type = .withResponse
        }
        target.writeValue(data, for: char, type: type)
    }

    /// 按 BLE 单包上限切片，并以固定间隔发送（很多音箱要求慢速、顺序写入）。
    func sendChunked(_ data: Data,
                     chunkSize: Int = 0,
                     interval: TimeInterval = 0.008,
                     completion: (() -> Void)? = nil) {
        let size = chunkSize > 0 ? chunkSize : max(20, min(mtu, 180))
        var offset = 0
        func sendNext() {
            guard offset < data.count else {
                completion?()
                return
            }
            let end = min(offset + size, data.count)
            let chunk = data.subdata(in: offset..<end)
            send(chunk)
            offset = end
            DispatchQueue.main.asyncAfter(deadline: .now() + interval) { sendNext() }
        }
        sendNext()
    }

    // MARK: - 日志

    private func log(_ message: String) {
        onLog?(message)
    }

    private func stateName(_ state: CBManagerState) -> String {
        switch state {
        case .poweredOn:  return "已开启"
        case .poweredOff: return "已关闭"
        case .unauthorized: return "未授权"
        case .unsupported: return "不支持"
        case .resetting: return "重置中"
        case .unknown: return "未知"
        @unknown default: return "未知"
        }
    }
}

// MARK: - CBCentralManagerDelegate

extension BLESession: CBCentralManagerDelegate {

    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        log("蓝牙状态：\(stateName(central.state))")
        if central.state == .poweredOn, pendingScan {
            pendingScan = false
            startScan()
            return
        }
        if central.state != .poweredOn {
            isScanning = false
            status = .disconnected
        }
    }

    func centralManager(_ central: CBCentralManager,
                        didDiscover peripheral: CBPeripheral,
                        advertisementData: [String: Any],
                        rssi RSSI: NSNumber) {
        let name = peripheral.name
            ?? (advertisementData[CBAdvertisementDataLocalNameKey] as? String)
            ?? "未命名设备"
        if let nameFilter, !nameFilter(name) { return }

        let services = (advertisementData[CBAdvertisementDataServiceUUIDsKey] as? [CBUUID]) ?? []
        let summary = services.map { $0.uuidString }.joined(separator: ",")
        known[peripheral.identifier] = peripheral

        let item = DiscoveredDevice(id: peripheral.identifier,
                                    name: name,
                                    rssi: RSSI.intValue,
                                    serviceSummary: summary)
        if let i = discovered.firstIndex(where: { $0.id == item.id }) {
            discovered[i] = item
        } else {
            discovered.append(item)
            discovered.sort { $0.rssi > $1.rssi }
        }
    }

    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        connectTimeout?.cancel()
        log("已连接 \(peripheral.name ?? "")，发现服务中…")
        connectedName = peripheral.name
        peripheral.delegate = self
        peripheral.discoverServices(nil)
    }

    func centralManager(_ central: CBCentralManager,
                        didFailToConnect peripheral: CBPeripheral,
                        error: Error?) {
        connectTimeout?.cancel()
        status = .failed(error?.localizedDescription ?? "连接失败")
        log("连接失败：\(error?.localizedDescription ?? "未知错误")")
    }

    func centralManager(_ central: CBCentralManager,
                        didDisconnectPeripheral peripheral: CBPeripheral,
                        error: Error?) {
        let reason = error?.localizedDescription
        log("连接断开\(reason.map { "：\($0)" } ?? "")")
        status = .disconnected
        connectedName = nil
        writeChar = nil
        notifyChars.removeAll()
        didFinishDiscovery = false
        onDisconnect?(reason)
        if autoReconnect, target?.identifier == peripheral.identifier, central.state == .poweredOn {
            log("2 秒后尝试重连…")
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in
                guard let self, self.autoReconnect, let target = self.target else { return }
                self.status = .connecting
                central.connect(target, options: nil)
            }
        }
    }
}

// MARK: - CBPeripheralDelegate

extension BLESession: CBPeripheralDelegate {

    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        if let error {
            log("发现服务失败：\(error.localizedDescription)")
            status = .failed(error.localizedDescription)
            return
        }
        guard let services = peripheral.services, !services.isEmpty else {
            log("没有发现任何服务")
            status = .failed("没有发现服务")
            return
        }
        expectedServiceCount = services.count
        discoveredServiceCount = 0
        for service in services {
            peripheral.discoverCharacteristics(nil, for: service)
        }
    }

    func peripheral(_ peripheral: CBPeripheral,
                    didDiscoverCharacteristicsFor service: CBService,
                    error: Error?) {
        if let error {
            log("发现特征失败：\(error.localizedDescription)")
        }
        discoveredServiceCount += 1

        let chars = service.characteristics ?? []
        log("服务 \(service.uuid.uuidString)：\(chars.map { $0.uuid.uuidString }.joined(separator: ", "))")

        for char in chars {
            if char.properties.contains(.notify) || char.properties.contains(.indicate) {
                if !notifyChars.contains(where: { $0.uuid == char.uuid }) {
                    notifyChars.append(char)
                }
                peripheral.setNotifyValue(true, for: char)
            }
            if (char.properties.contains(.writeWithoutResponse) || char.properties.contains(.write))
                && writeChar == nil {
                writeChar = char
            }
        }

        rebuildProfile(peripheral)
        mtu = peripheral.maximumWriteValueLength(for: .withoutResponse)

        if discoveredServiceCount >= expectedServiceCount, !didFinishDiscovery {
            finishDiscovery(peripheral)
        }
    }

    func peripheral(_ peripheral: CBPeripheral,
                    didUpdateValueFor characteristic: CBCharacteristic,
                    error: Error?) {
        if let error {
            log("接收失败：\(error.localizedDescription)")
            return
        }
        guard let data = characteristic.value else { return }
        onData?(data)
    }

    func peripheral(_ peripheral: CBPeripheral,
                    didUpdateNotificationStateFor characteristic: CBCharacteristic,
                    error: Error?) {
        if let error {
            log("订阅 \(characteristic.uuid.uuidString) 失败：\(error.localizedDescription)")
        }
    }

    private func rebuildProfile(_ peripheral: CBPeripheral) {
        var lines: [String] = []
        for service in peripheral.services ?? [] {
            let chars = (service.characteristics ?? []).map { c -> String in
                var flags: [String] = []
                if c.properties.contains(.read) { flags.append("r") }
                if c.properties.contains(.write) { flags.append("w") }
                if c.properties.contains(.writeWithoutResponse) { flags.append("wn") }
                if c.properties.contains(.notify) { flags.append("n") }
                if c.properties.contains(.indicate) { flags.append("i") }
                return "\(c.uuid.uuidString)[\(flags.joined(separator: "|"))]"
            }
            lines.append("\(service.uuid.uuidString) → \(chars.joined(separator: ", "))")
        }
        profile = lines.joined(separator: "\n")
        onProfile?(profile)
    }

    private func finishDiscovery(_ peripheral: CBPeripheral) {
        didFinishDiscovery = true
        if writeChar == nil {
            status = .failed("设备没有可写特征")
            log("没有可写特征，无法控制该设备")
            return
        }
        status = .connected
        log("连接就绪，写入特征 \(writeChar?.uuid.uuidString ?? "?")，MTU \(mtu)")
        onConnect?()
    }
}
