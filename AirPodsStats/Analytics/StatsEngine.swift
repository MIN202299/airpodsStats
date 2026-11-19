import Foundation

// MARK: - Result types

struct DayRecord: Hashable { var day: Date; var duration: TimeInterval }
struct MonthRecord: Hashable { var month: Date; var duration: TimeInterval }
struct StreakRecord: Hashable { var start: Date; var end: Date; var days: Int }
struct DeviceTotal: Hashable, Identifiable {
    var deviceID: String
    var duration: TimeInterval
    var sessionCount: Int
    var firstUsed: Date
    var lastUsed: Date
    var id: String { deviceID }
}

struct PersonalRecords {
    var bestDay: DayRecord?
    var longestSession: WearSession?
    var longestStreak: StreakRecord?
    var bestMonth: MonthRecord?
    var topDevice: DeviceTotal?
}

struct PeriodBar: Identifiable, Hashable {
    var index: Int
    var start: Date
    var end: Date
    var label: String        // 坐标轴文字，例如 “3月”
    var detailLabel: String  // 明细文字，例如 “2025 年 3 月”
    var duration: TimeInterval
    var recordedDays: Int
    var id: Int { index }
    var key: String { String(index) }
}

struct PeriodSummary {
    var kind: PeriodKind
    var interval: DateInterval
    var title: String
    var total: TimeInterval
    var previousTotal: TimeInterval?
    var bars: [PeriodBar]
    var recordedDays: Int
    var totalDays: Int
    var sessionCount: Int
    var bestDay: DayRecord?

    var averagePerRecordedDay: TimeInterval { recordedDays > 0 ? total / Double(recordedDays) : 0 }
    var delta: TimeInterval? { previousTotal.map { total - $0 } }
}

// MARK: - Engine

/// 纯计算层：给定会话列表，计算所有统计。与 UI / HealthKit 无关，方便测试。
struct StatsEngine {
    let calendar: Calendar
    let sessions: [WearSession]
    /// 当天 0 点 -> 当天佩戴秒数（跨天会话会被拆分）
    let daily: [Date: TimeInterval]
    let sortedDays: [Date]

    init(sessions: [WearSession], calendar: Calendar = .stats) {
        self.calendar = calendar
        self.sessions = sessions.sorted { $0.start < $1.start }
        var daily: [Date: TimeInterval] = [:]
        for s in self.sessions {
            for (day, seconds) in Self.split(s.start, s.end, by: .day, calendar: calendar) {
                daily[day, default: 0] += seconds
            }
        }
        self.daily = daily
        self.sortedDays = daily.keys.sorted()
    }

    var isEmpty: Bool { sessions.isEmpty }
    var firstDay: Date? { sortedDays.first }
    var lastDay: Date? { sortedDays.last }
    var totalDuration: TimeInterval { daily.values.reduce(0, +) }

    /// 把 [start, end) 按日历单位（天/小时）切开，返回 每段起点 -> 秒数
    static func split(_ start: Date, _ end: Date, by component: Calendar.Component, calendar: Calendar) -> [(Date, TimeInterval)] {
        guard end > start else { return [] }
        var result: [(Date, TimeInterval)] = []
        var cursor = start
        while cursor < end {
            guard let bucket = calendar.dateInterval(of: component, for: cursor) else { break }
            let segmentEnd = min(end, bucket.end)
            result.append((bucket.start, segmentEnd.timeIntervalSince(cursor)))
            cursor = segmentEnd
        }
        return result
    }

    // MARK: Records

    func records() -> PersonalRecords {
        var r = PersonalRecords()

        if let best = daily.max(by: { $0.value < $1.value }) {
            r.bestDay = DayRecord(day: best.key, duration: best.value)
        }
        r.longestSession = sessions.max(by: { $0.duration < $1.duration })
        r.longestStreak = longestStreak()

        var monthly: [Date: TimeInterval] = [:]
        for (day, v) in daily {
            if let m = calendar.dateInterval(of: .month, for: day)?.start { monthly[m, default: 0] += v }
        }
        if let best = monthly.max(by: { $0.value < $1.value }) {
            r.bestMonth = MonthRecord(month: best.key, duration: best.value)
        }
        r.topDevice = deviceTotals().first
        return r
    }

    func longestStreak() -> StreakRecord? {
        guard let first = sortedDays.first else { return nil }
        var best = StreakRecord(start: first, end: first, days: 1)
        var current = best
        for day in sortedDays.dropFirst() {
            if let next = calendar.date(byAdding: .day, value: 1, to: current.end),
               calendar.isDate(next, inSameDayAs: day) {
                current.end = day
                current.days += 1
            } else {
                current = StreakRecord(start: day, end: day, days: 1)
            }
            if current.days > best.days { best = current }
        }
        return best
    }

