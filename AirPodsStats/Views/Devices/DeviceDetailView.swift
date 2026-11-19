import SwiftUI

/// 单副耳机的详情页
struct DeviceDetailView: View {
    @Environment(UsageStore.self) private var store
    @Environment(AppRouter.self) private var router
    var deviceID: String
    var period: DevicePeriod
    @State private var editing: HeadphoneDevice?
    @State private var selectedDay: String?

    var body: some View {
        if store.devices[deviceID] == nil && store.hasData {
            // 设备已被合并或隐藏
            ContentUnavailableView {
                Label("这副耳机已不在统计中", systemImage: "headphones")
            } description: {
                Text(store.mergeTargets[deviceID] != nil ? "它已被合并到「\(store.displayName(for: store.resolvedID(deviceID)))」。" : "它可能已被隐藏，可在设置中恢复。")
            } actions: {
                if store.mergeTargets[deviceID] != nil {
                    Button("查看合并后的耳机") { router.devicePath = [.detail(store.resolvedID(deviceID))] }
                }
            }
            .background(NightBackground(horizon: 0.40))
        } else {
            content
        }
    }

    @ViewBuilder
    private var content: some View {
        let all = store.allDevicesEngine
        let interval = all.interval(of: period)
        let periodTotals = all.deviceTotals(in: interval)
        let periodSum = periodTotals.map(\.duration).reduce(0, +)
        let periodDuration = periodTotals.first(where: { $0.deviceID == deviceID })?.duration ?? 0

        let mine = StatsEngine(sessions: store.allSessions.filter { $0.deviceID == deviceID })
        let detail = mine.detail(for: deviceID)
        let trend = mine.recentDays(30)
        let recent = Array(mine.sessions.suffix(5).reversed())
        let device = store.devices[deviceID]
        let name = store.displayName(for: deviceID)

        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text(name)
                    .font(.system(size: 40, weight: .heavy))
                    .foregroundStyle(.white.opacity(0.92))
                    .lineLimit(2)
                    .minimumScaleFactor(0.6)

                DeviceGlassCard(name: name, kind: store.kind(for: deviceID), duration: periodDuration,
                                share: periodSum > 0 ? periodDuration / periodSum : 0, artworkHeight: 150)

                Text(metaLine(interval: interval, device: device))
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.white.opacity(0.55))
                    .padding(.horizontal, 2)

