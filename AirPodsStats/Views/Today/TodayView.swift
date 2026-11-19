import SwiftUI

struct TodayView: View {
    @Environment(UsageStore.self) private var store
    @State private var selectedHour: String?
    @State private var selectedDay: String?

    var body: some View {
        let engine = store.engine
        let now = Date.now
        let cal = engine.calendar
        let today = cal.startOfDay(for: now)
        let yesterday = cal.date(byAdding: .day, value: -1, to: today) ?? today
        let todayTotal = engine.duration(on: today)
        let yesterdayTotal = engine.duration(on: yesterday)
        let sessions = engine.sessions(on: today).sorted { $0.start > $1.start }
        let hourly = engine.hourly(on: today)
        let last7 = (0..<7).reversed().compactMap { cal.date(byAdding: .day, value: -$0, to: today) }
        let weekSummary = engine.summary(for: .week, containing: now)

        ScrollView {
            VStack(spacing: 18) {
                StatusBanner()
                LargeTitle(title: "今天", subtitle: Fmt.fullDay(now))
                    .padding(.top, 40)

                // 今日累计
                Card {
                    VStack(alignment: .leading, spacing: 14) {
                        CardHeader(icon: "headphones", title: "今日佩戴")
                        HStack(alignment: .top) {
                            VStack(alignment: .leading, spacing: 6) {
                                DurationText(seconds: selectedHourValue(hourly) ?? todayTotal, size: 56)
                                Text(selectedHour.map { "\($0):00 – \($0):59" } ?? "截至 \(Fmt.time(now))")
                                    .font(.system(size: 15, weight: .medium))
                                    .foregroundStyle(Theme.secondaryText)
                            }
                            Spacer()
                            Badge(title: "较昨天", value: Fmt.signedDuration(todayTotal - yesterdayTotal))
                        }
                        ChartPanel {
                            DurationBarChart(
                                bars: hourly.enumerated().map { h, v in
                                    ChartBar(key: String(format: "%02d", h), label: "\(h)", detail: "\(h) 时", seconds: v)
                                },
                                height: 180,
                                maxXLabels: 6,
                                selectedKey: $selectedHour
                            )
                        }
                    }
                }

                // 小卡片
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 14), GridItem(.flexible(), spacing: 14)], spacing: 14) {
                    SmallStat(icon: "repeat", title: "今日次数") {
                        NumberUnitText(value: "\(sessions.count)", unit: "次", size: 36, color: .white.opacity(0.85))
                    }
                    SmallStat(icon: "timer", title: "今日最长一次") {
                        DurationText(seconds: sessions.map(\.duration).max() ?? 0, size: 36)
                    }
                    SmallStat(icon: "calendar", title: "本周累计") {
                        DurationText(seconds: weekSummary.total, size: 36)
                    }
                    SmallStat(icon: "chart.line.uptrend.xyaxis", title: "近 7 日平均") {
                        DurationText(seconds: last7.map { engine.duration(on: $0) }.reduce(0, +) / 7, size: 36)
                    }
                }

                // 近 7 天
                Card {
                    VStack(alignment: .leading, spacing: 14) {
                        CardHeader(icon: "chart.bar.xaxis", title: "近 7 天")
                        if let key = selectedDay, let day = last7.first(where: { Fmt.day($0) == key }) {
                            Text("\(Fmt.day(day)) · \(Fmt.duration(engine.duration(on: day)))")
                                .font(.system(size: 15, weight: .medium)).foregroundStyle(Theme.secondaryText)
                        }
                        ChartPanel {
                            DurationBarChart(
                                bars: last7.map { d in
                                    ChartBar(key: Fmt.day(d), label: Fmt.barLabel(.week, date: d, calendar: cal),
                                             detail: Fmt.day(d), seconds: engine.duration(on: d))
                                },
                                height: 160,
                                selectedKey: $selectedDay
                            )
                        }
                    }
                }

