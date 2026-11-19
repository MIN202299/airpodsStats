import Foundation

/// 把零散的耳机音频样本合并成“佩戴会话”。
///
/// 健康 App 会在耳机播放音频时持续写入“耳机音频级别”样本，
/// 同一副耳机相邻样本之间的间隔不超过 `mergeGap` 时视为同一次佩戴。
enum SessionBuilder {
    static func build(from samples: [RawSample], mergeGap: TimeInterval) -> [WearSession] {
        let grouped = Dictionary(grouping: samples, by: \.deviceID)
        var sessions: [WearSession] = []

        for (deviceID, deviceSamples) in grouped {
            let sorted = deviceSamples
                .filter { $0.end > $0.start }
                .sorted { $0.start < $1.start }
            guard let first = sorted.first else { continue }

            var current = WearSession(deviceID: deviceID, start: first.start, end: first.end)
            var levelSum = 0.0, levelWeight = 0.0

            func accumulate(_ s: RawSample) {
                guard let level = s.level else { return }
                let w = s.end.timeIntervalSince(s.start)
                levelSum += level * w
                levelWeight += w
            }
            func finish() {
                current.averageLevel = levelWeight > 0 ? levelSum / levelWeight : nil
                sessions.append(current)
            }

            accumulate(first)
            for sample in sorted.dropFirst() {
                if sample.start.timeIntervalSince(current.end) <= mergeGap {
                    current.end = max(current.end, sample.end)
                } else {
                    finish()
                    current = WearSession(deviceID: deviceID, start: sample.start, end: sample.end)
                    levelSum = 0; levelWeight = 0
                }
                accumulate(sample)
            }
            finish()
        }

        return sessions.sorted { $0.start < $1.start }
    }

    /// 把已经合并好的会话再按设备合并一次（用于“合并设备”后两副耳机的会话首尾相接或重叠的情况）
    static func coalesce(_ input: [WearSession], mergeGap: TimeInterval) -> [WearSession] {
        var result: [WearSession] = []
        for (_, group) in Dictionary(grouping: input, by: \.deviceID) {
            let sorted = group.sorted { $0.start < $1.start }
            guard var current = sorted.first else { continue }
            var levelSum = (current.averageLevel ?? 0) * current.duration
            var levelWeight = current.averageLevel == nil ? 0 : current.duration

            for s in sorted.dropFirst() {
                if s.start.timeIntervalSince(current.end) <= mergeGap {
                    current.end = max(current.end, s.end)
                } else {
                    current.averageLevel = levelWeight > 0 ? levelSum / levelWeight : nil
                    result.append(current)
                    current = s
                    levelSum = 0; levelWeight = 0
                    // 新会话自己的音量在下面统一累加
                    if let l = s.averageLevel { levelSum = l * s.duration; levelWeight = s.duration }
                    continue
                }
                if let l = s.averageLevel { levelSum += l * s.duration; levelWeight += s.duration }
            }
            current.averageLevel = levelWeight > 0 ? levelSum / levelWeight : nil
            result.append(current)
        }
        return result.sorted { $0.start < $1.start }
    }

    static func devices(from samples: [RawSample]) -> [String: HeadphoneDevice] {
        var result: [String: HeadphoneDevice] = [:]
        for s in samples where result[s.deviceID] == nil {
            result[s.deviceID] = HeadphoneDevice(id: s.deviceID, rawName: s.deviceName, model: s.deviceModel, manufacturer: s.manufacturer)
        }
        return result
    }
}