                NightTile(padding: 22) {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("累计聆听时长")
                            .font(.system(size: 20, weight: .bold)).foregroundStyle(.white)
                        DurationText(seconds: detail.total, size: 56, color: Night.lavender.opacity(0.85))
                        Text(historyLine(detail))
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(.white.opacity(0.6))
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                    }
                }

                LazyVGrid(columns: [GridItem(.flexible(), spacing: 14), GridItem(.flexible(), spacing: 14)], spacing: 14) {
                    MetricTile(title: "累计佩戴次数", caption: "次") {
                        NumberUnitText(value: "\(detail.sessionCount)", unit: "", size: 36, color: .white.opacity(0.9))
                    }
                    MetricTile(title: "平均每次", caption: "每次佩戴") {
                        DurationText(seconds: detail.averagePerSession, size: 36, color: .white.opacity(0.9))
                    }
                    MetricTile(title: "最长一次", caption: detail.longest.map { Fmt.sessionRange($0) } ?? "估算") {
                        DurationText(seconds: detail.longest?.duration ?? 0, size: 36, color: .white.opacity(0.9))
                    }
                    MetricTile(title: "平均音量", caption: detail.averageLevel == nil ? "暂无音量数据" : "dB(A)") {
                        NumberUnitText(value: detail.averageLevel.map { String(Int($0.rounded())) } ?? "--",
                                       unit: "", size: 36, color: .white.opacity(0.9))
                    }
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text("近 30 天聆听趋势")
                        .font(.system(size: 22, weight: .bold)).foregroundStyle(.white)
                    Text(selectedLine(trend) ?? "轻点柱形查看当天聆听时长")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(.white.opacity(0.6))
                        .contentTransition(.numericText())
                }
                .padding(.top, 6)

                NightTile(padding: 16) {
                    DurationBarChart(
                        bars: trend.map { d in
                            ChartBar(key: Fmt.day(d.day), label: Fmt.barLabel(.month, date: d.day, calendar: mine.calendar),
                                     detail: Fmt.barDetail(.month, date: d.day, calendar: mine.calendar), seconds: d.duration)
                        },
                        height: 200,
                        maxXLabels: 6,
                        selectedKey: $selectedDay
                    )
                }

                if let key = selectedDay, let d = trend.first(where: { Fmt.day($0.day) == key }) {
                    Button {
                        selectedDay = nil
                        router.showDay(d.day)
                    } label: {
                        Label("查看 \(Fmt.barDetail(.month, date: d.day, calendar: .stats)) 的全部记录", systemImage: "arrow.right.circle.fill")
                            .font(.system(size: 15, weight: .semibold))
                    }
                    .foregroundStyle(Night.lavender)
                }

                HStack(alignment: .firstTextBaseline) {
                    Text("最近佩戴记录")
                        .font(.system(size: 22, weight: .bold)).foregroundStyle(.white)
                    Spacer()
                    if !recent.isEmpty {
                        Button("查看全部") { router.devicePath.append(.history(deviceID)) }
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(Night.lavender)
                    }
                }
                .padding(.top, 6)

                NightTile(padding: 18) {
                    if recent.isEmpty {
                        EmptyHint(text: "暂无记录")
                    } else {
                        VStack(spacing: 12) {
                            ForEach(recent) { s in
                                Button { router.showDay(s.start) } label: { SessionRow(session: s, showsDate: true) }
                                    .buttonStyle(.plain)
                                if s.id != recent.last?.id { Divider().overlay(.white.opacity(0.08)) }
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 40)
        }
        .scrollIndicators(.hidden)
        .background(NightBackground(horizon: 0.40))
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("编辑") { editing = device }
                    .font(.system(size: 18, weight: .semibold))
                    .disabled(device == nil)
            }
        }
        .tint(.white)
        .sheet(item: $editing) { DeviceEditSheet(device: $0) }
        .refreshable { await store.reload(force: true) }
    }

    /// “所选周期 11.10–11.16 · Apple Inc. · 0x202d”
    private func metaLine(interval: DateInterval, device: HeadphoneDevice?) -> String {
        var parts = ["所选周期 \(Fmt.compactRange(interval))"]
        if let m = device?.manufacturer, !m.isEmpty { parts.append(m) }
        if let model = device?.model, !model.isEmpty { parts.append(model) }
        return parts.joined(separator: " · ")
    }

    /// “已读取历史 2026.5.21–2026.11.14 · 116 个有记录日”
    private func historyLine(_ d: DeviceDetailStats) -> String {
        guard let first = d.firstDay, let last = d.lastDay else { return "暂无记录" }
        let source = store.dataSource == .demo ? "示例数据" : "已读取历史"
        return "\(source) \(Fmt.tightDayRange(first, last)) · \(d.recordedDays) 个有记录日"
    }

    private func selectedLine(_ trend: [(day: Date, duration: TimeInterval)]) -> String? {
        guard let key = selectedDay, let d = trend.first(where: { Fmt.day($0.day) == key }) else { return nil }
        return "\(Fmt.barDetail(.month, date: d.day, calendar: .stats)) · \(Fmt.duration(d.duration))"
    }
}

struct MetricTile<Value: View>: View {
    var title: String
    var caption: String
    @ViewBuilder var value: Value

    var body: some View {
        NightTile {
            VStack(alignment: .leading, spacing: 10) {
                Text(title)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(.white.opacity(0.65))
                value
                Text(caption)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.white.opacity(0.55))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
        }
    }
}
