import XCTest
@testable import AirPodsStats

final class AnalyticsTests: XCTestCase {
    private var cal: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Asia/Shanghai")!
        c.firstWeekday = 2
        c.minimumDaysInFirstWeek = 4
        return c
    }()

    private func date(_ y: Int, _ m: Int, _ d: Int, _ h: Int = 0, _ min: Int = 0) -> Date {
        cal.date(from: DateComponents(year: y, month: m, day: d, hour: h, minute: min))!
    }

    private func sample(_ device: String, _ start: Date, minutes: Double, level: Double? = nil) -> RawSample {
        RawSample(deviceID: device, deviceName: device, deviceModel: nil, start: start,
                  end: start.addingTimeInterval(minutes * 60), level: level)
    }

    private func session(_ device: String, _ start: Date, minutes: Double, level: Double? = nil) -> WearSession {
        WearSession(deviceID: device, start: start, end: start.addingTimeInterval(minutes * 60), averageLevel: level)
    }

    // MARK: SessionBuilder

    func testSamplesWithinGapMergeIntoOneSession() {
        let t = date(2025, 7, 3, 12)
        let samples = [
            sample("A", t, minutes: 10, level: 60),
            sample("A", t.addingTimeInterval(12 * 60), minutes: 10, level: 70),   // 2 分钟间隔
        ]
        let sessions = SessionBuilder.build(from: samples, mergeGap: 5 * 60)
        XCTAssertEqual(sessions.count, 1)
        XCTAssertEqual(sessions[0].duration, 22 * 60, accuracy: 0.001)
        XCTAssertEqual(sessions[0].averageLevel ?? 0, 65, accuracy: 0.001)
    }

    func testSamplesBeyondGapSplit() {
        let t = date(2025, 7, 3, 12)
        let samples = [sample("A", t, minutes: 10), sample("A", t.addingTimeInterval(30 * 60), minutes: 10)]
        XCTAssertEqual(SessionBuilder.build(from: samples, mergeGap: 5 * 60).count, 2)
    }

    func testDifferentDevicesNeverMerge() {
        let t = date(2025, 7, 3, 12)
        let samples = [sample("A", t, minutes: 10), sample("B", t.addingTimeInterval(60), minutes: 10)]
        let sessions = SessionBuilder.build(from: samples, mergeGap: 5 * 60)
        XCTAssertEqual(Set(sessions.map(\.deviceID)), ["A", "B"])
    }

    func testOverlappingSamplesAreNotDoubleCounted() {
        let t = date(2025, 7, 3, 12)
        let samples = [sample("A", t, minutes: 30), sample("A", t.addingTimeInterval(10 * 60), minutes: 10)]
        let sessions = SessionBuilder.build(from: samples, mergeGap: 0)
        XCTAssertEqual(sessions.count, 1)
        XCTAssertEqual(sessions[0].duration, 30 * 60, accuracy: 0.001)
    }

    func testCoalesceMergesAdjacentSessionsAndWeightsLevel() {
        let t = date(2025, 7, 3, 12)
        let merged = SessionBuilder.coalesce([
            session("A", t, minutes: 30, level: 60),
            session("A", t.addingTimeInterval(31 * 60), minutes: 10, level: 80),
            session("A", t.addingTimeInterval(120 * 60), minutes: 10, level: 50),
        ], mergeGap: 5 * 60)
        XCTAssertEqual(merged.count, 2)
        XCTAssertEqual(merged[0].duration, 41 * 60, accuracy: 0.001)
        XCTAssertEqual(merged[0].averageLevel ?? 0, (60 * 30 + 80 * 10) / 40.0, accuracy: 0.001)
        XCTAssertEqual(merged[1].averageLevel ?? 0, 50, accuracy: 0.001)
    }

    // MARK: StatsEngine

    func testSessionAcrossMidnightIsSplitByDay() {
        let s = session("A", date(2025, 7, 3, 23, 30), minutes: 60)
        let engine = StatsEngine(sessions: [s], calendar: cal)
        XCTAssertEqual(engine.duration(on: date(2025, 7, 3)), 30 * 60, accuracy: 0.001)
        XCTAssertEqual(engine.duration(on: date(2025, 7, 4)), 30 * 60, accuracy: 0.001)
        XCTAssertEqual(engine.hourly(on: date(2025, 7, 4))[0], 30 * 60, accuracy: 0.001)
    }

    func testRecords() {
        let sessions = [
            session("A", date(2025, 6, 30, 9), minutes: 60),
            session("A", date(2025, 7, 1, 9), minutes: 120),
            session("B", date(2025, 7, 1, 14), minutes: 30),
            session("A", date(2025, 7, 2, 9), minutes: 10),
            session("A", date(2025, 7, 10, 9), minutes: 300),
        ]
        let r = StatsEngine(sessions: sessions, calendar: cal).records()
        XCTAssertEqual(r.bestDay?.day, date(2025, 7, 10))
        XCTAssertEqual(r.longestSession?.duration ?? 0, 300 * 60, accuracy: 0.001)
        XCTAssertEqual(r.longestStreak?.days, 3)
        XCTAssertEqual(r.longestStreak?.start, date(2025, 6, 30))
        XCTAssertEqual(r.longestStreak?.end, date(2025, 7, 2))
        XCTAssertEqual(r.bestMonth?.month, date(2025, 7, 1))
        XCTAssertEqual(r.topDevice?.deviceID, "A")
    }

    func testYearSummaryBarsTotalsAndComparison() {
        let sessions = [
            session("A", date(2024, 5, 1, 9), minutes: 60),
            session("A", date(2025, 3, 1, 9), minutes: 120),
            session("A", date(2025, 3, 2, 9), minutes: 60),
            session("A", date(2025, 11, 1, 9), minutes: 30),
        ]
        let engine = StatsEngine(sessions: sessions, calendar: cal)
        let summary = engine.summary(for: .year, containing: date(2025, 6, 1), now: date(2025, 12, 31))
        XCTAssertEqual(summary.bars.count, 12)
        XCTAssertEqual(summary.total, 210 * 60, accuracy: 0.001)
        XCTAssertEqual(summary.previousTotal ?? 0, 60 * 60, accuracy: 0.001)
        XCTAssertEqual(summary.bars[2].duration, 180 * 60, accuracy: 0.001)
        XCTAssertEqual(summary.bars[2].recordedDays, 2)
        XCTAssertEqual(summary.recordedDays, 3)
        XCTAssertEqual(summary.totalDays, 365)
        XCTAssertEqual(summary.sessionCount, 3)
    }

    func testWeekStartsOnMonday() {
        let engine = StatsEngine(sessions: [], calendar: cal)
        let interval = engine.interval(of: .week, containing: date(2025, 11, 19), now: date(2025, 11, 19))
        XCTAssertEqual(interval.start, date(2025, 11, 17))
        XCTAssertEqual(engine.summary(for: .week, containing: date(2025, 11, 19)).bars.count, 7)
    }

    func testCannotNavigateIntoTheFuture() {
        let engine = StatsEngine(sessions: [session("A", date(2025, 1, 5, 9), minutes: 10)], calendar: cal)
        let now = date(2025, 6, 1)
        XCTAssertFalse(engine.canShift(now, kind: .month, by: 1, now: now))
        XCTAssertTrue(engine.canShift(now, kind: .month, by: -1, now: now))
        XCTAssertFalse(engine.canShift(date(2025, 1, 10), kind: .month, by: -1, now: now))
    }

    func testDeviceTotalsClipToInterval() {
        let engine = StatsEngine(sessions: [session("A", date(2025, 7, 3, 23), minutes: 120)], calendar: cal)
        let interval = DateInterval(start: date(2025, 7, 4), end: date(2025, 7, 5))
        XCTAssertEqual(engine.deviceTotals(in: interval).first?.duration ?? 0, 60 * 60, accuracy: 0.001)
    }

    // MARK: UsageStore.process

    func testMergeAndHide() {
        let known: [String: HeadphoneDevice] = [
            "A": HeadphoneDevice(id: "A", rawName: "AirPods Pro"),
            "A2": HeadphoneDevice(id: "A2", rawName: "我的 AirPods Pro"),
            "B": HeadphoneDevice(id: "B", rawName: "Beats"),
        ]
        let base = [
            session("A", date(2025, 7, 3, 9), minutes: 30),
            session("A2", date(2025, 7, 3, 9, 31), minutes: 30),
            session("B", date(2025, 7, 3, 12), minutes: 30),
        ]
        let out = UsageStore.process(base: base, known: known, merges: ["A2": "A"], hidden: ["B"],
                                     filter: [], mergeGap: 5 * 60)
        XCTAssertEqual(Set(out.devices.keys), ["A"])
        XCTAssertEqual(out.sessions.count, 1)
        XCTAssertEqual(out.sessions[0].duration, 61 * 60, accuracy: 0.001)
    }

    func testMergeCycleIsBroken() {
        let known: [String: HeadphoneDevice] = [
            "A": HeadphoneDevice(id: "A", rawName: "A"), "B": HeadphoneDevice(id: "B", rawName: "B"),
        ]
        // 非法的环不应导致死循环
        let resolved = UsageStore.resolve("A", merges: ["A": "B", "B": "A"], known: known)
        XCTAssertTrue(["A", "B"].contains(resolved))
    }

    func testFilterOnlyAffectsFilteredEngine() {
        let known: [String: HeadphoneDevice] = [
            "A": HeadphoneDevice(id: "A", rawName: "A"), "B": HeadphoneDevice(id: "B", rawName: "B"),
        ]
        let base = [session("A", date(2025, 7, 3, 9), minutes: 30), session("B", date(2025, 7, 3, 12), minutes: 60)]
        let out = UsageStore.process(base: base, known: known, merges: [:], hidden: [], filter: ["A"], mergeGap: 300)
        XCTAssertEqual(out.engine.totalDuration, 30 * 60, accuracy: 0.001)
        XCTAssertEqual(out.allDevicesEngine.totalDuration, 90 * 60, accuracy: 0.001)
    }

    // MARK: Formatting

    func testDurationFormatting() {
        XCTAssertEqual(Fmt.duration(13 * 3600 + 52 * 60 + 59), "13 h 52 min")
        XCTAssertEqual(Fmt.shortDuration(42 * 60), "42 min")
        XCTAssertEqual(Fmt.signedDuration(-(3 * 3600 + 120)), "-3 h 2 min")
        XCTAssertEqual(Fmt.signedDuration(0), "+0 h 0 min")
    }

    func testCSVEscapesQuotes() {
        let export = SessionExport(sessions: [session("A", date(2025, 7, 3, 9), minutes: 30, level: 60)],
                                   names: ["A": "Min\"s AirPods"])
        let csv = export.csv()
        XCTAssertTrue(csv.contains("\"Min\"\"s AirPods\""))
        XCTAssertTrue(csv.contains(",30.0,60.0"))
    }
}