                // 今日会话
                Card {
                    VStack(alignment: .leading, spacing: 14) {
                        CardHeader(icon: "list.bullet", title: "今日佩戴记录")
                        if sessions.isEmpty {
                            EmptyHint(text: "今天还没有记录 · 无记录不等于未佩戴")
                        } else {
                            ForEach(sessions) { s in
                                SessionRow(session: s)
                                if s.id != sessions.last?.id { Divider().overlay(.white.opacity(0.08)) }
                            }
                        }
                    }
                }

                if let updated = store.lastUpdated {
                    Text("更新于 \(Fmt.day(updated)) \(Fmt.time(updated))")
                        .font(.footnote).foregroundStyle(Theme.tertiaryText)
                }
            }
            .screenPadding()
            .padding(.bottom, 30)
        }
        .scrollIndicators(.hidden)
        .background(GridBackground())
        .refreshable { await store.reload() }
    }

    private func selectedHourValue(_ hourly: [TimeInterval]) -> TimeInterval? {
        guard let selectedHour, let h = Int(selectedHour), hourly.indices.contains(h) else { return nil }
        return hourly[h]
    }
}

struct SmallStat<Value: View>: View {
    var icon: String
    var title: String
    @ViewBuilder var value: Value

    var body: some View {
        Card(padding: 18) {
            VStack(alignment: .leading, spacing: 16) {
                CardHeader(icon: icon, title: title)
                value
            }
        }
    }
}

struct Badge: View {
    var title: String
    var value: String
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
            Text(value)
        }
        .font(.system(size: 14, weight: .medium))
        .foregroundStyle(.white.opacity(0.85))
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(.white.opacity(0.1)))
    }
}

struct SessionRow: View {
    @Environment(UsageStore.self) private var store
    var session: WearSession

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: store.kind(for: session.deviceID).symbol)
                .font(.system(size: 20))
                .foregroundStyle(.white.opacity(0.85))
                .frame(width: 40, height: 40)
                .background(Circle().fill(.white.opacity(0.08)))
            VStack(alignment: .leading, spacing: 3) {
                Text(store.displayName(for: session.deviceID))
                    .font(.system(size: 16, weight: .medium)).foregroundStyle(.white)
                    .lineLimit(1)
                Text(Fmt.timeRange(session))
                    .font(.system(size: 14)).foregroundStyle(Theme.secondaryText)
            }
            Spacer()
            Text(Fmt.shortDuration(session.duration))
                .font(.system(size: 16, weight: .semibold, design: .rounded))
                .foregroundStyle(Theme.accent)
        }
    }
}

/// 加载 / 错误 / 空数据 提示
struct StatusBanner: View {
    @Environment(UsageStore.self) private var store

    var body: some View {
        switch store.state {
        case .loading:
            HStack(spacing: 10) {
                ProgressView().tint(.white)
                Text("正在读取健康数据…").foregroundStyle(Theme.secondaryText)
            }
            .padding(.top, 8)
        case .failed(let message):
            Card {
                VStack(alignment: .leading, spacing: 10) {
                    Label("读取失败", systemImage: "exclamationmark.triangle").foregroundStyle(.orange)
                    Text(message).font(.subheadline).foregroundStyle(Theme.secondaryText)
                    Button("使用示例数据") { store.dataSource = .demo }
                        .buttonStyle(.bordered).tint(.white)
                }
            }
            .padding(.top, 8)
        default:
            if store.state == .loaded && store.allSessions.isEmpty && store.dataSource == .health {
                Card {
                    VStack(alignment: .leading, spacing: 10) {
                        Label("没有读取到耳机记录", systemImage: "info.circle").foregroundStyle(Theme.accent)
                        Text("请在「健康」App › 共享 › App 中允许本应用读取“耳机音频级别”，并确认戴 AirPods 播放过音频。")
                            .font(.subheadline).foregroundStyle(Theme.secondaryText)
                        Button("先看看示例数据") { store.dataSource = .demo }
                            .buttonStyle(.bordered).tint(.white)
                    }
                }
                .padding(.top, 8)
            }
        }
    }
}
