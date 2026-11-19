import SwiftUI

/// 设备页：粒子球总时长 + 可左右滑动的设备卡片
struct DevicesView: View {
    @Environment(UsageStore.self) private var store
    @AppStorage("devicePeriod") private var periodRaw = DevicePeriod.last7.rawValue
    @State private var path: [String] = []
    @State private var currentID: String?
    @State private var renaming: HeadphoneDevice?
    @State private var showSettings = false

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

        NavigationStack(path: $path) {
            GeometryReader { geo in
                ScrollView {
                    VStack(spacing: 0) {
                        header
                        sphere(total: sum, width: geo.size.width)
                        if entries.isEmpty {
                            GlassCard { EmptyHint(text: "还没有读取到耳机记录") }
                                .padding(.horizontal, 40)
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
                .scrollBounceBehavior(.basedOnSize)
            }
            .background(NightBackground(horizon: 0.47))
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(for: String.self) { id in
                DeviceDetailView(deviceID: id, period: period)
            }
            .sheet(item: $renaming) { RenameSheet(device: $0) }
            .sheet(isPresented: $showSettings) { SettingsSheet() }
            .onChange(of: entries.map(\.id)) { _, ids in
                if let id = currentID, ids.contains(id) { return }
                currentID = ids.first
            }
            .onAppear { if currentID == nil { currentID = entries.first?.id } }
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
            ParticleSphere()
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
                    Button { path.append(e.id) } label: {
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
        Button { path.append(id) } label: { Label("查看记录", systemImage: "chart.bar") }
        Button { renaming = store.devices[id] } label: { Label("重命名", systemImage: "pencil") }
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

// MARK: - 重命名

struct RenameSheet: View {
    @Environment(UsageStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    var device: HeadphoneDevice
    @State private var name = ""

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField(device.rawName, text: $name)
                } footer: {
                    Text("健康 App 中的原始名称：\(device.rawName)\(device.model.map { "（\($0)）" } ?? "")。留空则恢复原名。")
                }
            }
            .navigationTitle("编辑耳机")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") { store.setAlias(name, for: device.id); dismiss() }
                }
            }
            .onAppear { name = store.aliases[device.id] ?? "" }
        }
        .presentationDetents([.medium])
        .preferredColorScheme(.dark)
    }
}

// MARK: - 设置

struct SettingsSheet: View {
    @Environment(UsageStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        @Bindable var store = store
        NavigationStack {
            Form {
                Section("数据") {
                    Picker("数据来源", selection: $store.dataSource) {
                        ForEach(DataSourceKind.allCases) { Text($0.title).tag($0) }
                    }
                    Stepper(value: $store.mergeGapMinutes, in: 1...30) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("会话合并间隔：\(store.mergeGapMinutes) 分钟")
                            Text("间隔小于该值的记录视为同一次佩戴")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    Button {
                        Task { await store.reload() }
                    } label: {
                        HStack {
                            Text("重新读取历史")
                            Spacer()
                            if store.state == .loading { ProgressView() }
                        }
                    }
                    .disabled(store.state == .loading)
                    if let updated = store.lastUpdated {
                        LabeledContent("上次更新", value: "\(Fmt.day(updated)) \(Fmt.time(updated))")
                    }
                }
                Section("统计方式") {
                    Text("iOS 不开放 AirPods 的佩戴传感器记录。本应用读取「健康」App 中的“耳机音频级别”历史：耳机播放音频时系统会持续写入带设备名称和音量的样本，相邻样本合并后近似为一次佩戴。只开降噪而不播放音频的时段不会被记录，因此“无记录不等于未佩戴”。所有数据仅在本机处理。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("设置")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("完成") { dismiss() } }
            }
        }
        .preferredColorScheme(.dark)
    }
}
