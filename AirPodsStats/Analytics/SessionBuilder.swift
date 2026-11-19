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
            guard var current = sorted.first.map({ WearSession(deviceID: deviceID, start: $0.start, end: $0.end) }) else {
                continue
            }
            for sample in sorted.dropFirst() {
                if sample.start.timeIntervalSince(current.end) <= mergeGap {
                    current.end = max(current.end, sample.end)
                } else {
                    sessions.append(current)
                    current = WearSession(deviceID: deviceID, start: sample.start, end: sample.end)
                }
            }
            sessions.append(current)
        }

        return sessions.sorted { $0.start < $1.start }
    }

    static func devices(from samples: [RawSample]) -> [String: HeadphoneDevice] {
        var result: [String: HeadphoneDevice] = [:]
        for s in samples where result[s.deviceID] == nil {
            result[s.deviceID] = HeadphoneDevice(id: s.deviceID, rawName: s.deviceName, model: s.deviceModel)
        }
        return result
    }
}
