import Foundation
import CoreBluetooth
import Combine

/// 让 iPhone 变成一台 BLE MIDI 设备，iPad 上的 KORG Module 可以直接在
/// “Bluetooth MIDI”里搜到并连接。用于方案二。
final class BLEMIDIPeripheral: NSObject, ObservableObject {

    @Published private(set) var isAdvertising = false
    @Published private(set) var subscriberCount = 0
    @Published private(set) var bluetoothState: CBManagerState = .unknown
    @Published private(set) var statusText = "未开启"
    @Published private(set) var lastPacket = "—"
    @Published private(set) var eventLog: [String] = []

    var onLog: ((String) -> Void)?

    private var manager: CBPeripheralManager?
    private var characteristic: CBMutableCharacteristic?
    private var serviceAdded = false
    private var wantAdvertising = false

    var hasSubscribers: Bool { subscriberCount > 0 }

    private func logEvent(_ text: String) {
        let stamp = Self.formatter.string(from: Date())
        eventLog.append("[\(stamp)] \(text)")
        if eventLog.count > 40 { eventLog.removeFirst(eventLog.count - 40) }
        onLog?(text)
    }

    private static let formatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss"
        return f
    }()

    func start() {
        wantAdvertising = true
        if manager == nil {
            manager = CBPeripheralManager(delegate: self, queue: .main, options: nil)
        }
        switch manager?.state {
        case .poweredOn:
            publish()
        case .unauthorized:
            statusText = "蓝牙未授权"
        case .poweredOff:
            statusText = "蓝牙已关闭"
        case .unsupported:
            statusText = "不支持蓝牙外设模式"
        default:
            statusText = "正在初始化…"
        }
    }

    /// 回前台时重新广播一次，促使 iPad 重新订阅通知。
    func refreshAdvertising() {
        guard wantAdvertising, let manager else { return }
        manager.stopAdvertising()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in
            guard let self, self.wantAdvertising else { return }
            self.publish()
        }
    }

    func stop() {
        wantAdvertising = false
        manager?.stopAdvertising()
        isAdvertising = false
        subscriberCount = 0
        statusText = "已停止"
    }

    private func publish() {
        guard let manager else { return }
        if !serviceAdded {
            let char = CBMutableCharacteristic(
                type: BLEMIDI.characteristicUUID,
                // 标准 BLE MIDI 外设的形态：notify + writeWithoutResponse。
                properties: [.notify, .writeWithoutResponse],
                value: nil,
                permissions: [.writeable]
            )
            let svc = CBMutableService(type: BLEMIDI.serviceUUID, primary: true)
            svc.characteristics = [char]
            characteristic = char
            manager.add(svc)
            serviceAdded = true
            return   // 等 didAdd 回调再开始广播
        }
        // 等 GATT 数据库稳定后再广播，避免 central 连得太快、服务还没就绪。
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
            guard let self, self.wantAdvertising, let manager = self.manager else { return }
            manager.startAdvertising([
                CBAdvertisementDataServiceUUIDsKey: [BLEMIDI.serviceUUID],
                CBAdvertisementDataLocalNameKey: "StageControl MIDI"
            ])
            self.isAdvertising = true
            self.statusText = self.subscriberCount > 0
                ? "已连接 \(self.subscriberCount) 台设备"
                : "广播中：StageControl MIDI"
            self.onLog?("BLE MIDI 外设广播已开启")
        }
    }

    /// 发送纯 MIDI 字节（内部封装成 BLE MIDI 包）。
    func send(_ midi: [UInt8]) {
        guard let manager, let char = characteristic, !midi.isEmpty else { return }
        let data = BLEMIDI.encode(midi)
        lastPacket = [UInt8](data).map { String(format: "%02X", $0) }.joined(separator: " ")
        if subscriberCount == 0 {
            statusText = "无订阅者：包没有发出"
            return
        }
        let ok = manager.updateValue(data, for: char, onSubscribedCentrals: nil)
        statusText = "已连接 \(subscriberCount) 台设备"
        if !ok {
            // 发送队列满：稍后重试一次
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.03) { [weak self] in
                guard let self, let manager = self.manager, let char = self.characteristic else { return }
                _ = manager.updateValue(data, for: char, onSubscribedCentrals: nil)
            }
        }
    }
}

extension BLEMIDIPeripheral: CBPeripheralManagerDelegate {

    func peripheralManagerDidUpdateState(_ peripheral: CBPeripheralManager) {
        bluetoothState = peripheral.state
        switch peripheral.state {
        case .poweredOn:
            if wantAdvertising { publish() }
        case .unauthorized:
            statusText = "蓝牙未授权"
        case .poweredOff:
            statusText = "蓝牙已关闭"
        default:
            break
        }
    }

    func peripheralManager(_ peripheral: CBPeripheralManager, didAdd service: CBService, error: Error?) {
        if let error {
            statusText = "添加服务失败：\(error.localizedDescription)"
            logEvent("添加服务失败：\(error.localizedDescription)")
            return
        }
        logEvent("MIDI 服务已添加")
        if wantAdvertising { publish() }
    }

    func peripheralManagerDidStartAdvertising(_ peripheral: CBPeripheralManager, error: Error?) {
        if let error {
            statusText = "广播失败：\(error.localizedDescription)"
            logEvent("广播失败：\(error.localizedDescription)")
        } else {
            logEvent("开始广播 StageControl MIDI")
        }
    }

    func peripheralManager(_ peripheral: CBPeripheralManager,
                           central: CBCentral,
                           didSubscribeTo characteristic: CBCharacteristic) {
        subscriberCount += 1
        statusText = "已连接 \(subscriberCount) 台设备"
        logEvent("订阅通知：\(central.identifier.uuidString.prefix(8))")
    }

    func peripheralManager(_ peripheral: CBPeripheralManager,
                           central: CBCentral,
                           didUnsubscribeFrom characteristic: CBCharacteristic) {
        subscriberCount = max(0, subscriberCount - 1)
        statusText = subscriberCount > 0 ? "已连接 \(subscriberCount) 台设备" : "广播中：StageControl MIDI"
        logEvent("取消订阅：\(central.identifier.uuidString.prefix(8))")
    }

    func peripheralManagerIsReady(toUpdateSubscribers peripheral: CBPeripheralManager) {
        // 发送队列恢复，无需处理
    }

    func peripheralManager(_ peripheral: CBPeripheralManager,
                           didReceiveWrite requests: [CBATTRequest]) {
        // 目前只做发送，收到写入直接确认
        for request in requests {
            peripheral.respond(to: request, withResult: .success)
        }
        logEvent("对方写入特征 \(requests.count) 次")
    }
}
