import Foundation
enum Fmt { static func size(_ b: Int64) -> String { ByteCountFormatter.string(fromByteCount: b, countStyle: .file) } }
import Foundation

@MainActor func run() async {
    var fail = 0
    func expect(_ c: Bool, _ m: String) { print("\(c ? "✅" : "❌") \(m)"); if !c { fail += 1 } }

    let p = DiskHealthProbe()
    p.refresh()
    var waited = 0.0
    while p.isLoading && waited < 30 { try? await Task.sleep(nanoseconds: 100_000_000); waited += 0.1 }

    let v = p.volume
    print("=== 卷信息 ===")
    print("卷名: \(v.name)")
    print("文件系统: \(v.fileSystem)")
    print("设备: \(v.deviceNode)")
    print("SSD: \(v.isSolidState.map(String.init(describing:)) ?? "不可读")")
    print("加密: \(v.isEncrypted.map(String.init(describing:)) ?? "不可读")")
    print("只读: \(v.isReadOnly.map(String.init(describing:)) ?? "不可读")")
    print("SMART: \(v.smartStatus ?? "不可读")")
    print("总容量: \(Fmt.size(v.totalBytes))")
    print("可用: \(Fmt.size(v.freeBytes))")
    print("\n=== 容器 ===")
    for c in p.containers {
        print("\(c.reference): 总 \(Fmt.size(c.totalBytes)) 已用 \(Fmt.size(c.usedBytes)) 未分配 \(Fmt.size(c.freeBytes)) 快照 \(c.snapshotCount)")
    }
    print("\n=== 快照 ===")
    print(p.localSnapshots.isEmpty ? "（无）" : p.localSnapshots.joined(separator: "\n"))

    print("\n=== 断言 ===")
    expect(p.lastUpdated != nil, "应完成刷新")
    expect(!p.isLoading, "应结束加载状态")
    expect(v.totalBytes > 0, "总容量应 > 0")
    expect(v.name != "—", "应读到卷名")
    expect(v.fileSystem != "—", "应读到文件系统")
    expect(v.deviceNode.hasPrefix("/dev/"), "设备节点应以 /dev/ 开头")
    expect(v.isSolidState != nil, "应判断出介质类型")
    expect(v.freeBytes >= 0, "可用容量不应为负")
    expect(v.totalBytes >= v.freeBytes, "总容量应 ≥ 可用")
    expect(!p.containers.isEmpty, "应读到至少一个 APFS 容器")
    if let c = p.containers.first {
        expect(c.totalBytes > 0, "容器总容量应 > 0")
        expect(c.usedBytes > 0, "容器已用应 > 0")
        expect(c.reference.hasPrefix("disk"), "容器引用应以 disk 开头（实际 \(c.reference)）")
    }
    // SMART 允许不可读，但不应崩溃
    print(v.smartStatus == nil ? "ℹ️ SMART 不可读（属正常）" : "ℹ️ SMART = \(v.smartStatus!)")

    print(fail == 0 ? "\n✅ 全部通过" : "\n❌ \(fail) 项失败")
    exit(fail == 0 ? 0 : 1)
}
await run()
