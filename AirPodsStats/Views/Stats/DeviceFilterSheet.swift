import SwiftUI

struct DeviceFilterSheet: View {
    @Environment(UsageStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Button {
                        store.selectedDeviceIDs = []
                    } label: {
                        row(title: "全部耳机", symbol: "headphones", checked: store.selectedDeviceIDs.isEmpty)
                    }
                    Button {
                        store.selectedDeviceIDs = store.airPodsDeviceIDs
                    } label: {
                        row(title: "仅 AirPods", symbol: "airpodspro",
                            checked: !store.airPodsDeviceIDs.isEmpty && store.selectedDeviceIDs == store.airPodsDeviceIDs)
                    }
                    .disabled(store.airPodsDeviceIDs.isEmpty)
                }
                Section("按耳机筛选") {
                    if store.devices.isEmpty {
                        Text("还没有读取到耳机").foregroundStyle(.secondary)
                    }
                    ForEach(store.sortedDevices) { device in
                        Button {
                            var set = store.selectedDeviceIDs
                            if set.contains(device.id) { set.remove(device.id) } else { set.insert(device.id) }
                            store.selectedDeviceIDs = set
                        } label: {
                            row(title: store.displayName(for: device.id), symbol: device.kind.symbol,
                                checked: store.selectedDeviceIDs.contains(device.id))
                        }
                    }
                }
            }
            .navigationTitle("筛选")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("完成") { dismiss() } }
            }
        }
        .presentationDetents([.medium, .large])
        .preferredColorScheme(.dark)
    }

    private func row(title: String, symbol: String, checked: Bool) -> some View {
        HStack {
            Image(systemName: symbol).frame(width: 28)
            Text(title).foregroundStyle(.primary)
            Spacer()
            if checked { Image(systemName: "checkmark").foregroundStyle(.tint) }
        }
    }
}
