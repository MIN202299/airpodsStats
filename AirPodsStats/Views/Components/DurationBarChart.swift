import SwiftUI
import Charts

struct ChartBar: Identifiable, Hashable {
    var key: String          // 唯一键（作为类别轴的值）
    var label: String        // 坐标轴显示文字
    var detail: String       // 选中时显示的明细标题
    var seconds: TimeInterval
    var id: String { key }
}

/// 白色渐变圆角柱形图，Y 轴在右侧以 “h min” 显示，可点选查看明细。
struct DurationBarChart: View {
    var bars: [ChartBar]
    var height: CGFloat = 260
    /// 最多显示多少个 X 轴标签，超过后隔几个显示一个
    var maxXLabels: Int = 12
    @Binding var selectedKey: String?

    private var maxValue: Double { bars.map(\.seconds).max() ?? 0 }
    private var top: Double {
        let m = maxValue
        return m > 0 ? m * 1.18 : 3600
    }
    private var ticks: [Double] { [0, top / 3, top * 2 / 3, top] }
    private var labelStride: Int { max(1, Int(ceil(Double(bars.count) / Double(maxXLabels)))) }

    var body: some View {
        Chart(bars) { bar in
            BarMark(
                x: .value("周期", bar.key),
                y: .value("时长", bar.seconds),
                width: .ratio(0.55)
            )
            .cornerRadius(10)
            .foregroundStyle(
                LinearGradient(colors: [.white.opacity(isDimmed(bar) ? 0.35 : 0.95),
                                        .white.opacity(isDimmed(bar) ? 0.05 : 0.15)],
                               startPoint: .top, endPoint: .bottom)
            )
        }
        .chartYScale(domain: 0...top)
        .chartYAxis {
            AxisMarks(position: .trailing, values: ticks) { value in
                AxisGridLine(stroke: StrokeStyle(lineWidth: 0.6))
                    .foregroundStyle(.white.opacity(0.12))
                AxisValueLabel {
                    if let v = value.as(Double.self) {
                        Text(Fmt.duration(v))
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(.white.opacity(0.7))
                    }
                }
            }
        }
        .chartXAxis {
            AxisMarks { value in
                AxisValueLabel(centered: true) {
                    if let key = value.as(String.self), let i = bars.firstIndex(where: { $0.key == key }),
                       i % labelStride == 0 {
                        Text(bars[i].label)
                            .font(.system(size: 13))
                            .foregroundStyle(.white.opacity(0.75))
                            .fixedSize()
                    }
                }
            }
        }
        .chartOverlay { proxy in
            GeometryReader { geo in
                Rectangle().fill(.clear).contentShape(Rectangle())
                    .onTapGesture { location in
                        guard let plot = proxy.plotFrame else { return }
                        let x = location.x - geo[plot].origin.x
                        guard let key: String = proxy.value(atX: x) else { return }
                        withAnimation(.snappy) { selectedKey = (selectedKey == key) ? nil : key }
                    }
            }
        }
        .frame(height: height)
        .animation(.snappy, value: bars)
    }

    private func isDimmed(_ bar: ChartBar) -> Bool {
        guard let selectedKey else { return false }
        return selectedKey != bar.key
    }
}

/// 深色内嵌面板
struct ChartPanel<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View {
        content
            .padding(.horizontal, 14)
            .padding(.vertical, 18)
            .background(RoundedRectangle(cornerRadius: 22, style: .continuous).fill(.black.opacity(0.28)))
    }
}