    func deviceTotals() -> [DeviceTotal] {
        var map: [String: DeviceTotal] = [:]
        for s in sessions {
            if var t = map[s.deviceID] {
                t.duration += s.duration
                t.sessionCount += 1
                t.firstUsed = min(t.firstUsed, s.start)
                t.lastUsed = max(t.lastUsed, s.end)
                map[s.deviceID] = t
            } else {
                map[s.deviceID] = DeviceTotal(deviceID: s.deviceID, duration: s.duration, sessionCount: 1, firstUsed: s.start, lastUsed: s.end)
            }
        }
        return map.values.sorted { $0.duration > $1.duration }
    }

    // MARK: Days

    func duration(on day: Date) -> TimeInterval {
        daily[calendar.startOfDay(for: day)] ?? 0
    }

    func duration(in interval: DateInterval) -> TimeInterval {
        // daily 的 key 都是 0 点；区间均以 0 点对齐
        var total: TimeInterval = 0
        for (day, v) in daily where day >= interval.start && day < interval.end { total += v }
        return total
    }

    /// 某天中与该天相交的会话（已裁剪到当天范围内）
    func sessions(on day: Date) -> [WearSession] {
        guard let range = calendar.dateInterval(of: .day, for: day) else { return [] }
        return sessions.compactMap { s in
            guard s.end > range.start, s.start < range.end else { return nil }
            var clipped = s
            clipped.start = max(s.start, range.start)
            clipped.end = min(s.end, range.end)
            return clipped
        }
    }

    /// 某天 24 小时的分布（秒）
    func hourly(on day: Date) -> [TimeInterval] {
        var bins = Array(repeating: TimeInterval(0), count: 24)
        for s in sessions(on: day) {
            for (hourStart, seconds) in Self.split(s.start, s.end, by: .hour, calendar: calendar) {
                let h = calendar.component(.hour, from: hourStart)
                if (0..<24).contains(h) { bins[h] += seconds }
            }
        }
        return bins
    }

    // MARK: Periods

    func interval(of kind: PeriodKind, containing date: Date, now: Date = .now) -> DateInterval {
        switch kind {
        case .week: return calendar.dateInterval(of: .weekOfYear, for: date) ?? DateInterval(start: date, duration: 0)
        case .month: return calendar.dateInterval(of: .month, for: date) ?? DateInterval(start: date, duration: 0)
        case .year: return calendar.dateInterval(of: .year, for: date) ?? DateInterval(start: date, duration: 0)
        case .all:
            let todayEnd = calendar.dateInterval(of: .day, for: now)?.end ?? now
            let start = firstDay ?? calendar.startOfDay(for: now)
            let end = max(todayEnd, lastDay.flatMap { calendar.date(byAdding: .day, value: 1, to: $0) } ?? todayEnd)
            return DateInterval(start: start, end: end)
        }
    }

    func shift(_ date: Date, kind: PeriodKind, by value: Int) -> Date {
        switch kind {
        case .week: return calendar.date(byAdding: .weekOfYear, value: value, to: date) ?? date
        case .month: return calendar.date(byAdding: .month, value: value, to: date) ?? date
        case .year: return calendar.date(byAdding: .year, value: value, to: date) ?? date
        case .all: return date
        }
    }

    func canShift(_ date: Date, kind: PeriodKind, by value: Int, now: Date = .now) -> Bool {
        guard kind != .all else { return false }
        let target = interval(of: kind, containing: shift(date, kind: kind, by: value), now: now)
        if value > 0 { return target.start <= now }
        guard let first = firstDay else { return false }
        return target.end > first
    }

    func summary(for kind: PeriodKind, containing date: Date, now: Date = .now) -> PeriodSummary {
        let interval = interval(of: kind, containing: date, now: now)
        let total = duration(in: interval)
        var previous: TimeInterval?
        if kind != .all {
            let prevInterval = self.interval(of: kind, containing: shift(date, kind: kind, by: -1), now: now)
            previous = duration(in: prevInterval)
        }

        let bars = makeBars(kind: kind, interval: interval)
        let daysInPeriod = daily.filter { $0.key >= interval.start && $0.key < interval.end && $0.value > 0 }
        let totalDays = max(1, calendar.dateComponents([.day], from: interval.start, to: interval.end).day ?? 1)
        let sessionCount = sessions.filter { $0.start >= interval.start && $0.start < interval.end }.count
        let bestDay = daysInPeriod.max(by: { $0.value < $1.value }).map { DayRecord(day: $0.key, duration: $0.value) }

        return PeriodSummary(
            kind: kind,
            interval: interval,
            title: Fmt.periodTitle(kind, interval: interval, calendar: calendar),
            total: total,
            previousTotal: previous,
            bars: bars,
            recordedDays: daysInPeriod.count,
            totalDays: totalDays,
            sessionCount: sessionCount,
            bestDay: bestDay
        )
    }

