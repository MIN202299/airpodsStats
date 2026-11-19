import SwiftUI

/// 首次启动：说明数据来源与隐私，再请求健康权限
struct OnboardingView: View {
    @Environment(UsageStore.self) private var store

    var body: some View {
        GeometryReader { geo in
            ScrollView {
                VStack(spacing: 28) {
                    ZStack {
                        ParticleSphere(count: 380)
                            .frame(width: min(geo.size.width * 0.7, 300), height: min(geo.size.width * 0.7, 300))
                        Image(systemName: "airpodspro")
                            .font(.system(size: 64, weight: .light))
                            .foregroundStyle(.white)
                    }
                    .padding(.top, 30)

                    VStack(spacing: 10) {
                        Text("耳机统计")
                            .font(.system(size: 38, weight: .heavy)).foregroundStyle(.white)
                        Text("看看你每天戴了多久 AirPods")
                            .font(.system(size: 17)).foregroundStyle(.white.opacity(0.65))
                    }

                    VStack(alignment: .leading, spacing: 18) {
                        feature("chart.bar.fill", "每日、每月、每年的佩戴时长与个人纪录")
                        feature("airpodspro", "按耳机分别统计，支持合并、重命名、隐藏")
                        feature("heart.text.square.fill", "读取「健康」App 中的“耳机音频级别”历史")
                        feature("lock.fill", "所有数据只在本机处理，不会上传")
                    }
                    .padding(.horizontal, 8)

                    VStack(spacing: 12) {
                        Button {
                            store.completeOnboarding(using: .health)
                        } label: {
                            Text(store.healthAvailable ? "连接健康 App" : "此设备不支持健康数据")
                                .font(.system(size: 17, weight: .semibold))
                                .frame(maxWidth: .infinity, minHeight: 54)
                                .background(Capsule().fill(.white))
                                .foregroundStyle(.black)
                        }
                        .disabled(!store.healthAvailable)

                        Button("先看看示例数据") {
                            store.completeOnboarding(using: .demo)
                        }
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(.white.opacity(0.8))
                        .frame(minHeight: 44)

                        Text("统计的是戴着耳机播放音频的时长，只开降噪不放音频的时间不会被记录。")
                            .font(.footnote)
                            .foregroundStyle(.white.opacity(0.45))
                            .multilineTextAlignment(.center)
                    }
                }
                .padding(.horizontal, 28)
                .padding(.bottom, 30)
                .frame(minHeight: geo.size.height)
            }
            .scrollBounceBehavior(.basedOnSize)
        }
        .background(NightBackground(horizon: 0.62))
    }

    private func feature(_ icon: String, _ text: String) -> some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 18))
                .foregroundStyle(Night.lavender)
                .frame(width: 30)
            Text(text)
                .font(.system(size: 16))
                .foregroundStyle(.white.opacity(0.85))
        }
    }
}
