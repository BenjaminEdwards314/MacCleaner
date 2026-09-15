import Foundation

// DuplicateFinder 依赖 CleanupItem；这里构造最小的等价定义，
// 只为驱动真实的三阶段哈希逻辑。
enum CleanupCategory: String { case duplicates }
enum RiskLevel: String { case caution }
struct CleanupItem: Identifiable {
    let id = UUID(); let url: URL; let size: Int64; let category: CleanupCategory
    let risk: RiskLevel; let explanation: String; let defaultSelected: Bool
    var isSelected: Bool = false; var modified: Date?
}
enum Fmt { static func size(_ b: Int64) -> String { ByteCountFormatter.string(fromByteCount: b, countStyle: .file) } }

/// 自建测试夹具。
///
/// 早期版本直接扫描 `/tmp/duprealtest`，依赖手工创建的文件 ——
/// 那样在别的机器上（或临时目录被清理后）必然失败，测试会假报错。
/// 现在自己造、自己清，保证可重复。
func buildFixture() -> URL {
    let root = URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent("mc_dup_test_\(UUID().uuidString)")
    let fm = FileManager.default
    for sub in ["a", "b", "c"] {
        try? fm.createDirectory(at: root.appendingPathComponent(sub),
                                withIntermediateDirectories: true)
    }

    let big = Data(repeating: 0xAB, count: 3_000_000)   // 3 MB
    let diff = Data(repeating: 0xCD, count: 3_000_000)  // 同尺寸、内容不同
    let head = Data(repeating: 0x48, count: 4096)       // 相同的前 4 KB

    func write(_ rel: String, _ data: Data) {
        try? data.write(to: root.appendingPathComponent(rel))
    }

    write("a/big1.bin", big)
    write("b/big2.bin", big)                        // 与 big1 完全相同 → 应检出
    write("c/diff.bin", diff)                       // 同尺寸不同内容 → 应排除
    write("a/tiny.bin", Data(repeating: 0x01, count: 100))  // 小于 1MB → 应跳过
    write("a/head_same.bin", head + Data(repeating: 0x41, count: 4_000_000))  // 前4KB同、整体不同
    write("b/head_same.bin", head + Data(repeating: 0x42, count: 4_000_000))

    // 硬链接：同一份数据两个路径 → 不算重复
    try? fm.linkItem(atPath: root.appendingPathComponent("a/big1.bin").path,
                     toPath: root.appendingPathComponent("c/hardlink.bin").path)
    return root
}

// 让 DuplicateFinder 的非隔离静态方法可被调用
@MainActor func run() async {
    let fixture = buildFixture()
    defer { try? FileManager.default.removeItem(at: fixture) }

    let finder = DuplicateFinder()
    finder.roots = [fixture]
    finder.startScan()

    // 等扫描结束
    var waited = 0.0
    while finder.isScanning && waited < 60 {
        try? await Task.sleep(nanoseconds: 100_000_000); waited += 0.1
    }

    print("=== 扫描结果 ===")
    print("组数: \(finder.groups.count)")
    for g in finder.groups {
        print("\n组 hash=\(g.hash.prefix(12))…  单个 \(Fmt.size(g.size))  可回收 \(Fmt.size(g.reclaimable))")
        for f in g.files { print("   · \(f.path)") }
    }

    print("\n=== 断言 ===")
    var fail = 0
    func expect(_ cond: Bool, _ msg: String) {
        print("\(cond ? "✅" : "❌") \(msg)"); if !cond { fail += 1 }
    }
    let allFiles = finder.groups.flatMap { $0.files.map(\.path) }

    expect(finder.groups.count == 1, "应恰好检出 1 组重复（实际 \(finder.groups.count)）")
    expect(allFiles.contains { $0.hasSuffix("a/big1.bin") }, "应包含 a/big1.bin")
    expect(allFiles.contains { $0.hasSuffix("b/big2.bin") }, "应包含 b/big2.bin")
    expect(!allFiles.contains { $0.hasSuffix("c/diff.bin") }, "不同内容不得被判为重复")
    expect(!allFiles.contains { $0.hasSuffix("c/hardlink.bin") }, "硬链接不得被判为重复（同一份数据）")
    expect(!allFiles.contains { $0.hasSuffix("a/head_same.bin") }, "前4KB相同但整体不同，不得判为重复")
    expect(!allFiles.contains { $0.hasSuffix("b/head_same.bin") }, "同上")
    expect(!allFiles.contains { $0.hasSuffix("tiny.bin") }, "小于 1MB 应被跳过")

    // 选择策略
    finder.selectDuplicates(keeping: .oldest)
    expect(finder.selectedCount == 1, "每组保留一份 → 应勾选 1 项（实际 \(finder.selectedCount)）")
    finder.clearSelection()
    expect(finder.selectedCount == 0, "清空选择应生效")

    let items = finder.selectedItems()
    expect(items.allSatisfy { $0.category == .duplicates }, "产出的 CleanupItem 类别应为 duplicates")
    expect(items.allSatisfy { $0.risk == .caution }, "风险等级应为 caution（不当作安全项）")

    print(fail == 0 ? "\n✅ 全部通过" : "\n❌ \(fail) 项失败")
    exit(fail == 0 ? 0 : 1)
}
await run()
