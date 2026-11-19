import SwiftUI

enum Night {
    static let top = Color(red: 0.03, green: 0.03, blue: 0.10)
    static let mid = Color(red: 0.07, green: 0.07, blue: 0.18)
    static let planetTop = Color(red: 0.33, green: 0.32, blue: 0.58)
    static let planetBottom = Color(red: 0.10, green: 0.10, blue: 0.22)
    static let lavender = Color(red: 0.78, green: 0.76, blue: 0.95)
    static let secondary = Color.white.opacity(0.6)
    static let cardFill = Color(red: 0.16, green: 0.16, blue: 0.27)
}

/// 深紫夜空 + 星点 + 一道发光的“行星弧线”
struct NightBackground: View {
    /// 弧线顶部所在高度（占屏幕高度的比例）
    var horizon: CGFloat = 0.45

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width, h = geo.size.height
            ZStack {
                LinearGradient(colors: [Night.top, Night.mid, Night.top], startPoint: .top, endPoint: .bottom)

                // 行星表面：一个倾斜的大椭圆，顶部边缘带柔光
                Ellipse()
                    .fill(LinearGradient(colors: [Night.planetTop, Night.planetBottom, Night.top],
                                         startPoint: .top, endPoint: .bottom))
                    .frame(width: w * 3.2, height: h * 1.3)
                    .rotationEffect(.degrees(-9))
                    .position(x: w * 0.85, y: h * horizon + h * 0.65)
                    .blur(radius: 18)
                    .opacity(0.9)
                Ellipse()
                    .stroke(Night.lavender.opacity(0.35), lineWidth: 2)
                    .frame(width: w * 3.2, height: h * 1.3)
                    .rotationEffect(.degrees(-9))
                    .position(x: w * 0.85, y: h * horizon + h * 0.65)
                    .blur(radius: 6)

                StarField()
            }
        }
        .ignoresSafeArea()
    }
}

/// 静态星点（固定随机种子，每次渲染位置一致）
struct StarField: View {
    var count = 90

    var body: some View {
        Canvas { ctx, size in
            var rng = DemoDataGenerator.SeededRNG(seed: 7)
            for _ in 0..<count {
                let x = Double.random(in: 0...1, using: &rng) * size.width
                let y = Double.random(in: 0...1, using: &rng) * size.height
                let r = Double.random(in: 0.4...1.3, using: &rng)
                let a = Double.random(in: 0.15...0.6, using: &rng)
                ctx.fill(Path(ellipseIn: CGRect(x: x, y: y, width: r, height: r)), with: .color(.white.opacity(a)))
            }
        }
        .allowsHitTesting(false)
    }
}

/// 缓慢旋转、闪烁的粒子球
struct ParticleSphere: View {
    struct Particle {
        var x: Double, y: Double, z: Double
        var size: Double
        var phase: Double
        var speed: Double
    }

