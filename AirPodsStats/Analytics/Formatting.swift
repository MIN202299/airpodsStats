import Foundation

/// 时长与日期格式化（仿照原应用的 “13h52min”、“2025.7.3 12:46 – 17:43” 等写法）
enum Fmt {
    struct HM { var hours: Int; var minutes: Int }

    static func hm(_ seconds: TimeInterval) -> HM {
        let totalMinutes = max(0, Int((seconds / 60).rounded(.down)))
        return HM(hours: totalMinutes / 60, minutes: totalMinutes % 60)
    }

    /// “164 h 3 min”
    static func duration(_ seconds: TimeInterval) -> String {
        let v = hm(seconds)
        return "\(v.hours) h \(v.minutes) min"
    }

    /// 短格式：不足 1 小时只显示分钟，例如 “42 min”
    static func shortDuration(_ seconds: TimeInterval) -> String {
        let v = hm(seconds)
        return v.hours > 0 ? "\(v.hours) h \(v.minutes) min" : "\(v.minutes) min"
    }

    /// “+1305 h 1 min” / “-3 h 2 min”
    static func signedDuration(_ seconds: TimeInterval) -> String {
        (seconds < 0 ? "-" : "+") + duration(abs(seconds))
    }

    private static func df(_ format: String) -> DateFormatter {
        let f = DateFormatter()
        f.locale = Locale(identifier: "zh_CN")
        f.calendar = Calendar.stats
        f.timeZone = .current
        f.dateFormat = format
        return f
    }

    private static let dayF = df("yyyy.M.d")
    private static let shortDayF = df("M.d")
    private static let timeF = df("HH:mm")
    private static let monthF = df("yyyy 年 M 月")
    private static let yearF = df("yyyy 年")
    private static let fullDayF = df("M 月 d 日 EEEE")
    private static let monthOnlyF = df("M月")
    private static let dayOnlyF = df("d")
    private static let weekdayF = df("EEEEE")
    private static let detailDayF = df("M 月 d 日 EEE")

    static func day(_ d: Date) -> String { dayF.string(from: d) }
    static func time(_ d: Date) -> String { timeF.string(from: d) }
    static func month(_ d: Date) -> String { monthF.string(from: d) }
    static func year(_ d: Date) -> String { yearF.string(from: d) }
    static func fullDay(_ d: Date) -> String { fullDayF.string(from: d) }

    /// “2025.7.3 12:46 – 17:43”，跨天时写成 “2025.7.3 23:10 – 7.4 01:20”
    static func sessionRange(_ s: WearSession, calendar: Calendar = .stats) -> String {
        if calendar.isDate(s.start, inSameDayAs: s.end) || s.end == calendar.startOfDay(for: s.end) && s.end.timeIntervalSince(s.start) < 86_400 {
            return "\(day(s.start)) \(time(s.start)) – \(time(s.end))"
        }
        return "\(day(s.start)) \(time(s.start)) – \(shortDayF.string(from: s.end)) \(time(s.end))"
    }

    static func timeRange(_ s: WearSession) -> String { "\(time(s.start)) – \(time(s.end))" }

    /// “2025.6.30 – 2025.9.5”
    static func dayRange(_ a: Date, _ b: Date) -> String { "\(day(a)) – \(day(b))" }

    static func periodTitle(_ kind: PeriodKind, interval: DateInterval, calendar: Calendar) -> String {
        switch kind {
        case .week:
            let last = calendar.date(byAdding: .day, value: -1, to: interval.end) ?? interval.end
            return "\(day(interval.start)) – \(shortDayF.string(from: last))"
        case .month: return month(interval.start)
        case .year: return year(interval.start)
        case .all:
            let last = calendar.date(byAdding: .day, value: -1, to: interval.end) ?? interval.end
            return "\(day(interval.start)) – \(day(last))"
        }
    }

    static func barLabel(_ kind: PeriodKind, date: Date, calendar: Calendar) -> String {
        switch kind {
        case .week: return weekdayF.string(from: date)          // “一”
        case .month: return dayOnlyF.string(from: date)         // “17”
        case .year: return monthOnlyF.string(from: date)        // “3月”
        case .all: return String(calendar.component(.year, from: date))
        }
    }

    static func barDetail(_ kind: PeriodKind, date: Date, calendar: Calendar) -> String {
        switch kind {
        case .week, .month: return detailDayF.string(from: date)
        case .year: return month(date)
        case .all: return year(date)
        }
    }
}

extension Fmt {
    private static let mdF: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "zh_CN")
        f.calendar = Calendar.stats
        f.dateFormat = "M.d"
        return f
    }()

    /// “11.10–11.16”
    static func compactRange(_ interval: DateInterval, calendar: Calendar = .stats) -> String {
        let last = calendar.date(byAdding: .second, value: -1, to: interval.end) ?? interval.end
        if calendar.isDate(interval.start, inSameDayAs: last) { return mdF.string(from: interval.start) }
        return "\(mdF.string(from: interval.start))–\(mdF.string(from: last))"
    }

    /// “2026.5.21–2026.11.14”
    static func tightDayRange(_ a: Date, _ b: Date) -> String { "\(day(a))–\(day(b))" }
}
