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
    let inv = AppInventory()
    inv.startScan()
    var waited = 0.0
    while inv.isScanning && waited < 120 {
        try? await Task.sleep(nanoseconds: 200_000_000); waited += 0.2
    }

    print("=== 扫描结果 ===")
    print("应用数: \(inv.apps.count)   不可读目录: \(inv.skippedDirCount)")
    print("\n前 10 个（按残留体积排序）:")
    for app in inv.apps.prefix(10) {
        print("  \(app.name.padding(toLength: 22, withPad: " ", startingAt: 0)) 本体 \(Fmt.size(app.bundleSize).padding(toLength: 9, withPad: " ", startingAt: 0)) 残留 \(Fmt.size(app.residueSize).padding(toLength: 9, withPad: " ", startingAt: 0)) 共 \(Fmt.size(app.totalSize).padding(toLength: 9, withPad: " ", startingAt: 0)) (\(app.residues.count) 项)")
    }

    print("\n=== 断言 ===")
    var fail = 0
    func expect(_ c: Bool, _ m: String) { print("\(c ? "✅" : "❌") \(m)"); if !c { fail += 1 } }

    expect(!inv.apps.isEmpty, "应枚举到应用（实际 \(inv.apps.count)）")
    expect(inv.apps.allSatisfy { !$0.bundleID.hasPrefix("com.apple.") }, "不应包含系统应用")
    expect(inv.apps.allSatisfy { $0.bundleID.contains(".") }, "每个应用都应有合法 bundle id")
    expect(inv.apps.allSatisfy { $0.bundleURL.pathExtension == "app" }, "都应是 .app")
    expect(inv.hasScanned, "应标记为已扫描")

    let allResidues = inv.apps.flatMap(\.residues)
    expect(!allResidues.isEmpty, "应找到残留项（实际 \(allResidues.count)）")
    expect(allResidues.allSatisfy { $0.path.contains("/Library/") }, "残留都应位于 ~/Library 内")
    expect(allResidues.allSatisfy { $0.size >= 0 }, "体积不应为负")

    var mismatch = 0
    for app in inv.apps {
        for r in app.residues {
            let n = r.url.lastPathComponent.lowercased()
            let b = app.bundleID.lowercased()
            if !(n == b || n.hasPrefix(b + ".")) { mismatch += 1 }
        }
    }
    expect(mismatch == 0, "残留命名均与 bundle id 匹配（不匹配 \(mismatch) 项）")

    if let first = inv.apps.firstIndex(where: { !$0.residues.isEmpty }) {
        let name = inv.apps[first].name
        inv.selectAllResidues(appIndex: first)
        expect(inv.selectedCount > 0, "全选残留应生效（\(name)：\(inv.selectedCount) 项）")
        let items = inv.selectedResidueItems()
        expect(items.allSatisfy { $0.category == .appResidue }, "残留类别应为 appResidue")
        expect(items.allSatisfy { $0.risk == .caution }, "残留风险应为 caution")
        expect(items.allSatisfy { $0.isSelected }, "产出的项应处于已选状态")
        let b = inv.bundleItem(appIndex: first)
        expect(b != nil, "应能取到应用本体条目")
        expect(b?.risk == .dangerous, "应用本体风险应为 dangerous")
        expect(b?.url.pathExtension == "app", "本体条目应指向 .app")
        inv.selectNothing(appIndex: first)
        expect(inv.selectedCount == 0, "全不选应生效")
    }

    print(fail == 0 ? "\n✅ 全部通过" : "\n❌ \(fail) 项失败")
    exit(fail == 0 ? 0 : 1)
}
await run()
