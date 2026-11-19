import SwiftUI

@main
struct AirPodsStatsApp: App {
    @State private var store = UsageStore()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(store)
                .preferredColorScheme(.dark)
                .task { await store.reload() }
                .onChange(of: scenePhase) { _, phase in
                    if phase == .active, store.state != .loading, store.state != .idle {
                        Task { await store.reload() }
                    }
                }
        }
    }
}

struct ContentView: View {
    @State private var tab: AppTab = .stats

    enum AppTab: Hashable { case today, stats, devices }

    var body: some View {
        TabView(selection: $tab) {
            TodayView()
                .tabItem { Label("今天", systemImage: "square.grid.2x2") }
                .tag(AppTab.today)
            StatsView()
                .tabItem { Label("统计", systemImage: "chart.bar.fill") }
                .tag(AppTab.stats)
            DevicesView()
                .tabItem { Label("设备", systemImage: "airpodspro") }
                .tag(AppTab.devices)
        }
        .tint(Color(red: 0.45, green: 0.62, blue: 0.95))
        .toolbarBackground(.visible, for: .tabBar)
        .toolbarBackground(Color(red: 0.11, green: 0.12, blue: 0.14), for: .tabBar)
    }
}
