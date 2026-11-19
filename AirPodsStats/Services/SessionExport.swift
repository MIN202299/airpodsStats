import CoreTransferable
import Foundation
import UniformTypeIdentifiers

/// 把佩戴记录导出为 CSV（通过系统分享面板）
struct SessionExport: Transferable, Sendable {
    var sessions: [WearSession]
    var names: [String: String]

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(exportedContentType: .commaSeparatedText) { export in
            let url = FileManager.default.temporaryDirectory.appendingPathComponent("耳机佩戴记录.csv")
            try export.csv().write(to: url, atomically: true, encoding: .utf8)
            return SentTransferredFile(url)
        }
    }

    func csv() -> String {
        let iso = ISO8601DateFormatter()
        iso.timeZone = .current
        iso.formatOptions = [.withInternetDateTime]
        var lines = ["\u{FEFF}设备,开始时间,结束时间,时长（分钟）,平均音量 dB(A)"]   // BOM：Excel 正确识别中文
        lines.reserveCapacity(sessions.count + 1)
        for s in sessions {
            let name = (names[s.deviceID] ?? s.deviceID).replacingOccurrences(of: "\"", with: "\"\"")
            let level = s.averageLevel.map { String(format: "%.1f", $0) } ?? ""
            lines.append("\"\(name)\",\(iso.string(from: s.start)),\(iso.string(from: s.end)),\(String(format: "%.1f", s.duration / 60)),\(level)")
        }
        return lines.joined(separator: "\n")
    }
}

extension UsageStore {
    var export: SessionExport {
        var names: [String: String] = [:]
        for id in Set(allSessions.map(\.deviceID)) { names[id] = displayName(for: id) }
        return SessionExport(sessions: allSessions, names: names)
    }
}