    private func makeBars(kind: PeriodKind, interval: DateInterval) -> [PeriodBar] {
        let unit: Calendar.Component
        switch kind {
        case .week, .month: unit = .day
        case .year: unit = .month
        case .all: unit = .year
        }
        var bars: [PeriodBar] = []
        var cursor = interval.start
        if kind == .all, let y = calendar.dateInterval(of: .year, for: cursor) { cursor = y.start }
        var index = 0
        while cursor < interval.end, index < 400 {
            guard let bucket = calendar.dateInterval(of: unit, for: cursor) else { break }
            let days = daily.filter { $0.key >= bucket.start && $0.key < bucket.end && $0.value > 0 }
            let total = days.values.reduce(0, +)
            bars.append(PeriodBar(
                index: index,
                start: bucket.start,
                end: bucket.end,
                label: Fmt.barLabel(kind, date: bucket.start, calendar: calendar),
                detailLabel: Fmt.barDetail(kind, date: bucket.start, calendar: calendar),
                duration: total,
                recordedDays: days.count
            ))
            cursor = bucket.end
            index += 1
        }
        return bars
    }
}

extension Calendar {
    /// 以周一为一周开始的公历
    static var stats: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.locale = Locale(identifier: "zh_CN")
        c.timeZone = .current
        c.firstWeekday = 2
        c.minimumDaysInFirstWeek = 4
        return c
    }
}

// MARK: - Devices

struct DeviceDetailStats {
    var total: TimeInterval
    var firstDay: Date?
    var lastDay: Date?
    var recordedDays: Int
    var sessionCount: Int
    var longest: WearSession?
    var averageLevel: Double?

    var averagePerSession: TimeInterval { sessionCount > 0 ? total / Double(sessionCount) : 0 }
}

extension StatsEngine {
    /// 设备页时间范围对应的区间（均以 0 点对齐，截止到今天结束）
    func interval(of period: DevicePeriod, now: Date = .now) -> DateInterval {
        let todayEnd = calendar.dateInterval(of: .day, for: now)?.end ?? now
        let today = calendar.startOfDay(for: now)
        switch period {
        case .last7:
            return DateInterval(start: calendar.date(byAdding: .day, value: -6, to: today) ?? today, end: todayEnd)
        case .last30:
            return DateInterval(start: calendar.date(byAdding: .day, value: -29, to: today) ?? today, end: todayEnd)
        case .thisWeek:
            return interval(of: .week, containing: now, now: now)
        case .thisMonth:
            return interval(of: .month, containing: now, now: now)
        case .all:
            return interval(of: .all, containing: now, now: now)
        }
    }

    /// 区间内每副耳机的佩戴时长（会话被裁剪到区间内），按时长降序
    func deviceTotals(in interval: DateInterval) -> [DeviceTotal] {
        var map: [String: DeviceTotal] = [:]
        for s in sessions where s.end > interval.start && s.start < interval.end {
            let start = max(s.start, interval.start), end = min(s.end, interval.end)
            let d = end.timeIntervalSince(start)
            if var t = map[s.deviceID] {
                t.duration += d
                t.sessionCount += 1
                t.firstUsed = min(t.firstUsed, start)
                t.lastUsed = max(t.lastUsed, end)
                map[s.deviceID] = t
            } else {
                map[s.deviceID] = DeviceTotal(deviceID: s.deviceID, duration: d, sessionCount: 1, firstUsed: start, lastUsed: end)
            }
        }
        return map.values.sorted { $0.duration > $1.duration }
    }

    /// 单副耳机的全部历史统计
    func detail(for deviceID: String) -> DeviceDetailStats {
        let mine = sessions.filter { $0.deviceID == deviceID }
        let engine = StatsEngine(sessions: mine, calendar: calendar)
        var levelSum = 0.0, levelWeight = 0.0
        for s in mine {
            if let l = s.averageLevel { levelSum += l * s.duration; levelWeight += s.duration }
        }
        return DeviceDetailStats(
            total: engine.totalDuration,
            firstDay: engine.firstDay,
            lastDay: engine.lastDay,
            recordedDays: engine.daily.values.filter { $0 > 0 }.count,
            sessionCount: mine.count,
            longest: mine.max(by: { $0.duration < $1.duration }),
            averageLevel: levelWeight > 0 ? levelSum / levelWeight : nil
        )
    }

    /// 最近 n 天（含今天）的每日时长
    func recentDays(_ n: Int, now: Date = .now) -> [(day: Date, duration: TimeInterval)] {
        let today = calendar.startOfDay(for: now)
        return (0..<n).reversed().compactMap { offset in
            calendar.date(byAdding: .day, value: -offset, to: today).map { (day: $0, duration: duration(on: $0)) }
        }
    }
}
