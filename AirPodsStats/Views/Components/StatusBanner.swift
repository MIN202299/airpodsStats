import SwiftUI

/// 加载中 / 读取失败 / 没有数据 / 筛选后为空 的统一提示，三个标签页共用
struct StatusBanner: View {
    enum Style { case blue, night }

    @Environment(UsageStore.self) private var store
    @Environment(\.openURL) private var openURL
    var style: Style = .blue

    var body: some View {
        if store.isLoading && !store.hasData {
            HStack(spacing: 10) {
                ProgressView().tint(.white)
                Text(store.dataSource == .demo ? "正在生成示例数据…" : "正在读取健康数据…")
                    .foregroundStyle(.white.opacity(0.65))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
        } else if case .failed(let message) = store.state {
            container {
                Label("读取失败", systemImage: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                Text(store.hasData ? "\(message)。当前显示的是上次读取的数据。" : message)
                    .font(.subheadline).foregroundStyle(.white.opacity(0.65))
                HStack {
                    Button("重试") { Task { await store.reload(force: true) } }
                    if store.dataSource == .health && !store.hasData {
                        Button("使用示例数据") { store.dataSource = .demo }
                    }
                }
                .buttonStyle(.bordered).tint(.white)
            }
        } else if store.state == .loaded && store.allSessions.isEmpty && store.dataSource == .health {
            container {
                Label("没有读取到耳机记录", systemImage: "info.circle.fill").foregroundStyle(Theme.accent)
                Text("请在「健康」App › 共享 › App 与服务 › 耳机统计 中允许读取“耳机音频级别”，并确认戴着耳机播放过音频。")
                    .font(.subheadline).foregroundStyle(.white.opacity(0.65))
                HStack {
                    Button("打开健康 App") {
                        if let url = URL(string: "x-apple-health://") { openURL(url) }
                    }
                    Button("先看示例数据") { store.dataSource = .demo }
                }
                .buttonStyle(.bordered).tint(.white)
            }
        } else if store.isFiltered && store.engine.isEmpty && !store.allSessions.isEmpty {
            container {
                Label("当前筛选下没有记录", systemImage: "line.3.horizontal.decrease.circle").foregroundStyle(Theme.accent)
                Button("显示全部耳机") { store.selectedDeviceIDs = [] }
                    .buttonStyle(.bordered).tint(.white)
            }
        }
    }

    @ViewBuilder
    private func container<C: View>(@ViewBuilder _ content: () -> C) -> some View {
        let inner = VStack(alignment: .leading, spacing: 10) { content() }
        switch style {
        case .blue: Card { inner }
        case .night: NightTile { inner }
        }
    }
}

/// 筛选状态提示条（统计页 / 今天页顶部）
struct FilterChip: View {
    @Environment(UsageStore.self) private var store

    var body: some View {
        if store.isFiltered {
            let names = store.selectedDeviceIDs.map { store.displayName(for: $0) }.sorted()
            HStack(spacing: 8) {
                Image(systemName: "line.3.horizontal.decrease.circle.fill")
                Text(names.count == 1 ? "仅统计 \(names[0])" : "仅统计 \(names.count) 副耳机")
                    .lineLimit(1)
                Spacer(minLength: 4)
                Button {
                    store.selectedDeviceIDs = []
                } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(.white.opacity(0.6))
                }
                .accessibilityLabel("清除筛选")
            }
            .font(.system(size: 14, weight: .medium))
            .foregroundStyle(Theme.accent)
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(Capsule().fill(.white.opacity(0.08)))
        }
    }
}
