import Foundation
import Observation

/// 后台计算的结果
struct DerivedData: Sendable {
    var sessions: [WearSession]
    var devices: [String: HeadphoneDevice]
    var engine: StatsEngine
    var allDevicesEngine: StatsEngine
    var records: PersonalRecords
}

@MainActor
@Observable
final class UsageStore {
    enum LoadState: Equatable {
        case idle, loading, loaded, failed(String)
    }

    // MARK: Published data

    /// 经过“合并设备 / 隐藏设备”处理后的全部会话（不受筛选影响）
    private(set) var allSessions: [WearSession] = []
    /// 可见设备（未被合并到其他设备、未隐藏）
    private(set) var devices: [String: HeadphoneDevice] = [:]
    /// 读取到过的所有设备（包括已隐藏、已合并的）
    private(set) var knownDevices: [String: HeadphoneDevice] = [:]
    private(set) var state: LoadState = .idle
    private(set) var lastUpdated: Date?
    /// 受筛选影响的统计
    private(set) var engine = StatsEngine(sessions: [])
    /// 不受筛选影响的统计（设备页使用）
    private(set) var allDevicesEngine = StatsEngine(sessions: [])
    private(set) var records = PersonalRecords()
    /// 是否已经有过一次可用的数据（缓存或读取）
    private(set) var hasData = false

    // MARK: Internal state

    @ObservationIgnored private var rawSamples: [RawSample] = []
    @ObservationIgnored private var baseSessions: [WearSession] = []
    @ObservationIgnored private let health = HealthKitService()
    @ObservationIgnored private var reloadTask: Task<Void, Never>?
    @ObservationIgnored private var deriveGeneration = 0
    @ObservationIgnored private var lastFetch: Date?
    @ObservationIgnored private var loadingSource: DataSourceKind?
    @ObservationIgnored private var reloadToken = 0
    @ObservationIgnored private var isObservingHealth = false
    @ObservationIgnored private let defaults = UserDefaults.standard

    private enum Keys {
        static let source = "dataSource", gap = "mergeGapMinutes", filter = "deviceFilter", aliases = "deviceAliases"
        static let hidden = "hiddenDevices", merges = "deviceMerges", onboarded = "hasOnboarded"
    }

    // MARK: Settings (persisted)

    var dataSource: DataSourceKind {
        didSet {
            guard oldValue != dataSource else { return }
            defaults.set(dataSource.rawValue, forKey: Keys.source)
            rawSamples = []
            baseSessions = []
            knownDevices = [:]
            hasData = false
            Task { await derive(); await reload(force: true) }
        }
    }

    var mergeGapMinutes: Int {
        didSet {
            guard oldValue != mergeGapMinutes else { return }
            defaults.set(mergeGapMinutes, forKey: Keys.gap)
            Task { await regroup() }
        }
    }

    /// 空集合 = 全部耳机
    var selectedDeviceIDs: Set<String> {
        didSet {
            guard oldValue != selectedDeviceIDs else { return }
            defaults.set(Array(selectedDeviceIDs), forKey: Keys.filter)
            Task { await derive() }
        }
    }

    var hasOnboarded: Bool {
        didSet { defaults.set(hasOnboarded, forKey: Keys.onboarded) }
    }

    private(set) var aliases: [String: String]
    private(set) var hiddenDeviceIDs: Set<String>
    /// 被合并的设备 -> 合并目标
    private(set) var mergeTargets: [String: String]

    // MARK: Init

    init() {
        let d = UserDefaults.standard
        dataSource = DataSourceKind(rawValue: d.string(forKey: Keys.source) ?? "") ?? .health
        let gap = d.integer(forKey: Keys.gap)
        mergeGapMinutes = gap > 0 ? gap : 5
        selectedDeviceIDs = Set(d.stringArray(forKey: Keys.filter) ?? [])
        aliases = (d.dictionary(forKey: Keys.aliases) as? [String: String]) ?? [:]
        hiddenDeviceIDs = Set(d.stringArray(forKey: Keys.hidden) ?? [])
        mergeTargets = (d.dictionary(forKey: Keys.merges) as? [String: String]) ?? [:]
        hasOnboarded = d.bool(forKey: Keys.onboarded)

        if let cache = SessionCache.load(), cache.source == dataSource, cache.mergeGapMinutes == mergeGapMinutes {
            baseSessions = cache.sessions
            knownDevices = cache.devices
            lastUpdated = cache.updatedAt
            hasData = true
            Task { await derive() }
        }
    }

