import SwiftUI

/// “累计佩戴时长” 卡片：总时长 + 环比徽章 + 柱形图
struct PeriodTotalCard: View {
    var summary: PeriodSummary
    @Binding var selectedBar: String?

    private var selected: PeriodBar? {
        guard let selectedBar else { return nil }
        return summary.bars.first { $0.key == selectedBar }
    }

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: 14) {
                CardHeader(icon: "clock", title: "累计佩戴时长")

                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 6) {
                        DurationText(seconds: selected?.duration ?? summary.total, size: 56)
                        Text(selected.map { "\($0.detailLabel) · 有记录 \($0.recordedDays) 天" } ?? "本周期佩戴时长")
                            .font(.system(size: 15, weight: .medium))
                            .foregroundStyle(Theme.secondaryText)
                    }
                    Spacer(minLength: 8)
                    if let title = summary.kind.comparisonTitle, let delta = summary.delta, selected == nil {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(title)
                            Text(Fmt.signedDuration(delta))
                        }
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(.white.opacity(0.85))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(.white.opacity(0.1)))
                    }
                }

                ChartPanel {
                    DurationBarChart(
                        bars: summary.bars.map { ChartBar(key: $0.key, label: $0.label, detail: $0.detailLabel, seconds: $0.duration) },
                        height: 260,
                        maxXLabels: summary.kind == .month ? 7 : 12,
                        selectedKey: $selectedBar
                    )
                }

                Text("轻点柱形查看明细 · 无记录不等于未佩戴")
                    .font(.system(size: 14))
                    .foregroundStyle(Theme.secondaryText)
            }
        }
    }
}

/// “周期概览” 网格
struct PeriodOverview: View {
    var summary: PeriodSummary

    var body: some View {
        let columns = [GridItem(.flexible(), spacing: 14), GridItem(.flexible(), spacing: 14)]
        VStack(alignment: .leading, spacing: 14) {
            SectionTitle(title: "周期概览").padding(.top, 8)
            LazyVGrid(columns: columns, spacing: 14) {
                Card(padding: 18) {
                    VStack(alignment: .leading, spacing: 14) {
                        CardHeader(icon: "chart.bar", title: "有记录日平均")
                        DurationText(seconds: summary.averagePerRecordedDay, size: 40)
                        Text("基于 \(summary.recordedDays) 个有记录日")
                            .font(.system(size: 14, weight: .medium)).foregroundStyle(Theme.secondaryText)
                        MiniBars(values: summary.bars.map(\.duration))
                    }
                }
                Card(padding: 18) {
                    VStack(alignment: .leading, spacing: 14) {
                        CardHeader(icon: "calendar", title: "有记录天数")
                        NumberUnitText(value: "\(summary.recordedDays)", unit: "", size: 40, color: .white.opacity(0.85))
                        Text("周期共 \(summary.totalDays) 天")
                            .font(.system(size: 14, weight: .medium)).foregroundStyle(Theme.secondaryText)
                        DotRow(filled: summary.bars.map { $0.recordedDays > 0 })
                    }
                }
                Card(padding: 18) {
                    VStack(alignment: .leading, spacing: 14) {
                        CardHeader(icon: "trophy", title: "周期最长单日")
                        DurationText(seconds: summary.bestDay?.duration ?? 0, size: 40)
                        Text(summary.bestDay.map { Fmt.day($0.day) } ?? "暂无记录")
                            .font(.system(size: 14, weight: .medium)).foregroundStyle(Theme.secondaryText)
                    }
                }
                Card(padding: 18) {
                    VStack(alignment: .leading, spacing: 14) {
                        CardHeader(icon: "repeat", title: "佩戴次数")
                        NumberUnitText(value: "\(summary.sessionCount)", unit: "次", size: 40, color: .white.opacity(0.85))
                        Text(summary.sessionCount > 0
                             ? "平均每次 \(Fmt.shortDuration(summary.total / Double(summary.sessionCount)))"
                             : "暂无记录")
                            .font(.system(size: 14, weight: .medium)).foregroundStyle(Theme.secondaryText)
                    }
                }
            }
        }
    }
}

/// 小型柱状缩略图，最高的一根高亮
struct MiniBars: View {
    var values: [TimeInterval]

    var body: some View {
        let sampled = Self.resample(values, to: 12)
        let maxV = sampled.max() ?? 0
        let maxIndex = sampled.firstIndex(of: maxV)
        HStack(alignment: .bottom, spacing: 5) {
            ForEach(Array(sampled.enumerated()), id: \.offset) { i, v in
                Capsule()
                    .fill(.white.opacity(i == maxIndex && maxV > 0 ? 0.95 : 0.45))
                    .frame(height: maxV > 0 ? max(6, 44 * v / maxV) : 6)
            }
        }
        .frame(height: 44, alignment: .bottom)
    }

    static func resample(_ values: [TimeInterval], to n: Int) -> [TimeInterval] {
        guard values.count > n else { return values }
        let size = Double(values.count) / Double(n)
        return (0..<n).map { i in
            let a = Int(Double(i) * size), b = min(values.count, Int(Double(i + 1) * size))
            return values[a..<max(a + 1, b)].reduce(0, +)
        }
    }
}

/// 一排小圆点：有记录为亮色
struct DotRow: View {
    var filled: [Bool]

    var body: some View {
        let dots = filled.count > 12 ? Self.resample(filled, to: 12) : filled
        HStack(spacing: 6) {
            ForEach(Array(dots.enumerated()), id: \.offset) { _, on in
                Capsule()
                    .fill(.white.opacity(on ? 0.85 : 0.18))
                    .frame(height: 10)
            }
        }
        .frame(height: 44, alignment: .bottom)
    }

    static func resample(_ values: [Bool], to n: Int) -> [Bool] {
        let size = Double(values.count) / Double(n)
        return (0..<n).map { i in
            let a = Int(Double(i) * size), b = min(values.count, Int(Double(i + 1) * size))
            return values[a..<max(a + 1, b)].contains(true)
        }
    }
}
