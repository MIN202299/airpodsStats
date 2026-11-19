import SwiftUI

struct StatsView: View {
    @Environment(UsageStore.self) private var store
    @State private var period: PeriodKind = .year
    @State private var anchor: Date = .now
    @State private var selectedBar: String?
    @State private var showFilter = false

    var body: some View {
        let engine = store.engine
        let summary = engine.summary(for: period, containing: anchor)

        ScrollView {
            LazyVStack(spacing: 18, pinnedViews: [.sectionHeaders]) {
                header
                RecordsSection(engine: engine)
                Section {
                    PeriodTotalCard(summary: summary, selectedBar: $selectedBar)
                    PeriodOverview(summary: summary)
                } header: {
                    periodHeader(engine: engine, summary: summary)
                }
            }
            .screenPadding()
            .padding(.bottom, 30)
        }
        .scrollIndicators(.hidden)
        .background(GridBackground())
        .sheet(isPresented: $showFilter) { DeviceFilterSheet() }
        .onChange(of: period) { selectedBar = nil }
        .onChange(of: anchor) { selectedBar = nil }
        .refreshable { await store.reload() }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                Spacer()
                Button { showFilter = true } label: {
                    Image(systemName: "slider.horizontal.3")
                        .font(.system(size: 24, weight: .regular))
                        .foregroundStyle(store.isFiltered ? Theme.accent : .white.opacity(0.8))
                        .symbolVariant(store.isFiltered ? .fill : .none)
                }
                .accessibilityLabel("筛选耳机")
            }
            LargeTitle(title: "统计")
            SectionTitle(title: "个人纪录", trailing: store.dataSource == .demo ? "示例数据" : "已读取历史")
        }
    }

    private func periodHeader(engine: StatsEngine, summary: PeriodSummary) -> some View {
        VStack(spacing: 14) {
            SegmentedPicker(items: PeriodKind.allCases, selection: $period, title: \.title)
            HStack {
                Button { anchor = engine.shift(anchor, kind: period, by: -1) } label: {
                    Image(systemName: "chevron.left").font(.system(size: 22, weight: .medium))
                        .frame(width: 44, height: 44)
                }
                .disabled(!engine.canShift(anchor, kind: period, by: -1))
                .opacity(engine.canShift(anchor, kind: period, by: -1) ? 1 : 0.25)
                Spacer()
                Text(summary.title)
                    .font(.system(size: 19, weight: .semibold))
                    .contentTransition(.numericText())
                    .onTapGesture { withAnimation { anchor = .now } }
                Spacer()
                Button { anchor = engine.shift(anchor, kind: period, by: 1) } label: {
                    Image(systemName: "chevron.right").font(.system(size: 22, weight: .medium))
                        .frame(width: 44, height: 44)
                }
                .disabled(!engine.canShift(anchor, kind: period, by: 1))
                .opacity(engine.canShift(anchor, kind: period, by: 1) ? 1 : 0.25)
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
    @Environment(UsageStore.self) private var store
    var engine: StatsEngine

    var body: some View {
        let r = engine.records()
        let columns = [GridItem(.flexible(), spacing: 14), GridItem(.flexible(), spacing: 14)]

        VStack(spacing: 14) {
            LazyVGrid(columns: columns, spacing: 14) {
                RecordCard(icon: "sun.max", title: "单日佩戴最长",
                           footnote: r.bestDay.map { Fmt.day($0.day) } ?? "暂无记录") {
                    DurationText(seconds: r.bestDay?.duration ?? 0, size: 40)
                }
                RecordCard(icon: "timer", title: "单次佩戴最长",
                           footnote: r.longestSession.map { Fmt.sessionRange($0) } ?? "暂无记录") {
                    DurationText(seconds: r.longestSession?.duration ?? 0, size: 40, color: Color(red: 0.72, green: 0.75, blue: 0.92))
                }
                RecordCard(icon: "calendar.badge.checkmark", title: "连续记录最长",
                           footnote: r.longestStreak.map { Fmt.dayRange($0.start, $0.end) } ?? "暂无记录") {
                    NumberUnitText(value: "\(r.longestStreak?.days ?? 0)", unit: "天", size: 40, color: .white.opacity(0.85))
                }
                RecordCard(icon: "calendar", title: "单月佩戴最长",
                           footnote: r.bestMonth.map { Fmt.month($0.month) } ?? "暂无记录") {
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
    @ViewBuilder var value: Value

    var body: some View {
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
}

struct TopDeviceCard: View {
    @Environment(UsageStore.self) private var store
    var top: DeviceTotal?

    var body: some View {
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