    private let particles: [Particle]
    /// 页面不可见时暂停动画，节省电量
    var paused: Bool = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(count: Int = 520, seed: UInt64 = 11, paused: Bool = false) {
        self.paused = paused
        var rng = DemoDataGenerator.SeededRNG(seed: seed)
        let golden = Double.pi * (3 - 5.0.squareRoot())
        particles = (0..<count).map { i in
            // 斐波那契球面均匀分布 + 半径抖动，形成有厚度的球壳
            let y = 1 - (Double(i) + 0.5) / Double(count) * 2
            let radius = (1 - y * y).squareRoot()
            let theta = golden * Double(i)
            let shell = Double.random(in: 0.82...1.0, using: &rng)
            return Particle(
                x: cos(theta) * radius * shell,
                y: y * shell,
                z: sin(theta) * radius * shell,
                size: Double.random(in: 1.4...3.4, using: &rng),
                phase: Double.random(in: 0...(2 * .pi), using: &rng),
                speed: Double.random(in: 0.6...2.2, using: &rng)
            )
        }
    }

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 30, paused: reduceMotion || paused)) { timeline in
            let t = timeline.date.timeIntervalSinceReferenceDate
            Canvas { ctx, size in
                let r = min(size.width, size.height) / 2
                let cx = size.width / 2, cy = size.height / 2
                let a = t.truncatingRemainder(dividingBy: 3600) * 0.12
                let tilt = 0.38
                let (sa, ca, st, ct) = (sin(a), cos(a), sin(tilt), cos(tilt))

                for p in particles {
                    // 绕 Y 轴旋转，再绕 X 轴倾斜
                    let x1 = p.x * ca + p.z * sa
                    let z1 = -p.x * sa + p.z * ca
                    let y2 = p.y * ct - z1 * st
                    let z2 = p.y * st + z1 * ct
                    let depth = (z2 + 1) / 2                          // 0 = 背面, 1 = 正面
                    let twinkle = 0.65 + 0.35 * sin(t * p.speed + p.phase)
                    let alpha = (0.18 + 0.82 * depth) * twinkle
                    let s = p.size * (0.55 + 0.6 * depth)
                    let px = cx + x1 * r, py = cy + y2 * r

                    if depth > 0.75 {
                        // 正面较亮的粒子加一圈柔光
                        let g = s * 3
                        ctx.fill(Path(ellipseIn: CGRect(x: px - g / 2, y: py - g / 2, width: g, height: g)),
                                 with: .color(.white.opacity(alpha * 0.12)))
                    }
                    ctx.fill(Path(ellipseIn: CGRect(x: px - s / 2, y: py - s / 2, width: s, height: s)),
                             with: .color(.white.opacity(alpha)))
                }
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// 半透明“玻璃”圆角卡片
struct GlassCard<Content: View>: View {
    var cornerRadius: CGFloat = 34
    var padding: CGFloat = 22
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                ZStack {
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .fill(.ultraThinMaterial)
                        .environment(\.colorScheme, .dark)
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .fill(LinearGradient(colors: [Night.lavender.opacity(0.28), Night.lavender.opacity(0.10), Night.lavender.opacity(0.22)],
                                             startPoint: .topLeading, endPoint: .bottomTrailing))
                    // 底部的一抹反光
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .fill(RadialGradient(colors: [.white.opacity(0.18), .clear],
                                             center: .init(x: 0.6, y: 1.0), startRadius: 0, endRadius: 220))
                }
            }
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(LinearGradient(colors: [.white.opacity(0.35), .white.opacity(0.08), .white.opacity(0.2)],
                                                 startPoint: .top, endPoint: .bottom), lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.35), radius: 20, y: 10)
    }
}

/// 深色半透明的普通信息卡片
struct NightTile<Content: View>: View {
    var padding: CGFloat = 20
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 28, style: .continuous).fill(Night.cardFill.opacity(0.55)))
            .overlay(RoundedRectangle(cornerRadius: 28, style: .continuous).strokeBorder(.white.opacity(0.06), lineWidth: 1))
    }
}

/// 耳机“产品图”：用 SF Symbols 叠出淡紫色质感
struct DeviceArtwork: View {
    var kind: DeviceKind
    var height: CGFloat

    var body: some View {
        Image(systemName: kind.symbol)
            .resizable()
            .scaledToFit()
            .symbolRenderingMode(.hierarchical)
            .foregroundStyle(
                LinearGradient(colors: [.white, Night.lavender, Color(red: 0.62, green: 0.58, blue: 0.85)],
                               startPoint: .top, endPoint: .bottom)
            )
            .shadow(color: .black.opacity(0.35), radius: 10, y: 8)
            .frame(height: height)
            .frame(maxWidth: .infinity)
    }
}

/// 设备卡片内容：名称 / 产品图 / 时长 / 占比
struct DeviceGlassCard: View {
    var name: String
    var kind: DeviceKind
    var duration: TimeInterval
    var share: Double
    var artworkHeight: CGFloat = 130

    var body: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 10) {
                Text(name)
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                DeviceArtwork(kind: kind, height: artworkHeight)
                    .padding(.vertical, 8)
                DurationText(seconds: duration, size: 46)
                Text("\(Int((share * 100).rounded()))% 的佩戴时长")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(.white.opacity(0.7))
            }
        }
    }
}
