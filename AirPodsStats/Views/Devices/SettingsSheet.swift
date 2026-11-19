import SwiftUI

struct SettingsSheet: View {
    @Environment(UsageStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @State private var confirmReset = false
    @State private var confirmClear = false

    private var appVersion: String {
        let v = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
        let b = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1"
        return "\(v) (\(b))"
    }

    var body: some View {
        @Bindable var store = store
        NavigationStack {
            Form {
                Section {
                    Picker("数据来源", selection: $store.dataSource) {
                        ForEach(DataSourceKind.allCases) { Text($0.title).tag($0) }
                    }
                    Stepper(value: $store.mergeGapMinutes, in: 1...30) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("会话合并间隔：\(store.mergeGapMinutes) 分钟")
                            Text("相邻记录间隔不超过该值时算作同一次佩戴")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    Button {
                        Task { await store.reload(force: true) }
                    } label: {
                        HStack {
                            Text("重新读取历史")
                            Spacer()
                            if store.isLoading { ProgressView() }
                        }
                    }
                    .disabled(store.isLoading)
                    if let updated = store.lastUpdated {
                        LabeledContent("上次更新", value: "\(Fmt.day(updated)) \(Fmt.time(updated))")
                    }
                    if store.dataSource == .health {
                        Button("在健康 App 中管理权限") {
                            if let url = URL(string: "x-apple-health://") { openURL(url) }
                        }
                    }
                } header: {
                    Text("数据")
                }

                Section {
                    let hidden = store.hiddenDeviceIDs.sorted()
                    let merged = store.mergeTargets.keys.sorted()
                    if hidden.isEmpty && merged.isEmpty {
                        Text("没有隐藏或合并的耳机").foregroundStyle(.secondary)
                    }
                    ForEach(hidden, id: \.self) { id in
                        HStack {
                            Label(store.displayName(for: id), systemImage: "eye.slash")
                            Spacer()
                            Button("恢复") { store.setHidden(false, for: id) }
                        }
                    }
                    ForEach(merged, id: \.self) { id in
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(store.displayName(for: id))
                                Text("已合并到 \(store.displayName(for: store.resolvedID(id)))")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Button("拆分") { store.unmerge(id) }
                        }
                    }
                    Button("重置所有耳机的名称、合并与隐藏", role: .destructive) { confirmReset = true }
                } header: {
                    Text("设备管理")
                } footer: {
                    Text("在设备页长按耳机卡片，或在详情页点“编辑”，可以重命名、合并或隐藏耳机。")
                }

                Section {
                    ShareLink(item: store.export, preview: SharePreview("耳机佩戴记录.csv")) {
                        Label("导出佩戴记录（CSV）", systemImage: "square.and.arrow.up")
                    }
                    .disabled(store.allSessions.isEmpty)
                    Button("清除本地缓存并重新读取", role: .destructive) { confirmClear = true }
                } header: {
                    Text("数据管理")
                } footer: {
                    Text("缓存只用于加快启动，清除后不会影响健康 App 中的数据。")
                }

                Section("统计方式") {
                    Text("iOS 不开放 AirPods 的入耳检测记录。本应用读取「健康」App 中的“耳机音频级别”历史：耳机播放音频时系统会持续写入带设备名称和音量的样本，相邻样本合并后近似为一次佩戴。只开降噪而不播放音频的时段不会被记录，因此“无记录不等于未佩戴”。")
                        .font(.footnote).foregroundStyle(.secondary)
                    Text("所有数据只在本机处理，不会上传到任何服务器。")
                        .font(.footnote).foregroundStyle(.secondary)
                }

                Section {
                    LabeledContent("版本", value: appVersion)
                }
            }
            .navigationTitle("设置")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("完成") { dismiss() } }
            }
            .confirmationDialog("重置所有耳机设置？", isPresented: $confirmReset, titleVisibility: .visible) {
                Button("重置", role: .destructive) { store.resetDeviceCustomizations() }
            } message: {
                Text("名称、合并、隐藏和筛选都会恢复默认。")
            }
            .confirmationDialog("清除本地缓存？", isPresented: $confirmClear, titleVisibility: .visible) {
                Button("清除并重新读取", role: .destructive) { Task { await store.clearCacheAndReload() } }
            }
        }
        .preferredColorScheme(.dark)
    }
}
