import Foundation

/// 生成可复现的示例数据，方便在模拟器或没有健康数据时预览界面。
enum DemoDataGenerator {
    struct SeededRNG: RandomNumberGenerator {
        var state: UInt64
        init(seed: UInt64) { state = seed &+ 0x9E37_79B9_7F4A_7C15 }
        mutating func next() -> UInt64 {
            state &+= 0x9E37_79B9_7F4A_7C15
            var z = state
            z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
            z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
            return z ^ (z >> 31)
        }
    }

    static func samples(now: Date = .now, days: Int = 760, calendar: Calendar = .stats) -> [RawSample] {
        var rng = SeededRNG(seed: 2025)
        let pro2 = (id: "demo-pro2", name: "AirPods Pro 2（配 MagSafe 充电盒）", model: "AirPods Pro 2")
        let pro1 = (id: "demo-pro1", name: "AirPods Pro", model: "AirPods Pro")
        let max = (id: "demo-max", name: "AirPods Max", model: "0x200a")

        let today = calendar.startOfDay(for: now)
        var result: [RawSample] = []

        for offset in stride(from: days, through: 0, by: -1) {
            guard let day = calendar.date(byAdding: .day, value: -offset, to: today) else { continue }
            // 约 5% 的日子没有记录
            if Double.random(in: 0..<1, using: &rng) < 0.05 { continue }

            let weekday = calendar.component(.weekday, from: day)
            let isWeekend = weekday == 1 || weekday == 7
            // 早期使用旧耳机，之后换成 Pro 2；偶尔用 Max
            let primary = offset > 420 ? pro1 : pro2
            let sessionsToday = Int.random(in: (isWeekend ? 1 : 2)...(isWeekend ? 4 : 6), using: &rng)
            var cursor = calendar.date(bySettingHour: Int.random(in: 7...9, using: &rng),
                                       minute: Int.random(in: 0...59, using: &rng), second: 0, of: day) ?? day

            for _ in 0..<sessionsToday {
                let device = Double.random(in: 0..<1, using: &rng) < 0.08 ? max : primary
                let length = TimeInterval(Int.random(in: 10...(isWeekend ? 200 : 150), using: &rng) * 60)
                var sessionEnd = cursor.addingTimeInterval(length)
                if offset == 0 { sessionEnd = Swift.min(sessionEnd, now) }
                guard sessionEnd > cursor else { break }

                // 把一次佩戴切成若干条短样本，模拟健康 App 的写入方式
                var s = cursor
                while s < sessionEnd {
                    let e = Swift.min(sessionEnd, s.addingTimeInterval(TimeInterval(Int.random(in: 3...20, using: &rng) * 60)))
                    result.append(RawSample(deviceID: device.id, deviceName: device.name, deviceModel: device.model,
                                            manufacturer: "Apple Inc.", start: s, end: e,
                                            level: Double.random(in: 48...72, using: &rng)))
                    s = e.addingTimeInterval(TimeInterval(Int.random(in: 0...90, using: &rng)))
                }
                cursor = sessionEnd.addingTimeInterval(TimeInterval(Int.random(in: 20...180, using: &rng) * 60))
                if offset == 0 && cursor > now { break }
            }
        }
        return result
    }
}
