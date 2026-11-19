import Foundation

/// 本地缓存：保存“合并设备 / 隐藏设备”之前的基础会话，启动时先显示缓存再刷新。
struct SessionCache: Codable {
    static let currentVersion = 2

    var version: Int = SessionCache.currentVersion
    var sessions: [WearSession]
    var devices: [String: HeadphoneDevice]
    var updatedAt: Date
    var source: DataSourceKind
    var mergeGapMinutes: Int

    private static var url: URL {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("sessions-cache-v\(currentVersion).json")
    }

    static func load() -> SessionCache? {
        guard let data = try? Data(contentsOf: url),
              let cache = try? JSONDecoder().decode(SessionCache.self, from: data),
              cache.version == currentVersion else { return nil }
        return cache
    }

    func save() {
        guard let data = try? JSONEncoder().encode(self) else { return }
        try? data.write(to: Self.url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    }

    static func clear() {
        try? FileManager.default.removeItem(at: url)
    }
}
