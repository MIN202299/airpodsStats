import SwiftUI

@main
struct AirPodsStatsApp: App {
    @State private var store = UsageStore()
    @State private var router = AppRouter()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            Group {
                if store.hasOnboarded {
                    ContentView()
                        .task { await store.reload(force: true) }
                } else {
                    OnboardingView()
                }
            }
            .environment(store)
            .environment(router)
            .preferredColorScheme(.dark)
            .onChange(of: scenePhase) { _, phase in
                // 回到前台时刷新（60 秒内不重复读取）
                if phase == .active, store.hasOnboarded {
                    Task { await store.reload(force: false) }
                }
            }
        }
    }
}

struct ContentView: View {
    @Environment(AppRouter.self) private var router

    var body: some View {
        @Bindable var router = router
        TabView(selection: $router.tab) {
            TodayView()
                .tabItem { Label("今天", systemImage: "square.grid.2x2") }
                .tag(AppRouter.Tab.today)
            StatsView()
                .tabItem { Label("统计", systemImage: "chart.bar.fill") }
                .tag(AppRouter.Tab.stats)
            DevicesView()
                .tabItem { Label("设备", systemImage: "airpodspro") }
                .tag(AppRouter.Tab.devices)
        }
        .tint(Color(red: 0.45, green: 0.62, blue: 0.95))
    }
}
