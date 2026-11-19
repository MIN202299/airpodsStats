import SwiftUI

/// “今天”页：默认显示今天，可以前后翻看任意一天（统计页、纪录卡片也会跳到这里）
struct TodayView: View {
    @Environment(UsageStore.self) private var store
    @Environment(AppRouter.self) private var router
    @State private var selectedHour: String?
    @State private var selectedDay: String?
    @State private var showFilter = false

    var body: some View {
        let engine = store.engine
        let cal = engine.calendar
        let now = Date.now
        let today = cal.startOfDay(for: now)
        let day = router.focusedDay.map { min($0, today) } ?? today
        let isToday = cal.isDate(day, inSameDayAs: today)
        let previousDay = cal.date(byAdding: .day, value: -1, to: day) ?? day
        let dayTotal = engine.duration(on: day)
        let previousTotal = engine.duration(on: previousDay)
        let sessions = engine.sessions(on: day).sorted { $0.start > $1.start }
        let hourly = engine.hourly(on: day)
        let last7 = (0..<7).reversed().compactMap { cal.date(byAdding: .day, value: -$0, to: day) }
        let weekTotal = engine.summary(for: .week, containing: day).total
        let canGoBack = engine.firstDay.map { day > $0 } ?? false

        ScrollView {
            VStack(spacing: 18) {
                topBar
                StatusBanner()
                FilterChip()

                VStack(alignment: .leading, spacing: 4) {
                    Text(title(for: day, isToday: isToday, cal: cal))
                        .font(.system(size: 44, weight: .heavy)).foregroundStyle(.white.opacity(0.9))
                    Text(Fmt.fullDay(day)).font(.subheadline).foregroundStyle(Theme.secondaryText)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                dayNavigator(day: day, isToday: isToday, canGoBack: canGoBack)

                // 当日累计 + 24 小时分布
                Card {
                    VStack(alignment: .leading, spacing: 14) {
                        CardHeader(icon: "headphones", title: isToday ? "今日佩戴" : "当日佩戴")
                        HStack(alignment: .top) {
                            VStack(alignment: .leading, spacing: 6) {
                                DurationText(seconds: selectedHourValue(hourly) ?? dayTotal, size: 56)
                                Text(selectedHourCaption ?? (isToday ? "截至 \(Fmt.time(now))" : "全天"))
                                    .font(.system(size: 15, weight: .medium))
                                    .foregroundStyle(Theme.secondaryText)
                            }
                            Spacer()
                            Badge(title: isToday ? "较昨天" : "较前一天", value: Fmt.signedDuration(dayTotal - previousTotal))
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

                LazyVGrid(columns: [GridItem(.flexible(), spacing: 14), GridItem(.flexible(), spacing: 14)], spacing: 14) {
                    SmallStat(icon: "repeat", title: "佩戴次数") {
                        NumberUnitText(value: "\(sessions.count)", unit: "次", size: 36, color: .white.opacity(0.85))
                    }
                    SmallStat(icon: "timer", title: "最长一次") {
                        DurationText(seconds: sessions.map(\.duration).max() ?? 0, size: 36)
                    }
                    Button { router.showPeriod(.week, containing: day) } label: {
                        SmallStat(icon: "calendar", title: "本周累计") {
                            DurationText(seconds: weekTotal, size: 36)
                        }
                    }
                    .buttonStyle(.plain)
                    SmallStat(icon: "chart.line.uptrend.xyaxis", title: "近 7 日平均") {
                        DurationText(seconds: last7.map { engine.duration(on: $0) }.reduce(0, +) / 7, size: 36)
                    }
                }

                // 近 7 天（点柱形后可跳到那一天）
                Card {
                    VStack(alignment: .leading, spacing: 14) {
                        CardHeader(icon: "chart.bar.xaxis", title: "近 7 天")
                        if let key = selectedDay, let d = last7.first(where: { Fmt.day($0) == key }) {
                            HStack {
                                Text("\(Fmt.day(d)) · \(Fmt.duration(engine.duration(on: d)))")
                                    .font(.system(size: 15, weight: .medium)).foregroundStyle(Theme.secondaryText)
                                Spacer()
                                if !cal.isDate(d, inSameDayAs: day) {
                                    Button("查看这一天") {
                                        selectedDay = nil
                                        router.showDay(d)
                                    }
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundStyle(Theme.accent)
                                }
                            }
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

                // 当日会话
                Card {
                    VStack(alignment: .leading, spacing: 14) {
                        CardHeader(icon: "list.bullet", title: isToday ? "今日佩戴记录" : "当日佩戴记录")
                        if sessions.isEmpty {
                            EmptyHint(text: "这一天没有记录 · 无记录不等于未佩戴")
                        } else {
                            ForEach(sessions) { s in
                                Button { router.showDevice(s.deviceID) } label: { SessionRow(session: s) }
                                    .buttonStyle(.plain)
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
        .refreshable { await store.reload(force: true) }
        .sheet(isPresented: $showFilter) { DeviceFilterSheet() }
        .onChange(of: router.focusedDay) { selectedHour = nil; selectedDay = nil }
        .simultaneousGesture(
            DragGesture(minimumDistance: 40)
                .onEnded { value in
                    guard abs(value.translation.width) > abs(value.translation.height) * 2 else { return }
                    if value.translation.width > 0, canGoBack { move(day: day, by: -1) }
                    if value.translation.width < 0, !isToday { move(day: day, by: 1) }
                }
        )
    }

    // MARK: Parts

    private var topBar: some View {
        HStack {
            Spacer()
            Button { showFilter = true } label: {
                Image(systemName: "slider.horizontal.3")
                    .font(.system(size: 22))
                    .foregroundStyle(store.isFiltered ? Theme.accent : .white.opacity(0.8))
                    .frame(width: 44, height: 44)
            }
            .accessibilityLabel("筛选耳机")
        }
    }

    private func dayNavigator(day: Date, isToday: Bool, canGoBack: Bool) -> some View {
        HStack(spacing: 12) {
            navButton("chevron.left", label: "前一天", enabled: canGoBack) { move(day: day, by: -1) }
            Spacer()
            if !isToday {
                Button {
                    withAnimation(.snappy) { router.focusedDay = nil }
                } label: {
                    Label("回到今天", systemImage: "arrow.uturn.backward")
                        .font(.system(size: 15, weight: .semibold))
                        .padding(.horizontal, 14).padding(.vertical, 8)
                        .background(Capsule().fill(.white.opacity(0.1)))
                }
                .foregroundStyle(Theme.accent)
            }
            Spacer()
            navButton("chevron.right", label: "后一天", enabled: !isToday) { move(day: day, by: 1) }
        }
    }

    private func navButton(_ symbol: String, label: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 18, weight: .semibold))
                .frame(width: 40, height: 40)
                .background(Circle().fill(.white.opacity(0.08)))
        }
        .foregroundStyle(.white)
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.25)
        .accessibilityLabel(label)
    }

    private func move(day: Date, by offset: Int) {
        let cal = Calendar.stats
        guard let target = cal.date(byAdding: .day, value: offset, to: day) else { return }
        withAnimation(.snappy) {
            router.focusedDay = cal.isDateInToday(target) ? nil : target
        }
    }

    private func title(for day: Date, isToday: Bool, cal: Calendar) -> String {
        if isToday { return "今天" }
        if cal.isDateInYesterday(day) { return "昨天" }
        return Fmt.day(day)
    }

    private var selectedHourCaption: String? {
        selectedHour.map { "\($0):00 – \($0):59" }
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
    var showsDate = false

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
                Text(showsDate ? Fmt.sessionRange(session) : Fmt.timeRange(session))
                    .font(.system(size: 14)).foregroundStyle(Theme.secondaryText)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 3) {
                Text(Fmt.shortDuration(session.duration))
                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                    .foregroundStyle(Theme.accent)
                if let level = session.averageLevel {
                    Text("\(Int(level.rounded())) dB")
                        .font(.system(size: 12)).foregroundStyle(Theme.tertiaryText)
                }
            }
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}
