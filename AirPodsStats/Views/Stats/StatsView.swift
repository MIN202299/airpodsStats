import SwiftUI

struct StatsView: View {
    @Environment(UsageStore.self) private var store
    @Environment(AppRouter.self) private var router
    @State private var selectedBar: String?
    @State private var showFilter = false

    private static let periodSectionID = "period-section"

    var body: some View {
        @Bindable var router = router
        let engine = store.engine
        let summary = engine.summary(for: router.statsPeriod, containing: router.statsAnchor)

        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 18, pinnedViews: [.sectionHeaders]) {
                    header
                    StatusBanner()
                    RecordsSection(records: store.records)
                    Color.clear.frame(height: 0).id(Self.periodSectionID)
                    Section {
                        PeriodTotalCard(summary: summary, selectedBar: $selectedBar) { bar in
                            drillDown(from: bar, kind: summary.kind)
                        }
                        PeriodOverview(summary: summary)
                    } header: {
                        periodHeader(engine: engine, summary: summary, period: $router.statsPeriod)
                    }
                }
                .screenPadding()
                .padding(.bottom, 30)
            }
            .scrollIndicators(.hidden)
            .onChange(of: router.statsScrollRequest) {
                withAnimation(.snappy) { proxy.scrollTo(Self.periodSectionID, anchor: .top) }
            }
        }
        .background(GridBackground())
        .sheet(isPresented: $showFilter) { DeviceFilterSheet() }
        .onChange(of: router.statsPeriod) { selectedBar = nil }
        .onChange(of: router.statsAnchor) { selectedBar = nil }
        .refreshable { await store.reload(force: true) }
    }

    /// 年 → 月 → 日 逐级下钻
    private func drillDown(from bar: PeriodBar, kind: PeriodKind) {
        selectedBar = nil
        switch kind {
        case .all: router.showPeriod(.year, containing: bar.start)
        case .year: router.showPeriod(.month, containing: bar.start)
        case .week, .month: router.showDay(bar.start)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                Spacer()
                Button { showFilter = true } label: {
                    Image(systemName: "slider.horizontal.3")
                        .font(.system(size: 24, weight: .regular))
                        .foregroundStyle(store.isFiltered ? Theme.accent : .white.opacity(0.8))
                        .frame(width: 44, height: 44)
                }
                .accessibilityLabel("筛选耳机")
            }
            LargeTitle(title: "统计")
            FilterChip()
            SectionTitle(title: "个人纪录", trailing: store.dataSource == .demo ? "示例数据" : "已读取历史")
        }
    }

    private func periodHeader(engine: StatsEngine, summary: PeriodSummary, period: Binding<PeriodKind>) -> some View {
        let canBack = engine.canShift(router.statsAnchor, kind: period.wrappedValue, by: -1)
        let canForward = engine.canShift(router.statsAnchor, kind: period.wrappedValue, by: 1)
        return VStack(spacing: 14) {
            SegmentedPicker(items: PeriodKind.allCases, selection: period, title: \.title)
            HStack {
                Button {
                    router.statsAnchor = engine.shift(router.statsAnchor, kind: period.wrappedValue, by: -1)
                } label: {
                    Image(systemName: "chevron.left").font(.system(size: 22, weight: .medium))
                        .frame(width: 44, height: 44)
                }
                .disabled(!canBack)
                .opacity(canBack ? 1 : 0.25)
                .accessibilityLabel("上一个周期")
                Spacer()
                Button {
                    withAnimation { router.statsAnchor = .now }
                } label: {
                    Text(summary.title)
                        .font(.system(size: 19, weight: .semibold))
                        .contentTransition(.numericText())
                }
                .accessibilityHint("回到当前周期")
                Spacer()
                Button {
                    router.statsAnchor = engine.shift(router.statsAnchor, kind: period.wrappedValue, by: 1)
                } label: {
                    Image(systemName: "chevron.right").font(.system(size: 22, weight: .medium))
                        .frame(width: 44, height: 44)
                }
                .disabled(!canForward)
                .opacity(canForward ? 1 : 0.25)
                .accessibilityLabel("下一个周期")
            }
            .foregroundStyle(.white)
        }
        .padding(.vertical, 8)
        .background {
            Rectangle()
                .fill(.ultraThinMaterial)
                .environment(\.colorScheme, .dark)
                .padding(.horizontal, -20)
                .ignoresSafeArea(edges: .top)
        }
    }
}

// MARK: - 个人纪录

struct RecordsSection: View {
    @Environment(AppRouter.self) private var router
    var records: PersonalRecords

