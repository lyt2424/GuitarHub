import Foundation
import CoreBluetooth
import Combine

/// 全局装配：设备与踏板路由。
///
/// 启动页直接列出设备（Spark Mini / Pulze Mini），点哪台进哪台，同一时刻只连这一台。
final class DeviceHub: ObservableObject {

    let store: AppStore
    let profiles: ProfileStore
    let pedal: PedalRouter
    let pedalInput: BLEMIDIPedal

    @Published private(set) var devices: [AmpDevice] = []
    @Published private(set) var mode: AppMode = .launch
    @Published private(set) var selectedDeviceID: DeviceProfileID?

    init() {
        let store = AppStore()
        let profiles = ProfileStore()
        let pedal = PedalRouter(store: store)
        let pedalInput = BLEMIDIPedal()

        self.store = store
        self.profiles = profiles
        self.pedal = pedal
        self.pedalInput = pedalInput
        self.selectedDeviceID = UserDefaults.standard.string(forKey: "selected.device")
            ?? profiles.profiles.first?.id

        buildDevices()
        ensureBanks()
        migrateBanks()
        pedal.attach(devices: devices)
        pedal.onFeedback = { [weak self] text in self?.pedal.lastEvent = text }

        pedalInput.onMessage = { [weak self] message in
            self?.pedal.handle(message, source: "蓝牙踏板")
        }
        pedalInput.onLog = { [weak self] text in self?.pedalInputLog(text) }
    }

    // MARK: - 入口

    var selectedDevice: AmpDevice? {
        selectedDeviceID.flatMap(device(id:))
    }

    var guitarDevices: [AmpDevice] { devices }

    /// 从后台回到前台：补一次自动连接。
    func onAppActive() {
        prepareAutoConnect()
    }

    /// App 启动时静默尝试一次自动连接（音箱 + 踏板）。
    func prepareAutoConnect() {
        if let device = selectedDevice,
           !device.status.isConnected, !device.status.isBusy {
            device.connectLast()
        }
        if !pedalInput.status.isConnected, !pedalInput.status.isBusy {
            pedalInput.connectLast()
        }
    }

    func enterGuitar(_ id: DeviceProfileID) {
        selectedDeviceID = id
        UserDefaults.standard.set(id, forKey: "selected.device")
        mode = .guitar
        applySelection(connect: true)
    }

    func backToLaunch() {
        mode = .launch
        applySelection(connect: false)
    }

    /// 只切换选中的设备，不主动连接（用于设备页里手动搜索/连接）。
    func selectForConnection(_ device: AmpDevice) {
        selectedDeviceID = device.profile.id
        UserDefaults.standard.set(device.profile.id, forKey: "selected.device")
        mode = .guitar
        applySelection(connect: false)
    }

    func connect(_ device: AmpDevice, to id: UUID) {
        selectForConnection(device)
        device.connect(to: id)
    }

    private func applySelection(connect: Bool) {
        let activeID = mode == .guitar ? selectedDeviceID : nil
        pedal.setActive(deviceID: activeID)

        for device in devices where device.profile.id != activeID {
            if device.status.isConnected || device.status.isBusy {
                device.disconnect()
            }
        }

        let bankName: String
        switch mode {
        case .guitar: bankName = selectedDevice?.profile.name ?? ""
        case .launch: bankName = ""
        }
        if !bankName.isEmpty,
           let bank = store.data.pedalBanks.first(where: { $0.name == bankName }) {
            store.data.activeBankID = bank.id
        }

        // 踏板单独自动重连（和音箱是两条 BLE）。
        if !pedalInput.status.isConnected, !pedalInput.status.isBusy {
            pedalInput.connectLast()
        }

        guard connect, let device = selectedDevice else { return }
        if !device.status.isConnected, !device.status.isBusy {
            device.connectLast()
        }
    }

    // MARK: - 设备

    private func buildDevices() {
        devices = profiles.profiles.map { makeDevice(profile: $0) }
    }

    /// 给每个设备配置准备一套同名踏板组；新增设备后自动出现。
    private func ensureBanks() {
        var banks = store.data.pedalBanks
        for profile in profiles.profiles where !banks.contains(where: { $0.name == profile.name }) {
            banks.append(PedalBank.ampStarter(device: profile.id, name: profile.name))
        }
        if banks.map(\.id) != store.data.pedalBanks.map(\.id) {
            store.data.pedalBanks = banks
        }
    }

    /// 旧版本把 CC20/21 绑成了别的动作；升级后一次性替换成新的默认映射。
    private func migrateBanks() {
        let key = "migration.banks.pulze.v2"
        if !UserDefaults.standard.bool(forKey: key) {
            if let index = store.data.pedalBanks.firstIndex(where: { $0.name == "Pulze Mini" }) {
                store.data.pedalBanks[index] = PedalBank.pulzeStarter()
            }
            UserDefaults.standard.set(true, forKey: key)
        }

        let sparkKey = "migration.banks.spark.v3"
        if !UserDefaults.standard.bool(forKey: sparkKey) {
            if let index = store.data.pedalBanks.firstIndex(where: { $0.name == "Spark Mini" }) {
                store.data.pedalBanks[index] = PedalBank.sparkStarter()
            }
            UserDefaults.standard.set(true, forKey: sparkKey)
        }
    }

    private func makeDevice(profile: DeviceProfile) -> AmpDevice {
        let session = BLESession()
        let transport = profile.transport

        let prefixes = transport.namePrefixes
        session.nameFilter = { name in
            guard !prefixes.isEmpty else { return true }
            return prefixes.contains { name.localizedCaseInsensitiveContains($0) }
        }
        if !transport.serviceUUIDs.isEmpty {
            session.serviceFilter = transport.serviceUUIDs.map { CBUUID(string: $0) }
        }
        if !transport.writeCharacteristic.isEmpty {
            session.writeCharacteristicUUID = CBUUID(string: transport.writeCharacteristic)
        }
        if !transport.notifyCharacteristic.isEmpty {
            session.notifyCharacteristicUUID = CBUUID(string: transport.notifyCharacteristic)
        }

        let codec: DeviceCodec
        switch transport.codec {
        case .spark:
            codec = SparkCodec(profile: profile, session: session)
        case .midiCC:
            codec = MIDICodec(profile: profile, session: session)
        case .template:
            // 模板编解码器尚未实现；先用 MIDI 编码器占位，避免静默失败。
            codec = MIDICodec(profile: profile, session: session)
        }

        return AmpDevice(profile: profile, session: session, codec: codec, store: store)
    }

    func device(id: DeviceProfileID) -> AmpDevice? {
        devices.first { $0.profile.id == id }
    }

    func reloadProfiles() {
        profiles.reload()
        buildDevices()
        ensureBanks()
        pedal.attach(devices: devices)
        applySelection(connect: false)
    }

    private func pedalInputLog(_ text: String) {
        pedal.log(text)
    }
}
