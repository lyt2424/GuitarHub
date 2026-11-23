import Foundation
import Combine

/// 本地持久化：预设库、踏板映射、设置。
/// 全部存在 Application Support/GuitarHub/store.json，随改随存（0.6 秒防抖）。
final class AppStore: ObservableObject {

    struct Settings: Codable, Hashable {
        var sparkPresetCount: Int = 4
        /// Pulze 换音色发送方式："cc127" / "cc0" / "pc"
        var presetTriggerMode: String? = nil
        var hapticsEnabled: Bool = true
        /// 召回音色时是否把本地保存的模块状态整包推给设备。
        var pushFullStateOnRecall: Bool = true
        /// 为 true 时，设备状态变化也会写回本地预设库（Spark 的有效状态）。
        var autoCapture: Bool = true
        var showDebugLog: Bool = false

        static let `default` = Settings()
    }

    struct DeviceLibrary: Codable, Hashable {
        var snapshots: [Int: AmpSnapshot] = [:]
        var lastUsedPreset: Int = 0
        /// 用户自己起的显示名（中文），优先级高于设备上报的名字。
        var aliases: [Int: String] = [:]
        /// 设备当前音色组里实际有几个音色（Pulze 这类不能读回的设备需要手动告诉 App）。
        var presetCount: Int?

        enum CodingKeys: String, CodingKey { case snapshots, lastUsedPreset, aliases, presetCount }

        init() {}

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            snapshots = (try? c.decode([Int: AmpSnapshot].self, forKey: .snapshots)) ?? [:]
            lastUsedPreset = (try? c.decode(Int.self, forKey: .lastUsedPreset)) ?? 0
            aliases = (try? c.decode([Int: String].self, forKey: .aliases)) ?? [:]
            presetCount = try? c.decodeIfPresent(Int.self, forKey: .presetCount)
        }
    }

    struct StoreData: Codable {
        var settings: Settings = .default
        /// key = DeviceProfileID
        var libraries: [String: DeviceLibrary] = [:]
        var pedalBanks: [PedalBank] = []
        var activeBankID: UUID?
    }

    @Published var data: StoreData {
        didSet { scheduleSave() }
    }

    private let fileURL: URL
    private var saveWorkItem: DispatchWorkItem?

    init(fileURL: URL? = nil) {
        let fm = FileManager.default
        let base = (try? fm.url(for: .applicationSupportDirectory,
                                in: .userDomainMask,
                                appropriateFor: nil,
                                create: true)) ?? fm.temporaryDirectory
        let dir = base.appendingPathComponent("GuitarHub", isDirectory: true)
        try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        self.fileURL = fileURL ?? dir.appendingPathComponent("store.json")
        self.data = Self.load(from: self.fileURL)
        seedIfNeeded()
    }

    // MARK: - 加载 / 保存

    private static func load(from url: URL) -> StoreData {
        guard let raw = try? Data(contentsOf: url) else { return StoreData() }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        if let decoded = try? decoder.decode(StoreData.self, from: raw) {
            return decoded
        }
        // 结构升级失败时保留一份备份，避免用户数据被静默清空
        let backup = url.deletingPathExtension().appendingPathExtension("broken.json")
        try? FileManager.default.copyItem(at: url, to: backup)
        return StoreData()
    }

    private func seedIfNeeded() {
        var d = data
        var changed = false

        if d.pedalBanks.isEmpty {
            // 两套踏板组，分别对应 Spark Mini / Pulze Mini。
            let banks = [PedalBank.sparkStarter(), PedalBank.pulzeStarter()]
            d.pedalBanks = banks
            d.activeBankID = banks.first?.id
            changed = true
        }
        if d.activeBankID == nil {
            d.activeBankID = d.pedalBanks.first?.id
            changed = true
        }
        if changed {
            data = d
            saveNow()
        }
    }

    private func scheduleSave() {
        saveWorkItem?.cancel()
        let item = DispatchWorkItem { [weak self] in self?.saveNow() }
        saveWorkItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6, execute: item)
    }

    func saveNow() {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        guard let raw = try? encoder.encode(data) else { return }
        try? raw.write(to: fileURL, options: .atomic)
    }

    // MARK: - 设备预设库

    func library(_ kind: DeviceProfileID) -> DeviceLibrary {
        data.libraries[kind] ?? DeviceLibrary()
    }

    func snapshot(_ kind: DeviceProfileID, index: Int) -> AmpSnapshot? {
        library(kind).snapshots[index]
    }

    func save(snapshot: AmpSnapshot, for kind: DeviceProfileID) {
        var lib = library(kind)
        lib.snapshots[snapshot.presetIndex] = snapshot
        data.libraries[kind] = lib
    }

    func save(modules: [ModuleState], name: String, index: Int, for kind: DeviceProfileID) {
        guard !modules.isEmpty else { return }
        let snap = AmpSnapshot(presetIndex: index,
                               name: name,
                               modules: modules,
                               updatedAt: Date())
        save(snapshot: snap, for: kind)
    }

    func alias(_ kind: DeviceProfileID, index: Int) -> String? {
        let value = library(kind).aliases[index]?.trimmingCharacters(in: .whitespacesAndNewlines)
        return (value?.isEmpty ?? true) ? nil : value
    }

    func setAlias(_ name: String?, for kind: DeviceProfileID, index: Int) {
        var lib = library(kind)
        let trimmed = name?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let trimmed, !trimmed.isEmpty {
            lib.aliases[index] = trimmed
        } else {
            lib.aliases.removeValue(forKey: index)
        }
        data.libraries[kind] = lib
    }

    func setPresetCount(_ count: Int, for kind: DeviceProfileID) {
        var lib = library(kind)
        lib.presetCount = max(1, min(128, count))
        data.libraries[kind] = lib
    }

    func setLastUsedPreset(_ index: Int, for kind: DeviceProfileID) {
        var lib = library(kind)
        lib.lastUsedPreset = index
        data.libraries[kind] = lib
    }

    // MARK: - 踏板

    var activeBank: PedalBank? {
        guard let id = data.activeBankID else { return data.pedalBanks.first }
        return data.pedalBanks.first { $0.id == id } ?? data.pedalBanks.first
    }

    func updateBank(_ bank: PedalBank) {
        if let index = data.pedalBanks.firstIndex(where: { $0.id == bank.id }) {
            data.pedalBanks[index] = bank
        } else {
            data.pedalBanks.append(bank)
        }
    }
}
