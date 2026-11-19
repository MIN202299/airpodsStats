import SwiftUI

/// 某副耳机的全部佩戴记录，按天分组
struct SessionHistoryView: View {
    @Environment(UsageStore.self) private var store
    @Environment(AppRouter.self) private var router
    var deviceID: String

    struct DayGroup: Identifiable {
        var day: Date
        var sessions: [WearSession]
        var total: TimeInterval
        var id: Date { day }
    }

    var body: some View {
        let groups = makeGroups()

        ScrollView {
            LazyVStack(alignment: .leading, spacing: 14) {
                Text("\(groups.count) 个有记录日 · 共 \(groups.reduce(0) { $0 + $1.sessions.count }) 次")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.white.opacity(0.55))

                if groups.isEmpty {
                    NightTile { EmptyHint(text: "暂无记录") }
                }

                ForEach(groups) { g in
                    NightTile(padding: 16) {
                        VStack(alignment: .leading, spacing: 12) {
                            Button { router.showDay(g.day) } label: {
                                HStack {
                                    Text(Fmt.barDetail(.month, date: g.day, calendar: .stats))
                                        .font(.system(size: 16, weight: .semibold)).foregroundStyle(.white)
                                    Text(Fmt.year(g.day)).font(.system(size: 13)).foregroundStyle(.white.opacity(0.45))
                                    Spacer()
                                    Text(Fmt.shortDuration(g.total))
                                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                                        .foregroundStyle(Night.lavender)
                                    Image(systemName: "chevron.right").font(.system(size: 12, weight: .semibold))
                                        .foregroundStyle(.white.opacity(0.4))
                                }
                            }
                            .buttonStyle(.plain)
                            ForEach(g.sessions) { s in
                                Divider().overlay(.white.opacity(0.08))
                                HStack {
                                    Text(Fmt.timeRange(s)).foregroundStyle(.white.opacity(0.8))
                                    Spacer()
                                    if let l = s.averageLevel {
                                        Text("\(Int(l.rounded())) dB").foregroundStyle(.white.opacity(0.45))
                                    }
                                    Text(Fmt.shortDuration(s.duration)).foregroundStyle(.white.opacity(0.8))
                                        .frame(minWidth: 70, alignment: .trailing)
                                }
                                .font(.system(size: 14))
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 40)
        }
        .scrollIndicators(.hidden)
        .background(NightBackground(horizon: 0.30))
        .navigationTitle(store.displayName(for: deviceID))
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
        .tint(.white)
    }

    /// 跨天会话归到开始那天
    private func makeGroups() -> [DayGroup] {
        let cal = Calendar.stats
        let mine = store.allSessions.filter { $0.deviceID == deviceID }
        let grouped = Dictionary(grouping: mine) { cal.startOfDay(for: $0.start) }
        return grouped.map { day, list in
            let sorted = list.sorted { $0.start > $1.start }
            return DayGroup(day: day, sessions: sorted, total: sorted.reduce(0) { $0 + $1.duration })
        }
        .sorted { $0.day > $1.day }
    }
}
