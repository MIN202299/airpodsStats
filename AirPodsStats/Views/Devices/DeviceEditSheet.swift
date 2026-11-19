import SwiftUI

/// 编辑耳机：重命名 / 合并到另一副 / 在统计中隐藏
struct DeviceEditSheet: View {
    @Environment(UsageStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    var device: HeadphoneDevice

    @State private var name = ""
    @State private var mergeTarget: String?
    @State private var hidden = false
    @State private var showMergeConfirm = false

    private var candidates: [HeadphoneDevice] {
        store.sortedDevices.filter { $0.id != device.id && store.resolvedID($0.id) != device.id }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField(device.rawName, text: $name)
                        .submitLabel(.done)
                } header: {
                    Text("名称")
                } footer: {
                    Text("留空则使用健康 App 中的原始名称。")
                }

                Section {
                    Picker("合并到", selection: $mergeTarget) {
                        Text("不合并").tag(String?.none)
                        ForEach(candidates) { d in
                            Text(store.displayName(for: d.id)).tag(Optional(d.id))
                        }
                    }
                    let sources = store.mergedSources(into: device.id)
                    if !sources.isEmpty {
                        ForEach(sources, id: \.self) { src in
                            HStack {
                                Text(store.displayName(for: src)).foregroundStyle(.secondary)
                                Spacer()
                                Button("拆分") { store.unmerge(src) }
                            }
                        }
                    }
                } header: {
                    Text("合并")
                } footer: {
                    Text("给 AirPods 改名或系统更新后，同一副耳机可能被识别成两副。合并后两者的记录会算作同一副耳机，可以随时拆分。")
                }

                Section {
                    Toggle("在统计中隐藏", isOn: $hidden)
                } footer: {
                    Text("隐藏后这副耳机的记录不会计入任何统计，可在 设置 › 设备管理 中恢复。")
                }

                Section("信息") {
                    LabeledContent("原始名称", value: device.rawName)
                    if let m = device.manufacturer, !m.isEmpty { LabeledContent("厂商", value: m) }
                    if let model = device.model, !model.isEmpty { LabeledContent("型号", value: model) }
                }
            }
            .navigationTitle("编辑耳机")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        if mergeTarget != nil && mergeTarget != store.mergeTargets[device.id] {
                            showMergeConfirm = true
                        } else {
                            save()
                        }
                    }
                    .fontWeight(.semibold)
                }
            }
            .confirmationDialog("确定合并？", isPresented: $showMergeConfirm, titleVisibility: .visible) {
                Button("合并") { save() }
                Button("取消", role: .cancel) {}
            } message: {
                Text("「\(store.displayName(for: device.id))」的记录将并入「\(mergeTarget.map { store.displayName(for: $0) } ?? "")」。")
            }
            .onAppear {
                name = store.aliases[device.id] ?? ""
                mergeTarget = store.mergeTargets[device.id]
                hidden = store.hiddenDeviceIDs.contains(device.id)
            }
        }
        .presentationDetents([.large])
        .preferredColorScheme(.dark)
    }

    private func save() {
        store.setAlias(name, for: device.id)
        if mergeTarget != store.mergeTargets[device.id] {
            if let target = mergeTarget {
                store.merge(device.id, into: target)
            } else {
                store.unmerge(device.id)
            }
        }
        if hidden != store.hiddenDeviceIDs.contains(device.id) {
            store.setHidden(hidden, for: device.id)
        }
        dismiss()
    }
}
