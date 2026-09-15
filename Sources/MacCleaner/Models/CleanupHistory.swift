import Foundation

/// 一次清理的记录。
struct CleanupRecord: Codable, Identifiable {
    var id: UUID = UUID()
    let date: Date
    /// 成功删除的项目数
    let itemCount: Int
    /// 实际释放的字节数
    let freed: Int64
    /// 各类别的释放量明细
    let byCategory: [String: Int64]
    /// 失败项数量（权限等原因）
    let failureCount: Int
}

/// 清理历史，持久化在 `~/Library/Application Support/MacCleaner/history.json`。
///
/// 设计取舍：只记录**释放量**这类聚合数据，不记录具体文件路径。
/// 路径信息对趋势展示没有价值，却会让一个本地历史文件变成隐私存档。
@MainActor
final class CleanupHistory: ObservableObject {

    @Published private(set) var records: [CleanupRecord] = []

    /// 历史文件位置。
    ///
    /// 可注入：测试必须能指向临时文件，否则 `clear()` 会删掉用户真实的历史。
    /// 早期测试直接操作真实路径，跑一次测试就清空了使用者的清理记录。
    let fileURL: URL

    /// 默认位置
    nonisolated static var defaultFileURL: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory() + "/Library/Application Support")
        return base.appendingPathComponent("MacCleaner/history.json")
    }

    init(fileURL: URL = CleanupHistory.defaultFileURL) {
        self.fileURL = fileURL
        load()
    }

    // MARK: - 读写

    private func load() {
        let url = fileURL
        guard let data = try? Data(contentsOf: url) else { return }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        // 历史文件损坏时静默从空历史开始 —— 这只是统计信息，
        // 不应因为文件损坏而阻断应用启动。
        records = (try? decoder.decode([CleanupRecord].self, from: data)) ?? []
    }

    private func save() {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted]
        guard let data = try? encoder.encode(records) else { return }

        let url = fileURL
        do {
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try data.write(to: url, options: .atomic)
        } catch {
            // 写不进去不影响清理功能本身，静默降级
        }
    }

    // MARK: - 记录

    /// 记录一次清理。释放量为 0 的操作不记录，避免历史被无效条目淹没。
    func record(items: [CleanupItem], freed: Int64, failureCount: Int) {
        guard freed > 0, !items.isEmpty else { return }

        var byCategory: [String: Int64] = [:]
        for item in items {
            byCategory[item.category.rawValue, default: 0] += item.size
        }

        records.append(CleanupRecord(
            date: Date(),
            itemCount: items.count,
            freed: freed,
            byCategory: byCategory,
            failureCount: failureCount
        ))

        // 只保留最近 500 条，防止文件无限增长
        if records.count > 500 {
            records = Array(records.suffix(500))
        }
        save()
    }

    func clear() {
        records = []
        try? FileManager.default.removeItem(at: fileURL)
    }

    // MARK: - 统计

    var totalFreed: Int64 { records.reduce(0) { $0 + $1.freed } }
    var totalItems: Int { records.reduce(0) { $0 + $1.itemCount } }

    /// 最近 N 天的记录
    func records(inLastDays days: Int) -> [CleanupRecord] {
        let cutoff = Calendar.current.date(byAdding: .day, value: -days, to: Date()) ?? .distantPast
        return records.filter { $0.date >= cutoff }
    }

    /// 最近 N 天每天的释放量，用于柱状图。返回按日期升序、且补齐空白天。
    func dailyFreed(days: Int) -> [(date: Date, freed: Int64)] {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())

        var buckets: [Date: Int64] = [:]
        for r in records {
            let day = cal.startOfDay(for: r.date)
            buckets[day, default: 0] += r.freed
        }

        return (0..<days).reversed().compactMap { offset in
            guard let day = cal.date(byAdding: .day, value: -offset, to: today) else { return nil }
            return (day, buckets[day] ?? 0)
        }
    }

    /// 按类别汇总的累计释放量，降序
    func freedByCategory() -> [(category: CleanupCategory, freed: Int64)] {
        var totals: [String: Int64] = [:]
        for r in records {
            for (k, v) in r.byCategory { totals[k, default: 0] += v }
        }
        return totals
            .compactMap { key, value -> (CleanupCategory, Int64)? in
                guard let c = CleanupCategory(rawValue: key) else { return nil }
                return (c, value)
            }
            .sorted { $0.1 > $1.1 }
    }
}
