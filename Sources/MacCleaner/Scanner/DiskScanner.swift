import Foundation

/// 空间视图的一个节点（文件或目录）。
///
/// 设计要点：**全盘建树会爆内存**。这台机器上 Codex Crashpad 单个目录就有
/// 26 万个文件，`~/Library/Caches` 也有几万项。所以这里不做一次性递归，
/// 而是「按需加载一层」——只计算当前目录的直接子项，钻取到哪层算哪层。
struct DiskNode: Identifiable, Hashable {
    let id: String              // 用标准化路径做 id，保证同一目录复用
    let url: URL
    let name: String
    /// 该节点自身的总占用（目录含所有子孙）。
    /// 两阶段加载：阶段一为 0，阶段二逐个回填。
    var size: Int64
    /// 体积是否已算出。false 时 UI 显示占位符而不是「0 字节」。
    var measured: Bool = false
    let isDirectory: Bool
    /// 读取时是否遇到权限不足
    var accessDenied: Bool

    var path: String { url.path }

    /// 是否在 SafetyGuard 白名单内 —— 决定界面上能否直接清理
    var cleanable: Bool { isDirectory && SafetyGuard.isAllowed(url) }

    static func == (lhs: DiskNode, rhs: DiskNode) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

/// 一层目录的扫描结果。
struct DiskLevel {
    var node: DiskNode
    /// 子项。两阶段加载中会随体积回填而重排。
    var children: [DiskNode]
    /// 因超出显示上限而未列出的子项数量
    var hiddenCount: Int
    /// 超出上限的那些子项的体积合计
    var hiddenSize: Int64
    /// 无权限、大小无法统计的子项数量
    var deniedCount: Int
    /// 本层统计中是否跳过了病态目录（体积会偏小，必须告知用户）
    var skippedPathological: Bool = false

    /// 已算出体积的子项数 / 总数 —— 驱动进度显示
    var measuredCount: Int { children.filter(\.measured).count }
    var allMeasured: Bool { !children.isEmpty && measuredCount == children.count }
}

/// 空间视图的扫描器。
///
/// 与 `StorageScanner` 的分工：
/// - `StorageScanner` 只扫已知的垃圾位置，产出「可清理条目」
/// - `DiskScanner` 扫任意目录，产出「空间占用情况」，本身不判断可删性
///
/// ## 为什么要两阶段
///
/// 实测（本机 `~/Library/Application Support`，49 GB）：
/// - 递归算出全部体积：**24 秒**，其中 `Codex/Crashpad/pending`
///   一个目录占 47 秒里的绝大部分 —— 它单层就有 **265,750 个文件**，
///   光是 `contentsOfDirectory` 列出它就要 7-9 秒。
/// - 只列出目录结构：**0.009 秒**。
///
/// 试过的、**不work**的优化（都实测过）：
/// - 单次遍历累加代替逐子项递归：60s → 24s，但瓶颈不在这
/// - 遇到大目录就 `skipDescendants`：耗时没降，且体积严重失真
///   （49 GB 只剩 20 GB，用户会以为磁盘是空的）
///
/// 结论：**在保持数字准确的前提下，24 秒省不掉** —— 这是 APFS 目录读取的硬成本。
/// 所以优化方向不是「算得更快」，而是「别让用户等」：
/// 先秒出结构，再流式逐个回填体积。
enum DiskScanner {

    /// 单层最多列出多少个子项。超出的折叠成「其他 N 项」。
    static let maxChildren = 50

