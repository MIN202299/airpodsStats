import Foundation

/// 把上次读取并合并好的会话缓存到本地，启动时先显示缓存再刷新。
struct SessionCache: Codable {
    var sessions: [WearSession]
    var devices: [String: HeadphoneDevice]
    var updatedAt: Date
    var source: DataSourceKind

    private static var url: URL {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("sessions-cache.json")
    }

    static func load() -> SessionCache? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(SessionCache.self, from: data)
    }

    func save() {
        guard let data = try? JSONEncoder().encode(self) else { return }
        try? data.write(to: Self.url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    }

    static func clear() {
        try? FileManager.default.removeItem(at: url)
    }
}
