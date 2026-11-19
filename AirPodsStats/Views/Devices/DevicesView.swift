import SwiftUI

/// 设备页：粒子球总时长 + 可左右滑动的设备卡片
struct DevicesView: View {
    @Environment(UsageStore.self) private var store
    @Environment(AppRouter.self) private var router
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage("devicePeriod") private var periodRaw = DevicePeriod.last7.rawValue
    @State private var currentID: String?
    @State private var editing: HeadphoneDevice?
    @State private var showSettings = false
    @State private var isVisible = false

    private var period: DevicePeriod { DevicePeriod(rawValue: periodRaw) ?? .last7 }

    struct Entry: Identifiable {
        var id: String
        var duration: TimeInterval
        var share: Double
    }

    var body: some View {
        let engine = store.allDevicesEngine
        let interval = engine.interval(of: period)
        let totals = engine.deviceTotals(in: interval)
        let sum = totals.map(\.duration).reduce(0, +)
        let entries = makeEntries(totals: totals, sum: sum)

        @Bindable var router = router
        NavigationStack(path: $router.devicePath) {
            GeometryReader { geo in
                ScrollView {
                    VStack(spacing: 0) {
                        header
                        StatusBanner(style: .night)
                            .padding(.horizontal, 20)
                            .padding(.top, 8)
                        sphere(total: sum, width: geo.size.width)
                        if entries.isEmpty {
                            if store.hasData && !store.isLoading {
                                GlassCard { EmptyHint(text: "还没有读取到耳机记录") }
                                    .padding(.horizontal, 40)
                            }
                        } else {
                            carousel(entries: entries, width: geo.size.width)
                            pageDots(entries: entries)
                                .padding(.top, 26)
                            Text("轻点查看记录 · 长按卡片管理设备")
                                .font(.system(size: 14))
                                .foregroundStyle(.white.opacity(0.45))
                                .padding(.top, 18)
                        }
                    }
                    .padding(.bottom, 40)
                }
                .scrollIndicators(.hidden)
                .refreshable { await store.reload(force: true) }
            }
            .background(NightBackground(horizon: 0.47))
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(for: DeviceRoute.self) { route in
                switch route {
                case .detail(let id): DeviceDetailView(deviceID: id, period: period)
                case .history(let id): SessionHistoryView(deviceID: id)
                }
            }
            .sheet(item: $editing) { DeviceEditSheet(device: $0) }
            .sheet(isPresented: $showSettings) { SettingsSheet() }
            .onChange(of: entries.map(\.id)) { _, ids in
                if let id = currentID, ids.contains(id) { return }
                currentID = ids.first
            }
            .onAppear {
                isVisible = true
                if currentID == nil { currentID = entries.first?.id }
            }
            .onDisappear { isVisible = false }
        }
    }

    // MARK: Parts

    private var header: some View {
        ZStack {
            Text("设备")
                .font(.system(size: 19, weight: .bold))
                .foregroundStyle(.white.opacity(0.9))
            HStack {
                Button { showSettings = true } label: {
                    Image(systemName: "gearshape")
                        .font(.system(size: 19, weight: .medium))
                        .frame(width: 40, height: 40)
                }
                .accessibilityLabel("设置")
                Spacer()
                Menu {
                    Picker("时间范围", selection: $periodRaw) {
                        ForEach(DevicePeriod.allCases) { Text($0.title).tag($0.rawValue) }
                    }
                } label: {
                    HStack(spacing: 6) {
                        Text(period.title)
                        Image(systemName: "chevron.down").font(.system(size: 15, weight: .semibold))
                    }
                    .font(.system(size: 18, weight: .medium))
                }
            }
            .foregroundStyle(.white.opacity(0.9))
        }
        .padding(.horizontal, 20)
        .padding(.top, 8)
    }

    private func sphere(total: TimeInterval, width: CGFloat) -> some View {
        let side = min(width * 0.82, 360)
        return ZStack {
            ParticleSphere(paused: !isVisible || scenePhase != .active || !router.devicePath.isEmpty)
                .frame(width: side, height: side)
            VStack(spacing: 8) {
                DurationText(seconds: total, size: 54)
                Text(period.totalCaption)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(.white.opacity(0.65))
            }
        }
        .frame(height: side + 50)
    }

    private func carousel(entries: [Entry], width: CGFloat) -> some View {
        let cardWidth = min(width * 0.64, 300)
        return ScrollView(.horizontal) {
            LazyHStack(spacing: 16) {
                ForEach(entries) { e in
                    Button { router.devicePath.append(.detail(e.id)) } label: {
                        DeviceGlassCard(name: store.displayName(for: e.id), kind: store.kind(for: e.id),
                                        duration: e.duration, share: e.share)
                    }
                    .buttonStyle(.plain)
                    .frame(width: cardWidth)
                    .contextMenu { menu(for: e.id) }
                    .scrollTransition(axis: .horizontal) { content, phase in
                        content
                            .scaleEffect(phase.isIdentity ? 1 : 0.84)
                            .opacity(phase.isIdentity ? 1 : 0.55)
                    }
                    .id(e.id)
                }
            }
            .scrollTargetLayout()
        }
        .contentMargins(.horizontal, (width - cardWidth) / 2, for: .scrollContent)
        .scrollTargetBehavior(.viewAligned)
        .scrollPosition(id: $currentID)
        .scrollIndicators(.hidden)
        .scrollClipDisabled()
    }

    private func pageDots(entries: [Entry]) -> some View {
        let active = currentID ?? entries.first?.id
        return HStack(spacing: 14) {
            ForEach(entries) { e in
                Circle()
                    .fill(.white.opacity(e.id == active ? 0.95 : 0.25))
                    .frame(width: 9, height: 9)
                    .onTapGesture { withAnimation(.snappy) { currentID = e.id } }
            }
        }
    }

    @ViewBuilder
    private func menu(for id: String) -> some View {
        Button { router.devicePath.append(.detail(id)) } label: { Label("查看详情", systemImage: "chart.bar") }
        Button { router.devicePath.append(.history(id)) } label: { Label("全部佩戴记录", systemImage: "list.bullet") }
        Button { editing = store.devices[id] } label: { Label("编辑 / 合并 / 隐藏", systemImage: "pencil") }
        if store.selectedDeviceIDs == [id] {
            Button { store.selectedDeviceIDs = [] } label: { Label("统计全部耳机", systemImage: "headphones") }
        } else {
            Button { store.selectedDeviceIDs = [id] } label: { Label("只统计这副耳机", systemImage: "line.3.horizontal.decrease.circle") }
        }
    }

    /// 本周期有记录的耳机在前，其余耳机（0 时长）排在后面
    private func makeEntries(totals: [DeviceTotal], sum: TimeInterval) -> [Entry] {
        var result = totals.map { Entry(id: $0.deviceID, duration: $0.duration, share: sum > 0 ? $0.duration / sum : 0) }
        let seen = Set(result.map(\.id))
        for d in store.sortedDevices where !seen.contains(d.id) {
            result.append(Entry(id: d.id, duration: 0, share: 0))
        }
        return result
    }
}

