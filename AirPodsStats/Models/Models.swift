import Foundation

/// 一条来自健康 App 的原始耳机音频样本（或示例数据样本）。
struct RawSample: Hashable, Sendable {
    var deviceID: String
    var deviceName: String
    var deviceModel: String?
    var manufacturer: String? = nil
    var start: Date
    var end: Date
    /// 耳机音频级别 dB(A)
    var level: Double? = nil
}

/// 合并后的一次连续佩戴。
struct WearSession: Identifiable, Codable, Hashable, Sendable {
    var id: UUID = UUID()
    var deviceID: String
    var start: Date
    var end: Date
    /// 本次佩戴期间按时长加权的平均音量 dB(A)
    var averageLevel: Double? = nil

    var duration: TimeInterval { max(0, end.timeIntervalSince(start)) }
}

/// 一副耳机。
struct HeadphoneDevice: Identifiable, Codable, Hashable, Sendable {
    var id: String
    var rawName: String
    var model: String?
    var manufacturer: String? = nil

    var kind: DeviceKind { DeviceKind.guess(name: rawName, model: model) }
}

enum DeviceKind: String, Codable, Sendable {
    case airPods, airPodsPro, airPodsMax, beats, wired, other

    static func guess(name: String, model: String?) -> DeviceKind {
        let text = (name + " " + (model ?? "")).lowercased()
        if text.contains("max") && text.contains("airpods") { return .airPodsMax }
        if text.contains("airpods") && text.contains("pro") { return .airPodsPro }
        if text.contains("airpods") { return .airPods }
        if text.contains("beats") || text.contains("powerbeats") { return .beats }
        if text.contains("wired") || text.contains("有线") || text.contains("earpods") { return .wired }
        return .other
    }

    var symbol: String {
        switch self {
        case .airPods: return "airpods"
        case .airPodsPro: return "airpodspro"
        case .airPodsMax: return "airpodsmax"
        case .beats: return "beats.headphones"
        case .wired: return "earpods"
        case .other: return "headphones"
        }
    }

    var caseSymbol: String {
        switch self {
        case .airPods: return "airpods.chargingcase"
        case .airPodsPro: return "airpodspro.chargingcase.wireless"
        case .airPodsMax: return "airpodsmax"
        case .beats: return "beats.headphones"
        case .wired: return "earpods"
        case .other: return "headphones"
        }
    }

    var isAirPods: Bool { self == .airPods || self == .airPodsPro || self == .airPodsMax }
}

enum DataSourceKind: String, Codable, CaseIterable, Identifiable, Sendable {
    case health, demo
    var id: String { rawValue }
    var title: String {
        switch self {
        case .health: return "健康 App"
        case .demo: return "示例数据"
        }
    }
}

enum PeriodKind: String, CaseIterable, Identifiable, Sendable {
    case week, month, year, all
    var id: String { rawValue }
    var title: String {
        switch self {
        case .week: return "周"
        case .month: return "月"
        case .year: return "年"
        case .all: return "总共"
        }
    }
    /// “较前一周 / 较前一月 / 较前一年”
    var comparisonTitle: String? {
        switch self {
        case .week: return "较前一周"
        case .month: return "较前一月"
        case .year: return "较前一年"
        case .all: return nil
        }
    }
}

/// 设备页的时间范围（右上角“近7天 ⌄”）
enum DevicePeriod: String, CaseIterable, Identifiable, Sendable {
    case last7, last30, thisWeek, thisMonth, all
    var id: String { rawValue }
    var title: String {
        switch self {
        case .last7: return "近7天"
        case .last30: return "近30天"
        case .thisWeek: return "本周"
        case .thisMonth: return "本月"
        case .all: return "全部"
        }
    }
    var totalCaption: String {
        switch self {
        case .last7: return "近 7 天总佩戴时长"
        case .last30: return "近 30 天总佩戴时长"
        case .thisWeek: return "本周总佩戴时长"
        case .thisMonth: return "本月总佩戴时长"
        case .all: return "累计总佩戴时长"
        }
    }
}
