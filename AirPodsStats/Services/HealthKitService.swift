import Foundation
import HealthKit

/// 从健康 App 读取“耳机音频级别”(headphoneAudioExposure) 样本。
///
/// iOS 没有公开的“AirPods 佩戴记录”接口；但只要耳机在播放音频，系统就会把
/// 带有设备信息（例如 “AirPods Pro”）的耳机音频级别样本写入健康 App，并保留历史。
/// 本应用把这些样本合并成会话来近似佩戴时长，因此“无记录不等于未佩戴”
/// （例如只开降噪、不播放音频时不会产生样本）。
final class HealthKitService: @unchecked Sendable {
    enum HKError: LocalizedError {
        case unavailable
        var errorDescription: String? { "此设备不支持健康数据" }
    }

    private let store = HKHealthStore()
    private let exposureType = HKQuantityType(.headphoneAudioExposure)

    var isAvailable: Bool { HKHealthStore.isHealthDataAvailable() }

    func requestAuthorization() async throws {
        guard isAvailable else { throw HKError.unavailable }
        try await store.requestAuthorization(toShare: [], read: [exposureType])
    }

    func fetchSamples(since start: Date? = nil) async throws -> [RawSample] {
        guard isAvailable else { throw HKError.unavailable }
        let predicate = start.map { HKQuery.predicateForSamples(withStart: $0, end: nil, options: .strictStartDate) }
        let descriptor = HKSampleQueryDescriptor(
            predicates: [.quantitySample(type: exposureType, predicate: predicate)],
            sortDescriptors: [SortDescriptor(\.startDate, order: .forward)]
        )
        let samples = try await descriptor.result(for: store)
        return samples.map(Self.convert)
    }

    private static func convert(_ sample: HKQuantitySample) -> RawSample {
        let device = sample.device
        let name = device?.name?.trimmingCharacters(in: .whitespacesAndNewlines)
        let model = device?.model
        let displayName: String
        if let name, !name.isEmpty {
            displayName = name
        } else if let model, !model.isEmpty {
            displayName = model
        } else {
            displayName = "未知耳机"
        }
        // 以 名称 + 型号 + 本地标识 作为设备键，同名的两副耳机也能区分
        let id = [name ?? "", model ?? "", device?.localIdentifier ?? ""]
            .joined(separator: "|")
        return RawSample(
            deviceID: id == "||" ? "unknown" : id,
            deviceName: displayName,
            deviceModel: model,
            start: sample.startDate,
            end: sample.endDate
        )
    }
}