    // MARK: Queries

    var healthAvailable: Bool { health.isAvailable }
    var isFiltered: Bool { !selectedDeviceIDs.isEmpty }
    var isLoading: Bool { state == .loading }

    /// 可见设备，按累计时长降序
    var sortedDevices: [HeadphoneDevice] {
        let totals = Dictionary(uniqueKeysWithValues: allDevicesEngine.deviceTotals().map { ($0.deviceID, $0.duration) })
        return devices.values.sorted {
            let a = totals[$0.id] ?? 0, b = totals[$1.id] ?? 0
            return a != b ? a > b : displayName(for: $0.id) < displayName(for: $1.id)
        }
    }

    var airPodsDeviceIDs: Set<String> {
        Set(devices.values.filter { $0.kind.isAirPods }.map(\.id))
    }

    func displayName(for deviceID: String) -> String {
        if let alias = aliases[deviceID], !alias.isEmpty { return alias }
        return knownDevices[deviceID]?.rawName ?? "未知耳机"
    }

    func kind(for deviceID: String) -> DeviceKind {
        knownDevices[deviceID]?.kind ?? .other
    }

    /// 合并链的最终目标
    func resolvedID(_ id: String) -> String {
        Self.resolve(id, merges: mergeTargets, known: knownDevices)
    }

    /// 合并到指定设备的其他设备
    func mergedSources(into target: String) -> [String] {
        mergeTargets.keys.filter { resolvedID($0) == target && $0 != target }.sorted()
    }

    // MARK: Device management

    func setAlias(_ name: String, for deviceID: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        aliases[deviceID] = trimmed.isEmpty ? nil : trimmed
        defaults.set(aliases, forKey: Keys.aliases)
    }

    func setHidden(_ hidden: Bool, for deviceID: String) {
        if hidden { hiddenDeviceIDs.insert(deviceID) } else { hiddenDeviceIDs.remove(deviceID) }
        defaults.set(Array(hiddenDeviceIDs), forKey: Keys.hidden)
        if hidden, selectedDeviceIDs.contains(deviceID) { selectedDeviceIDs.remove(deviceID) }
        Task { await derive() }
    }

    /// 把 source 合并到 target；会拒绝形成环的合并
    @discardableResult
    func merge(_ source: String, into target: String) -> Bool {
        guard source != target, resolvedID(target) != source else { return false }
        mergeTargets[source] = target
        defaults.set(mergeTargets, forKey: Keys.merges)
        if selectedDeviceIDs.contains(source) {
            selectedDeviceIDs.remove(source)
            selectedDeviceIDs.insert(resolvedID(target))
        }
        Task { await derive() }
        return true
    }

    func unmerge(_ source: String) {
        mergeTargets[source] = nil
        defaults.set(mergeTargets, forKey: Keys.merges)
        Task { await derive() }
    }

    func resetDeviceCustomizations() {
        aliases = [:]
        hiddenDeviceIDs = []
        mergeTargets = [:]
        defaults.removeObject(forKey: Keys.aliases)
        defaults.removeObject(forKey: Keys.hidden)
        defaults.removeObject(forKey: Keys.merges)
        selectedDeviceIDs = []
        Task { await derive() }
    }

    func clearCacheAndReload() async {
        SessionCache.clear()
        rawSamples = []
        baseSessions = []
        hasData = false
        await derive()
        await reload(force: true)
    }

    func completeOnboarding(using source: DataSourceKind) {
        hasOnboarded = true
        if dataSource == source {
            Task { await reload(force: true) }
        } else {
            dataSource = source   // didSet 会触发读取
        }
    }

    // MARK: Loading

    /// 读取数据。同一时间只会有一次读取；`force == false` 时 60 秒内不重复读取。
    func reload(force: Bool = true) async {
        while let running = reloadTask {
            let token = reloadToken
            await running.value
            if reloadToken == token { reloadTask = nil }   // 这个任务已经结束
            // 正在进行的读取已经覆盖当前数据来源，直接复用结果
            if loadingSource == dataSource { return }
        }
        if !force, let last = lastFetch, Date.now.timeIntervalSince(last) < 60 { return }

        reloadToken += 1
        let token = reloadToken
        let task = Task { await performReload() }
        reloadTask = task
        await task.value
        if reloadToken == token { reloadTask = nil }
    }

