import Foundation
import Combine

/// 蓝牙 MIDI 踏板：直接作为 BLE 中心连接踏板的 BLE MIDI 服务，
/// 这样踏板消息只会进本 App，由 App 决定转发给音箱还是 KORG Module，
/// 避免"系统级 BLE MIDI + App 直连"造成同一条消息触发两次。
final class BLEMIDIPedal: ObservableObject {

    let session = BLESession()

    @Published private(set) var status: ConnectionStatus = .disconnected
    @Published private(set) var candidates: [DiscoveredDevice] = []
    @Published private(set) var connectedName: String?
    @Published private(set) var isScanning = false

    var onMessage: ((MIDIMessage) -> Void)?
    var onLog: ((String) -> Void)?

    private let parser = MIDIStreamParser()
    private var bag = Set<AnyCancellable>()

    init() {
        session.serviceFilter = [BLEMIDI.serviceUUID]
        session.onData = { [weak self] data in
            guard let self else { return }
            let bytes = BLEMIDI.decode(data)
            guard !bytes.isEmpty else { return }
            for message in self.parser.feed(bytes) {
                self.onMessage?(message)
            }
        }
        session.onLog = { [weak self] text in self?.onLog?(text) }

        session.$status.receive(on: RunLoop.main)
            .sink { [weak self] in self?.status = $0 }.store(in: &bag)
        session.$discovered.receive(on: RunLoop.main)
            .sink { [weak self] in self?.candidates = $0 }.store(in: &bag)
        session.$connectedName.receive(on: RunLoop.main)
            .sink { [weak self] in self?.connectedName = $0 }.store(in: &bag)
        session.$isScanning.receive(on: RunLoop.main)
            .sink { [weak self] in self?.isScanning = $0 }.store(in: &bag)
    }

    func startScan() { session.startScan() }
    func stopScan() { session.stopScan() }
    func disconnect() { session.disconnect() }

    func connect(to id: UUID) {
        UserDefaults.standard.set(id.uuidString, forKey: "last.pedal")
        session.connect(to: id)
    }

    func connectLast() {
        if let raw = UserDefaults.standard.string(forKey: "last.pedal"),
           let uuid = UUID(uuidString: raw) {
            session.connect(to: uuid)
        } else {
            startScan()
        }
    }
}
