import Foundation
import Observation

@MainActor
@Observable
final class UsageStore {
    enum LoadState: Equatable {
        case idle, loading, loaded, failed(String)
    }

    // MARK: Data
    private(set) var allSessions: [WearSession] = []
    private(set) var devices: [String: HeadphoneDevice] = [:]
    private(set) var state: LoadState = .idle
    private(set) var lastUpdated: Date?
    private(set) var engine = StatsEngine(sessions: [])
    private(set) var allDevicesEngine = StatsEngine(sessions: [])

    private var rawSamples: [RawSample] = []
    private let health = HealthKitService()

    // MARK: Settings (persisted)
    var dataSource: DataSourceKind {
        didSet { defaults.set(dataSource.rawValue, forKey: Keys.source); Task { await reload() } }
    }
    var mergeGapMinutes: Int {
        didSet { defaults.set(mergeGapMinutes, forKey: Keys.gap); rebuildFromRaw() }
    }
    /// 空集合 = 全部耳机
    var selectedDeviceIDs: Set<String> {
        didSet { defaults.set(Array(selectedDeviceIDs), forKey: Keys.filter); recomputeEngine() }
    }
    private(set) var aliases: [String: String]

    private let defaults = UserDefaults.standard
    private enum Keys {
        static let source = "dataSource", gap = "mergeGapMinutes", filter = "deviceFilter", aliases = "deviceAliases"
    }

    init() {
        let d = UserDefaults.standard
        dataSource = DataSourceKind(rawValue: d.string(forKey: Keys.source) ?? "") ?? .health
        let gap = d.integer(forKey: Keys.gap)
        mergeGapMinutes = gap > 0 ? gap : 5
        selectedDeviceIDs = Set(d.stringArray(forKey: Keys.filter) ?? [])
        aliases = (d.dictionary(forKey: Keys.aliases) as? [String: String]) ?? [:]

        if let cache = SessionCache.load(), cache.source == dataSource {
            allSessions = cache.sessions
            devices = cache.devices
            lastUpdated = cache.updatedAt
            recomputeEngine()
        }
    }

    // MARK: Derived
    var healthAvailable: Bool { health.isAvailable }
    var isFiltered: Bool { !selectedDeviceIDs.isEmpty }
    var sortedDevices: [HeadphoneDevice] {
        let totals = Dictionary(uniqueKeysWithValues: allDevicesEngine.deviceTotals().map { ($0.deviceID, $0.duration) })
        return devices.values.sorted { (totals[$0.id] ?? 0) > (totals[$1.id] ?? 0) }
    }

    func displayName(for deviceID: String) -> String {
        if let alias = aliases[deviceID], !alias.isEmpty { return alias }
        return devices[deviceID]?.rawName ?? "未知耳机"
    }

    func kind(for deviceID: String) -> DeviceKind {
        devices[deviceID]?.kind ?? .other
    }

    func setAlias(_ name: String, for deviceID: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        aliases[deviceID] = trimmed.isEmpty ? nil : trimmed
        defaults.set(aliases, forKey: Keys.aliases)
    }

    // MARK: Loading
    func reload() async {
        state = .loading
        do {
            switch dataSource {
            case .demo:
                rawSamples = DemoDataGenerator.samples()
            case .health:
                try await health.requestAuthorization()
                rawSamples = try await health.fetchSamples()
            }
            devices = SessionBuilder.devices(from: rawSamples)
            rebuildFromRaw()
            state = .loaded
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    private func rebuildFromRaw() {
        guard !rawSamples.isEmpty || state == .loading else {
            // 没有原始样本（例如只加载了缓存），重新读取
            Task { await reload() }
            return
        }
        let samples = rawSamples
        let gap = TimeInterval(mergeGapMinutes * 60)
        allSessions = SessionBuilder.build(from: samples, mergeGap: gap)
        lastUpdated = .now
        recomputeEngine()
        SessionCache(sessions: allSessions, devices: devices, updatedAt: lastUpdated ?? .now, source: dataSource).save()
    }

    private func recomputeEngine() {
        // 过滤掉已经不存在的设备
        let valid = selectedDeviceIDs.filter { devices[$0] != nil }
        let filtered = valid.isEmpty ? allSessions : allSessions.filter { valid.contains($0.deviceID) }
        engine = StatsEngine(sessions: filtered)
        allDevicesEngine = valid.isEmpty ? engine : StatsEngine(sessions: allSessions)
    }
}
