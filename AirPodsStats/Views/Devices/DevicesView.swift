import SwiftUI

struct DevicesView: View {
    @Environment(UsageStore.self) private var store
    @State private var renaming: HeadphoneDevice?

    var body: some View {
        @Bindable var store = store
        let totals = store.allDevicesEngine.deviceTotals()
        let sum = totals.map(\.duration).reduce(0, +)
        let grand = max(1, sum)

        ScrollView {
            VStack(spacing: 18) {
                LargeTitle(title: "设备", subtitle: "\(totals.count) 副耳机 · 共 \(Fmt.duration(sum))")
                    .padding(.top, 40)

                if totals.isEmpty {
                    Card { EmptyHint(text: "还没有读取到耳机记录") }
                }

                ForEach(totals) { t in
                    DeviceCard(total: t, share: t.duration / grand) {
                        renaming = store.devices[t.deviceID]
                    }
                }

                SectionTitle(title: "设置").padding(.top, 8)
                Card {
                    VStack(alignment: .leading, spacing: 18) {
                        HStack {
                            Text("数据来源").foregroundStyle(.white)
                            Spacer()
                            Picker("数据来源", selection: $store.dataSource) {
                                ForEach(DataSourceKind.allCases) { Text($0.title).tag($0) }
                            }
                            .pickerStyle(.segmented)
                            .frame(width: 190)
                        }
                        Divider().overlay(.white.opacity(0.08))
                        Stepper(value: $store.mergeGapMinutes, in: 1...30) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("会话合并间隔：\(store.mergeGapMinutes) 分钟").foregroundStyle(.white)
                                Text("间隔小于该值的记录视为同一次佩戴")
                                    .font(.caption).foregroundStyle(Theme.secondaryText)
                            }
                        }
                        Divider().overlay(.white.opacity(0.08))
                        Button {
                            Task { await store.reload() }
                        } label: {
                            HStack {
                                Label("重新读取历史", systemImage: "arrow.clockwise")
                                Spacer()
                                if store.state == .loading { ProgressView().tint(.white) }
                            }
                        }
                        .foregroundStyle(Theme.accent)
                        .disabled(store.state == .loading)
                    }
                }

                Card {
                    VStack(alignment: .leading, spacing: 8) {
                        Label("统计方式", systemImage: "info.circle").foregroundStyle(.white)
                        Text("iOS 不开放 AirPods 的佩戴传感器记录。本应用读取「健康」App 中的“耳机音频级别”历史：耳机播放音频时系统会持续写入带设备名称的样本，相邻样本合并后近似为一次佩戴。只开降噪而不播放音频的时段不会被记录，因此“无记录不等于未佩戴”。所有数据仅在本机处理。")
                            .font(.footnote)
                            .foregroundStyle(Theme.secondaryText)
                    }
                }
            }
            .screenPadding()
            .padding(.bottom, 30)
        }
        .scrollIndicators(.hidden)
        .background(GridBackground())
        .sheet(item: $renaming) { device in
            RenameSheet(device: device)
        }
    }
}

struct DeviceCard: View {
    @Environment(UsageStore.self) private var store
    var total: DeviceTotal
    var share: Double
    var onRename: () -> Void

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 16) {
                    DeviceImage(kind: store.kind(for: total.deviceID), size: 84)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(store.displayName(for: total.deviceID))
                            .font(.system(size: 18, weight: .semibold)).foregroundStyle(.white)
                            .lineLimit(2)
                        DurationText(seconds: total.duration, size: 32, color: Theme.accent)
                    }
                    Spacer(minLength: 0)
                    Button(action: onRename) {
                        Image(systemName: "pencil").foregroundStyle(.white.opacity(0.7))
                            .frame(width: 36, height: 36)
                            .background(Circle().fill(.white.opacity(0.08)))
                    }
                    .accessibilityLabel("重命名")
                }
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(.white.opacity(0.1))
                        Capsule().fill(Theme.accent.opacity(0.85)).frame(width: geo.size.width * share)
                    }
                }
                .frame(height: 6)
                HStack {
                    info("占比", String(format: "%.0f%%", share * 100))
                    Spacer()
                    info("佩戴次数", "\(total.sessionCount)")
                    Spacer()
                    info("首次记录", Fmt.day(total.firstUsed))
                    Spacer()
                    info("最近使用", Fmt.day(total.lastUsed))
                }
            }
        }
    }

    private func info(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.caption2).foregroundStyle(Theme.tertiaryText)
            Text(value).font(.system(size: 13, weight: .medium)).foregroundStyle(.white.opacity(0.85))
                .lineLimit(1).minimumScaleFactor(0.7)
        }
    }
}

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
            .navigationTitle("重命名耳机")
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