    var body: some View {
        let r = records
        let columns = [GridItem(.flexible(), spacing: 14), GridItem(.flexible(), spacing: 14)]

        VStack(spacing: 14) {
            LazyVGrid(columns: columns, spacing: 14) {
                RecordCard(icon: "sun.max", title: "单日佩戴最长",
                           footnote: r.bestDay.map { Fmt.day($0.day) } ?? "暂无记录",
                           action: r.bestDay.map { d -> () -> Void in { router.showDay(d.day) } }) {
                    DurationText(seconds: r.bestDay?.duration ?? 0, size: 40)
                }
                RecordCard(icon: "timer", title: "单次佩戴最长",
                           footnote: r.longestSession.map { Fmt.sessionRange($0) } ?? "暂无记录",
                           action: r.longestSession.map { s -> () -> Void in { router.showDay(s.start) } }) {
                    DurationText(seconds: r.longestSession?.duration ?? 0, size: 40, color: Color(red: 0.72, green: 0.75, blue: 0.92))
                }
                RecordCard(icon: "calendar.badge.checkmark", title: "连续记录最长",
                           footnote: r.longestStreak.map { Fmt.dayRange($0.start, $0.end) } ?? "暂无记录",
                           action: r.longestStreak.map { s -> () -> Void in { router.showPeriod(.month, containing: s.start) } }) {
                    NumberUnitText(value: "\(r.longestStreak?.days ?? 0)", unit: "天", size: 40, color: .white.opacity(0.85))
                }
                RecordCard(icon: "calendar", title: "单月佩戴最长",
                           footnote: r.bestMonth.map { Fmt.month($0.month) } ?? "暂无记录",
                           action: r.bestMonth.map { m -> () -> Void in { router.showPeriod(.month, containing: m.month) } }) {
                    DurationText(seconds: r.bestMonth?.duration ?? 0, size: 40)
                }
            }
            TopDeviceCard(top: r.topDevice)
        }
    }
}

struct RecordCard<Value: View>: View {
    var icon: String
    var title: String
    var footnote: String
    var action: (() -> Void)? = nil
    @ViewBuilder var value: Value

    var body: some View {
        Button { action?() } label: {
            Card(padding: 18) {
                VStack(alignment: .leading, spacing: 18) {
                    CardHeader(icon: icon, title: title)
                    value
                    Text(footnote)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(Theme.secondaryText)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
            }
        }
        .buttonStyle(PressableCardStyle())
        .disabled(action == nil)
        .accessibilityElement(children: .combine)
    }
}

/// 卡片按下时轻微缩小
struct PressableCardStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.snappy(duration: 0.18), value: configuration.isPressed)
    }
}

struct TopDeviceCard: View {
    @Environment(UsageStore.self) private var store
    @Environment(AppRouter.self) private var router
    var top: DeviceTotal?

    var body: some View {
        Button {
            if let top { router.showDevice(top.deviceID) }
        } label: {
            content
        }
        .buttonStyle(PressableCardStyle())
        .disabled(top == nil)
    }

    private var content: some View {
        Card {
            VStack(alignment: .leading, spacing: 16) {
                CardHeader(icon: "headphones", title: "最常戴耳机")
                if let top {
                    HStack(spacing: 18) {
                        DeviceImage(kind: store.kind(for: top.deviceID), size: 120)
                        VStack(alignment: .leading, spacing: 6) {
                            Text(store.displayName(for: top.deviceID))
                                .font(.system(size: 21, weight: .semibold))
                                .foregroundStyle(.white)
                                .lineLimit(2)
                                .minimumScaleFactor(0.8)
                            DurationText(seconds: top.duration, size: 40, color: Theme.accent)
                            Text(store.dataSource == .demo ? "示例数据累计佩戴" : "已读取历史累计佩戴")
                                .font(.system(size: 14, weight: .medium))
                                .foregroundStyle(Theme.secondaryText)
                        }
                    }
                } else {
                    EmptyHint(text: "还没有读取到耳机记录")
                }
            }
        }
    }
}

/// 用 SF Symbols 画一个“耳机产品图”
struct DeviceImage: View {
    var kind: DeviceKind
    var size: CGFloat

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.26, style: .continuous)
                .fill(LinearGradient(colors: [.white, Color(white: 0.84)], startPoint: .top, endPoint: .bottom))
                .shadow(color: .black.opacity(0.4), radius: 8, y: 4)
            Image(systemName: kind.caseSymbol)
                .resizable()
                .scaledToFit()
                .foregroundStyle(Color(white: 0.55))
                .padding(size * 0.2)
        }
        .frame(width: size, height: size * 0.88)
    }
}
