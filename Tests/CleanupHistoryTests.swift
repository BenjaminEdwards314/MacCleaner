enum CleanupCategory: String { case duplicates, appResidue, appBundle }
enum RiskLevel: String { case caution, dangerous }
struct CleanupItem: Identifiable {
    let id = UUID(); let url: URL; let size: Int64; let category: CleanupCategory
    let risk: RiskLevel; let explanation: String; let defaultSelected: Bool
    var isSelected: Bool = false; var modified: Date?
}
enum Fmt { static func size(_ b: Int64) -> String { ByteCountFormatter.string(fromByteCount: b, countStyle: .file) } }
import Foundation

@MainActor func run() async {
    var fail = 0
    func expect(_ c: Bool, _ m: String) { print("\(c ? "✅" : "❌") \(m)"); if !c { fail += 1 } }

    // 使用隔离的临时文件。
    // 绝不能用默认路径：clear() 会删掉用户真实的清理历史。
    let store = URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent("mc_history_test_\(UUID().uuidString).json")
    defer { try? FileManager.default.removeItem(at: store) }

    print("=== CleanupHistory 持久化测试 ===")
    print("临时存储: \(store.lastPathComponent)")
    let realFile = CleanupHistory.defaultFileURL
    let realExistsBefore = FileManager.default.fileExists(atPath: realFile.path)

    let h = CleanupHistory(fileURL: store)
    expect(h.records.isEmpty, "初始为空")
    expect(h.totalFreed == 0, "初始累计为 0")

    // 造两条记录
    let items1 = [
        CleanupItem(url: URL(fileURLWithPath: "/tmp/x/1"), size: 1000, category: .duplicates,
                    risk: .caution, explanation: "", defaultSelected: false),
        CleanupItem(url: URL(fileURLWithPath: "/tmp/x/2"), size: 2000, category: .duplicates,
                    risk: .caution, explanation: "", defaultSelected: false),
    ]
    h.record(items: items1, freed: 3000, failureCount: 0)
    expect(h.records.count == 1, "记录 1 条")
    expect(h.totalFreed == 3000, "累计 3000（实际 \(h.totalFreed)）")
    expect(h.totalItems == 2, "项目数 2（实际 \(h.totalItems)）")

    // 释放量为 0 不应记录
    h.record(items: items1, freed: 0, failureCount: 0)
    expect(h.records.count == 1, "释放量 0 不记录")

    // 空 items 不应记录
    h.record(items: [], freed: 500, failureCount: 0)
    expect(h.records.count == 1, "空条目不记录")

    // 持久化：新实例应能读回
    let h2 = CleanupHistory(fileURL: store)
    expect(h2.records.count == 1, "重新加载后有 1 条（实际 \(h2.records.count)）")
    expect(h2.totalFreed == 3000, "重新加载后累计 3000（实际 \(h2.totalFreed)）")

    // 按类别汇总
    let cats = h2.freedByCategory()
    expect(cats.count == 1, "类别数 1")
    expect(cats.first?.category == .duplicates, "类别为 duplicates")
    expect(cats.first?.freed == 3000, "该类别累计 3000")

    // 每日柱状
    let daily = h2.dailyFreed(days: 30)
    expect(daily.count == 30, "补齐 30 天（实际 \(daily.count)）")
    expect(daily.last?.freed == 3000, "今天为 3000")
    expect(daily.dropLast().allSatisfy { $0.freed == 0 }, "其余天为 0")

    // 天数范围
    expect(h2.records(inLastDays: 7).count == 1, "近 7 天有 1 条")
    expect(h2.records(inLastDays: 0).count == 0, "近 0 天为 0 条")

    // 上限：超过 500 条应截断
    for i in 0..<510 {
        h2.record(items: [CleanupItem(url: URL(fileURLWithPath: "/tmp/y/\(i)"), size: 10,
                    category: .duplicates, risk: .caution, explanation: "", defaultSelected: false)],
                  freed: 10, failureCount: 0)
    }
    expect(h2.records.count == 500, "上限截断为 500（实际 \(h2.records.count)）")

    // clear
    h2.clear()
    expect(h2.records.isEmpty, "清空后为空")
    let h3 = CleanupHistory(fileURL: store)
    expect(h3.records.isEmpty, "清空后重新加载仍为空")

    // 最关键的一条：测试全程不得触碰用户真实的历史文件
    let realExistsAfter = FileManager.default.fileExists(atPath: realFile.path)
    expect(realExistsBefore == realExistsAfter,
           "★测试不得创建或删除用户真实的历史文件（\(realFile.lastPathComponent)）")

    print("\n测试存储: \(store.path)")
    print(fail == 0 ? "\n✅ 全部通过" : "\n❌ \(fail) 项失败")
    exit(fail == 0 ? 0 : 1)
}
await run()
