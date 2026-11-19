import SwiftUI

enum Theme {
    static let topBlue = Color(red: 0.20, green: 0.36, blue: 0.56)
    static let midBlue = Color(red: 0.07, green: 0.13, blue: 0.22)
    static let bottom = Color(red: 0.05, green: 0.06, blue: 0.09)
    static let accent = Color(red: 0.70, green: 0.82, blue: 0.95)
    static let cardFill = Color(red: 0.13, green: 0.15, blue: 0.19)
    static let secondaryText = Color.white.opacity(0.62)
    static let tertiaryText = Color.white.opacity(0.4)
    static let cornerRadius: CGFloat = 30
}

/// 蓝黑渐变 + 细网格背景
struct GridBackground: View {
    var body: some View {
        ZStack {
            LinearGradient(colors: [Theme.topBlue, Theme.midBlue, Theme.bottom, Theme.bottom],
                           startPoint: .top, endPoint: .bottom)
            Canvas { ctx, size in
                let step: CGFloat = 22
                var path = Path()
                var x: CGFloat = 0
                while x <= size.width { path.move(to: CGPoint(x: x, y: 0)); path.addLine(to: CGPoint(x: x, y: size.height)); x += step }
                var y: CGFloat = 0
                while y <= size.height { path.move(to: CGPoint(x: 0, y: y)); path.addLine(to: CGPoint(x: size.width, y: y)); y += step }
                ctx.stroke(path, with: .color(.white.opacity(0.045)), lineWidth: 0.5)
            }
        }
        .ignoresSafeArea()
    }
}

/// 卡片容器
struct Card<Content: View>: View {
    var padding: CGFloat = 20
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous)
                    .fill(LinearGradient(colors: [Theme.cardFill.opacity(0.95), Theme.cardFill.opacity(0.8)],
                                         startPoint: .top, endPoint: .bottom))
            )
            .overlay(
                RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.07), lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.35), radius: 12, y: 6)
    }
}

/// 卡片标题：圆角方块图标 + 文字
struct CardHeader: View {
    var icon: String
    var title: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 17, weight: .medium))
                .foregroundStyle(.white.opacity(0.85))
                .frame(width: 36, height: 36)
                .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(.white.opacity(0.09)))
            Text(title)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(.white.opacity(0.92))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
    }
}

/// 大号 “13h52min” 样式
struct DurationText: View {
    var seconds: TimeInterval
    var size: CGFloat = 44
    var color: Color = .white

    var body: some View {
        let v = Fmt.hm(seconds)
        HStack(alignment: .firstTextBaseline, spacing: 1) {
            if v.hours > 0 {
                Text("\(v.hours)").font(.system(size: size, weight: .heavy, design: .rounded))
                Text("h").font(.system(size: size * 0.42, weight: .semibold, design: .rounded))
                    .padding(.trailing, 2)
            }
            Text("\(v.minutes)").font(.system(size: size, weight: .heavy, design: .rounded))
            Text("min").font(.system(size: size * 0.42, weight: .semibold, design: .rounded))
        }
        .foregroundStyle(color)
        .lineLimit(1)
        .minimumScaleFactor(0.5)
        .contentTransition(.numericText())
    }
}

/// 大号数字 + 单位，例如 “68 天”
struct NumberUnitText: View {
    var value: String
    var unit: String
    var size: CGFloat = 44
    var color: Color = .white

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text(value).font(.system(size: size, weight: .heavy, design: .rounded))
            if !unit.isEmpty {
                Text(unit).font(.system(size: size * 0.8, weight: .heavy))
            }
        }
        .foregroundStyle(color)
        .lineLimit(1)
        .minimumScaleFactor(0.5)
    }
}

struct SectionTitle: View {
    var title: String
    var trailing: String? = nil

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title).font(.system(size: 26, weight: .bold)).foregroundStyle(.white)
            Spacer()
            if let trailing {
                Text(trailing).font(.subheadline).foregroundStyle(Theme.secondaryText)
            }
        }
        .padding(.horizontal, 4)
    }
}

struct LargeTitle: View {
    var title: String
    var subtitle: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.system(size: 44, weight: .heavy)).foregroundStyle(.white.opacity(0.9))
            if let subtitle {
                Text(subtitle).font(.subheadline).foregroundStyle(Theme.secondaryText)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// 自定义分段控件（周 / 月 / 年 / 总共）
struct SegmentedPicker<T: Hashable & Identifiable>: View {
    var items: [T]
    @Binding var selection: T
    var title: (T) -> String
    @Namespace private var ns

    var body: some View {
        HStack(spacing: 0) {
            ForEach(items) { item in
                Button {
                    withAnimation(.snappy) { selection = item }
                } label: {
                    Text(title(item))
                        .font(.system(size: 17, weight: selection == item ? .semibold : .regular))
                        .foregroundStyle(.white.opacity(selection == item ? 1 : 0.75))
                        .frame(maxWidth: .infinity, minHeight: 42)
                        .background {
                            if selection == item {
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .fill(.white.opacity(0.18))
                                    .matchedGeometryEffect(id: "seg", in: ns)
                            }
                        }
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(4)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Theme.cardFill.opacity(0.9)))
    }
}

struct EmptyHint: View {
    var text: String
    var body: some View {
        Text(text)
            .font(.subheadline)
            .foregroundStyle(Theme.tertiaryText)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

extension View {
    func screenPadding() -> some View { padding(.horizontal, 20) }
}