    private func performReload() async {
        let source = dataSource
        loadingSource = source
        state = .loading
        do {
            let samples: [RawSample]
            switch source {
            case .demo:
                samples = await Task.detached(priority: .userInitiated) { DemoDataGenerator.samples() }.value
            case .health:
                try await health.requestAuthorization()
                samples = try await health.fetchSamples()
                startObservingHealth()
            }
            guard source == dataSource else {
                // 读取期间切换了数据来源，交给下一次读取
                loadingSource = nil
                state = .idle
                return
            }
            rawSamples = samples
            lastFetch = .now
            await rebuildBase()
            state = .loaded
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    /// 合并间隔变化：有原始样本就直接重算，否则重新读取
    private func regroup() async {
        if rawSamples.isEmpty {
            await reload(force: true)
        } else {
            await rebuildBase()
        }
    }

    private func rebuildBase() async {
        let samples = rawSamples
        let gapMinutes = mergeGapMinutes
        let source = dataSource
        let built = await Task.detached(priority: .userInitiated) {
            (SessionBuilder.build(from: samples, mergeGap: TimeInterval(gapMinutes * 60)),
             SessionBuilder.devices(from: samples))
        }.value
        // 读取期间用户切换了数据来源，丢弃结果
        guard source == dataSource else { return }

        baseSessions = built.0
        knownDevices = built.1
        let updated = Date.now
        lastUpdated = updated
        hasData = true
        await derive()

        let cache = SessionCache(sessions: built.0, devices: built.1, updatedAt: updated,
                                 source: source, mergeGapMinutes: gapMinutes)
        Task.detached(priority: .utility) { cache.save() }
    }

    private func startObservingHealth() {
        guard !isObservingHealth else { return }
        isObservingHealth = true
        health.observeChanges { [weak self] in
            Task { @MainActor [weak self] in
                await self?.reload(force: false)
            }
        }
    }

    // MARK: Derivation

    private func derive() async {
        deriveGeneration += 1
        let generation = deriveGeneration
        let base = baseSessions, known = knownDevices, merges = mergeTargets
        let hidden = hiddenDeviceIDs, filter = selectedDeviceIDs
        let gap = TimeInterval(mergeGapMinutes * 60)

        let output = await Task.detached(priority: .userInitiated) {
            UsageStore.process(base: base, known: known, merges: merges, hidden: hidden, filter: filter, mergeGap: gap)
        }.value

        guard generation == deriveGeneration else { return }   // 已有更新的计算
        allSessions = output.sessions
        devices = output.devices
        engine = output.engine
        allDevicesEngine = output.allDevicesEngine
        records = output.records
    }

    nonisolated static func resolve(_ id: String, merges: [String: String], known: [String: HeadphoneDevice]) -> String {
        var current = id
        var steps = 0
        while let next = merges[current], next != current, known[next] != nil, steps < 16 {
            current = next
            steps += 1
        }
        return current
    }

    /// 纯函数：基础会话 -> 合并 / 隐藏 / 筛选 -> 统计
    nonisolated static func process(base: [WearSession],
                                    known: [String: HeadphoneDevice],
                                    merges: [String: String],
                                    hidden: Set<String>,
                                    filter: Set<String>,
                                    mergeGap: TimeInterval) -> DerivedData {
        var remapped: [WearSession] = []
        remapped.reserveCapacity(base.count)
        var anyMerged = false
        for var s in base {
            let target = resolve(s.deviceID, merges: merges, known: known)
            if target != s.deviceID { anyMerged = true; s.deviceID = target }
            if !hidden.contains(target) { remapped.append(s) }
        }
        let sessions = anyMerged ? SessionBuilder.coalesce(remapped, mergeGap: mergeGap) : remapped

        let devices = known.filter { id, _ in
            resolve(id, merges: merges, known: known) == id && !hidden.contains(id)
        }

        let all = StatsEngine(sessions: sessions)
        let validFilter = filter.filter { devices[$0] != nil }
        let filtered = validFilter.isEmpty ? all : StatsEngine(sessions: sessions.filter { validFilter.contains($0.deviceID) })
        return DerivedData(sessions: sessions, devices: devices, engine: filtered,
                           allDevicesEngine: all, records: filtered.records())
    }
}
