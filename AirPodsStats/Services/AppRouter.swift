import Foundation
import Observation

/// 设备页的导航目的地
enum DeviceRoute: Hashable {
    case detail(String)
    case history(String)
}

/// 跨标签页导航：例如从“单日佩戴最长”跳到那一天、从会话跳到设备详情
@MainActor
@Observable
final class AppRouter {
    enum Tab: Hashable { case today, stats, devices }

    var tab: Tab = .stats

    /// “今天”页正在查看的日期；nil 表示始终跟随今天
    var focusedDay: Date?

    var statsPeriod: PeriodKind = .year
    var statsAnchor: Date = .now
    /// 每次从别处跳到统计页时 +1，统计页据此滚动到周期图表
    private(set) var statsScrollRequest = 0

    var devicePath: [DeviceRoute] = []

    func showDay(_ day: Date) {
        let cal = Calendar.stats
        focusedDay = cal.isDateInToday(day) ? nil : cal.startOfDay(for: day)
        tab = .today
    }

    func showPeriod(_ kind: PeriodKind, containing date: Date) {
        statsPeriod = kind
        statsAnchor = date
        statsScrollRequest += 1
        tab = .stats
    }

    func showDevice(_ id: String) {
        devicePath = [.detail(id)]
        tab = .devices
    }
}