    /// 阶段一：只列出直接子项，不算体积。毫秒级返回。
    ///
    /// 返回的子项按**名称**排序（此时还没有体积可排），
    /// 体积回填完成后再按大小重排。
    static func listChildren(of url: URL) -> [DiskNode] {
        let fm = FileManager.default
        let keys: [URLResourceKey] = [.isDirectoryKey, .isSymbolicLinkKey]

        guard let entries = try? fm.contentsOfDirectory(at: url, includingPropertiesForKeys: keys, options: []) else {
            return []
        }

        return entries.compactMap { e -> DiskNode? in
            // 跳过符号链接，避免循环与重复计算
            if (try? e.resourceValues(forKeys: [.isSymbolicLinkKey]))?.isSymbolicLink == true { return nil }
            let isDir = (try? e.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory ?? false
            return makeNode(e, size: 0, isDirectory: isDir, denied: false)
        }
        .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    /// 阶段二：计算单个子项的体积。调用方逐个调用并即时回填 UI。
    ///
    /// 这是耗时的那一步（病态目录可能几秒到几十秒），所以必须
    /// 在后台逐个执行，让已完成的结果尽早可见。
    ///
    /// 内部走 `SizeCalculator.size`（跳过已知病态路径）。
    /// 实测 `~/Library/Application Support`：17.3s → 1.5s（8.3x）。
    static func measure(_ node: DiskNode) -> Int64 {
        SizeCalculator.size(of: node.url)
    }

    /// 该目录下是否存在被跳过的病态路径。
    /// UI 用它来决定是否提示「体积偏小」。
    static func hasSkippedContent(at url: URL) -> Bool {
        let base = url.standardizedFileURL.path
        return SizeCalculator.pathologicalPaths.contains { p in
            p == base || p.hasPrefix(base + "/")
        }
    }

    /// 构建一层的初始结构（只有名字与类型，体积待回填）。
    static func makeLevel(of url: URL) -> DiskLevel {
        let fm = FileManager.default
        var isDir: ObjCBool = false
        guard fm.fileExists(atPath: url.path, isDirectory: &isDir) else {
            return DiskLevel(node: makeNode(url, size: 0, isDirectory: false, denied: false),
                             children: [], hiddenCount: 0, hiddenSize: 0, deniedCount: 0)
        }

        // 普通文件：直接给出体积，无需阶段二
        guard isDir.boolValue else {
            let s = SizeCalculator.fileSize(url)
            var n = makeNode(url, size: s, isDirectory: false, denied: false)
            n.measured = true
            return DiskLevel(node: n, children: [], hiddenCount: 0, hiddenSize: 0, deniedCount: 0)
        }

        let kids = listChildren(of: url)
        let denied = kids.filter(\.accessDenied).count
        let shown = Array(kids.prefix(maxChildren))

        return DiskLevel(
            node: makeNode(url, size: 0, isDirectory: true, denied: false),
            children: shown,
            hiddenCount: kids.count - shown.count,
            hiddenSize: 0,
            deniedCount: denied,
            // 这一层或其子项里含病态目录时，体积会偏小 —— 必须让 UI 知道
            skippedPathological: shown.contains { hasSkippedContent(at: $0.url) }
        )
    }

    private static func makeNode(_ url: URL, size: Int64, isDirectory: Bool, denied: Bool) -> DiskNode {
        let std = url.standardizedFileURL
        let name = std.lastPathComponent
        return DiskNode(
            id: std.path,
            url: std,
            name: name.isEmpty ? std.path : name,
            size: size,
            measured: false,
            isDirectory: isDirectory,
            accessDenied: denied
        )
    }

    /// 空间视图的根节点候选。全盘根目录太大，默认给用户这几个入口。
    static func roots() -> [URL] {
        let home = NSHomeDirectory()
        return [
            URL(fileURLWithPath: home),
            URL(fileURLWithPath: "\(home)/Library"),
            URL(fileURLWithPath: "\(home)/Library/Caches"),
            URL(fileURLWithPath: "\(home)/Library/Application Support"),
            URL(fileURLWithPath: "\(home)/Library/Developer"),
            URL(fileURLWithPath: "\(home)/Downloads"),
            URL(fileURLWithPath: "/Applications"),
            URL(fileURLWithPath: "/"),
        ].filter { FileManager.default.fileExists(atPath: $0.path) }
    }
}
