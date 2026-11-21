import Foundation
import Combine

// MARK: - BLE 设备描述加载

/// 从 App 包内 Resources/Profiles/*.json 与 Documents/Profiles/*.json 读取设备描述。
/// 用户可以直接把新设备的 JSON 丢进 Documents（通过"文件"App 共享），无需重新编译。
final class ProfileStore: ObservableObject {

    @Published private(set) var profiles: [DeviceProfile] = []
    @Published private(set) var issues: [String] = []

    init() {
        reload()
    }

    func reload() {
        var loaded: [String: DeviceProfile] = [:]
        var problems: [String] = []

        for url in Self.profileURLs() {
            do {
                let data = try Data(contentsOf: url)
                let profile = try JSONDecoder().decode(DeviceProfile.self, from: data)
                let validation = profile.validate()
                if !validation.isEmpty {
                    problems.append("\(url.lastPathComponent)：\(validation.joined(separator: "；"))")
                    continue
                }
                loaded[profile.id] = profile
            } catch {
                problems.append("\(url.lastPathComponent)：解析失败 \(error.localizedDescription)")
            }
        }

        profiles = loaded.values.sorted { $0.name < $1.name }
        issues = problems
    }

    private static func profileURLs() -> [URL] {
        var urls: [URL] = []
        if let bundled = Bundle.main.urls(forResourcesWithExtension: "json", subdirectory: "Profiles") {
            urls.append(contentsOf: bundled)
        } else if let bundled = Bundle.main.urls(forResourcesWithExtension: "json", subdirectory: nil) {
            urls.append(contentsOf: bundled.filter { $0.lastPathComponent.contains("profile") || $0.lastPathComponent.contains("mini") })
        }

        if let docs = try? FileManager.default.url(for: .documentDirectory,
                                                   in: .userDomainMask,
                                                   appropriateFor: nil,
                                                   create: true) {
            let dir = docs.appendingPathComponent("Profiles", isDirectory: true)
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            if let files = try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil) {
                urls.append(contentsOf: files.filter { $0.pathExtension.lowercased() == "json" })
            }
        }
        return urls
    }

    func profile(id: DeviceProfileID) -> DeviceProfile? {
        profiles.first { $0.id == id }
    }
}
