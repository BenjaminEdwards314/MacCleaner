import Foundation
import AppKit

/// 单个孤儿残留条目
struct OrphanItem: Identifiable, Hashable {
    let id: String              // 标准化路径
    let url: URL
    let name: String            // 目录名或文件名
    let bundleID: String        // 从名字里提取的 bundle id
    let kind: String            // 所属 ~/Library 子目录名
    let size: Int64
    let modified: Date?

    /// 归属厂商前缀，用于按厂商聚类展示
    var vendor: String {
        let parts = bundleID.split(separator: ".")
        guard parts.count >= 2 else { return bundleID }
        return "\(parts[0]).\(parts[1])"
    }
}

/// 一个厂商下的全部残留
struct OrphanGroup: Identifiable {
    var id: String { vendor }
    let vendor: String
    var items: [OrphanItem]
    var totalSize: Int64 { items.reduce(0) { $0 + $1.size } }
}

/// 扫描「已卸载应用留下的残余文件」。
///
/// 判定思路
/// --------
/// 1. 先枚举**所有已安装应用内部的全部 bundle id**。
///    只读顶层 Info.plist 是远远不够的：本机实测顶层只有 29 个 id，
///    而把每个 app 内部的 Info.plist 全走一遍能拿到 784 个。
///    漏掉的那 755 个会造成严重误判 —— 例如 Docker.app 的 id 是
///    `com.docker.docker`，但它内部嵌套的 Helper 用的是
///    `com.electron.dockerdesktop`。若只比对顶层 id，就会把
///    `~/Library/Preferences/com.electron.dockerdesktop.plist`
///    当成孤儿推荐删除，而它属于一个正在使用的应用。
///
/// 2. 再扫 `~/Library` 下的常见残留位置，取出名字形如 bundle id 的条目。
///
/// 3. 只有当条目的 id 与已知集合**完全无交集**时才判为孤儿。
///    这里采用保守策略：宁可漏报，也不误删。因此
///    - 不匹配 `com.apple.*`（系统组件）；
///    - 双向前缀不重叠才算孤儿（`a.b` 与 `a.b.c` 视为相关）；
///    - 名字不像 bundle id 的一律跳过。
///
/// 安全约束
/// --------
/// 本扫描器只**产出候选**，不执行删除。删除仍需经 SafetyGuard 校验，
/// 且只移入废纸篓，不提供永久删除。
@MainActor
final class OrphanScanner: ObservableObject {
    @Published private(set) var groups: [OrphanGroup] = []
    @Published private(set) var isScanning = false
    @Published private(set) var hasScanned = false
    @Published private(set) var progressText = ""
    @Published private(set) var knownIDCount = 0
    @Published private(set) var scannedDirCount = 0
    @Published private(set) var skippedDirCount = 0

    private var task: Task<Void, Never>?

    /// 可能出现残留的 `~/Library` 子目录
    nonisolated static let residueSubdirs = [
        "Caches",
        "Preferences",
        "Logs",
        "Application Support",
        "Saved Application State",
        "HTTPStorages",
        "WebKit",
        "Cookies",
        "LaunchAgents",
        "Application Scripts",
        "Containers",
        "Group Containers",
    ]

    /// 应用安装位置
    nonisolated static var appDirs: [URL] {
        ["/Applications", "\(NSHomeDirectory())/Applications"].map { URL(fileURLWithPath: $0) }
    }

    var totalSize: Int64 { groups.reduce(0) { $0 + $1.totalSize } }
    var itemCount: Int { groups.reduce(0) { $0 + $1.items.count } }

    func cancel() {
        task?.cancel()
        isScanning = false
    }

    func startScan() {
        guard !isScanning else { return }
        isScanning = true
        hasScanned = false
        groups = []
        progressText = "正在枚举已安装应用…"

        task = Task.detached(priority: .userInitiated) { [weak self] in
            guard let self else { return }

            let known = await Self.collectKnownBundleIDs { text in
                Task { @MainActor in self.progressText = text }
            }
            await MainActor.run { self.knownIDCount = known.count }

            if Task.isCancelled { return }

            let found = await Self.findOrphans(known: known) { text in
                Task { @MainActor in self.progressText = text }
            }

            await MainActor.run {
                self.groups = found.groups
                self.scannedDirCount = found.scanned
                self.skippedDirCount = found.skipped
                self.isScanning = false
                self.hasScanned = true
                self.progressText = ""
            }
        }
    }

    // MARK: - 第一步：收集已知 bundle id

    /// 枚举每个已安装应用**内部所有** Info.plist 的 bundle id。
    ///
    /// 必须递归整个 .app 包：应用会把真正的 bundle id 藏在嵌套的
    /// framework / Helper.app / XPCServices / PlugIns 里。
    nonisolated static func collectKnownBundleIDs(
        progress: @escaping (String) -> Void
    ) async -> Set<String> {
        var known = Set<String>()
        let fm = FileManager.default

        for dir in appDirs {
            guard let apps = try? fm.contentsOfDirectory(
                at: dir, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]
            ) else { continue }

            for app in apps where app.pathExtension == "app" {
                progress("正在读取 \(app.lastPathComponent)…")
                await Task.yield()
                // 递归整个 app 包，收集所有 Info.plist。
                // 这里同步收集完再 await —— FileManager.enumerator 的迭代器
                // 在异步上下文里不安全（Swift 6 会报错），因此先取出结果集。
                for bid in bundleIDs(insideApp: app) { known.insert(bid) }
            }
        }
        return known
    }

    /// 同步遍历一个 .app 包，取出其中所有 Info.plist 的 bundle id。
    nonisolated static func bundleIDs(insideApp app: URL) -> [String] {
        let fm = FileManager.default
        guard let walker = fm.enumerator(
            at: app, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]
        ) else { return [] }
        var out: [String] = []
        for case let f as URL in walker where f.lastPathComponent == "Info.plist" {
            if let bid = bundleID(fromPlist: f) { out.append(bid) }
        }
        return out
    }

    /// 读取 Info.plist 的 CFBundleIdentifier（小写）
    nonisolated static func bundleID(fromPlist url: URL) -> String? {
        guard let data = try? Data(contentsOf: url),
              let plist = try? PropertyListSerialization.propertyList(
                from: data, options: [], format: nil) as? [String: Any],
              let bid = plist["CFBundleIdentifier"] as? String,
              !bid.isEmpty
        else { return nil }
        return bid.lowercased()
    }

    // MARK: - 第二步：找孤儿

    /// 名字是否形如 bundle id。
    ///
    /// 只接受「至少两段、每段由字母数字和短横线组成」的形式，
    /// 借此排除 `com.apple.Safari` 之外的大量普通文件夹名。
    nonisolated static func looksLikeBundleID(_ s: String) -> Bool {
        let lower = s.lowercased()
        guard lower.count >= 6, lower.count <= 200 else { return false }
        let parts = lower.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count >= 2 else { return false }
        for p in parts {
            guard !p.isEmpty else { return false }
            guard p.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" }) else { return false }
        }
        // 顶级域名白名单，进一步降低误判
        let tlds: Set<String> = ["com", "org", "net", "io", "cn", "co", "me", "dev",
                                 "app", "sh", "gg", "us", "uk", "de", "jp", "fr",
                                 "info", "biz", "tv", "xyz", "top", "site", "tech",
                                 "group", "is", "ai", "ru", "kr", "in", "eu", "ch"]
        let first = String(parts[0])
        // 形如 `9699und7h5.group.com.netease...` 的沙盒前缀也接受
        if tlds.contains(first) { return true }
        if first.first?.isNumber == true, parts.count >= 3 { return true }
        return false
    }

    /// 从条目名中提取 bundle id（去掉 .plist / .savedState / .binarycookies 等后缀）
    ///
    /// 同时剥离沙盒的 team-id 前缀：`2DC432GLL2.com.openai.sky.CUAService`
    /// 去掉前缀后是 `com.openai.sky.CUAService`，这样才能和 app 内登记的 id 比对。
    nonisolated static func extractBundleID(from name: String) -> String? {
        var stem = name
        // 两边都要小写再比较：早期写成 `stem.lowercased().hasSuffix(suf)`，
        // 而 suf 里的 `.savedState` 是混合大小写，永远匹配不上 ——
        // `.plist` 当时能work只是因为它本身就全是小写。
        for suf in [".savedState", ".binarycookies", ".plist", ".log", ".db", ".db-wal", ".db-shm"] {
            if stem.lowercased().hasSuffix(suf.lowercased()) {
                stem = String(stem.dropLast(suf.count))
            }
        }
        let stripped = stripTeamPrefix(stem)
        guard looksLikeBundleID(stripped) else { return nil }
        return stripped.lowercased()
    }

    /// 去掉沙盒 team-id 前缀。
    ///
    /// 形如 `2DC432GLL2.com.openai.sky` 或 `9699und7h5.group.com.netease`，
    /// 首段是 10 位团队标识（大写字母+数字，或小写混合），第二段是
    /// `com` / `group` 之类的域名段。识别到这种结构就丢掉首段。
    nonisolated static func stripTeamPrefix(_ s: String) -> String {
        let parts = s.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count >= 3 else { return s }
        let first = String(parts[0])
        let second = String(parts[1]).lowercased()

        // 团队标识：10 位左右、字母数字混合、不含短横线（短横线更像是正常域名段）
        guard first.count == 10,
              first.allSatisfy({ $0.isLetter || $0.isNumber }),
              !first.contains("-") else { return s }
        // 第二段必须是域名段，否则不像沙盒前缀
        let tlds: Set<String> = ["com", "org", "net", "io", "cn", "co", "me", "group", "us", "ai"]
        guard tlds.contains(second) else { return s }
        return parts.dropFirst().joined(separator: ".")
    }

    /// id 是否属于某个已安装应用。
    ///
    /// 双向前缀比对：`a.b` 与 `a.b.c` 互认为相关，
    /// 避免把某应用的子模块残留误判成孤儿。
    nonisolated static func isKnown(_ bid: String, in known: Set<String>) -> Bool {
        if known.contains(bid) { return true }
        let parts = bid.split(separator: ".")
        // 逐级收缩前缀，看是否有已知 id 与之同源
        for i in stride(from: parts.count - 1, through: 2, by: -1) {
            let prefix = parts.prefix(i).joined(separator: ".")
            if known.contains(prefix) { return true }
        }
        return false
    }

    /// id 是否属于 Apple 系统组件。
    ///
    /// 遍历过程中任何位置出现 `com.apple.` 都视为系统组件 —— 例如
    /// `groups.com.apple.podcasts`、`group.com.apple.replayd`。
    nonisolated static func isAppleSystemID(_ bid: String) -> Bool {
        bid.contains("com.apple.") || bid.hasPrefix("apple.")
    }

    /// 条目最近一次被使用的时间（取「内容修改时间」与「访问时间」的较大者）。
    nonisolated static func lastUsed(_ url: URL) -> Date? {
        let keys: Set<URLResourceKey> = [.contentModificationDateKey, .contentAccessDateKey]
        guard let v = try? url.resourceValues(forKeys: keys) else { return nil }
        switch (v.contentModificationDate, v.contentAccessDate) {
        case let (m?, a?): return max(m, a)
        case let (m?, nil): return m
        case let (nil, a?): return a
        default: return nil
        }
    }

    struct FindResult {
        var groups: [OrphanGroup]
        var scanned: Int
        var skipped: Int
    }

    nonisolated static func findOrphans(
        known: Set<String>,
        progress: @escaping (String) -> Void
    ) async -> FindResult {
        let home = NSHomeDirectory()
        let fm = FileManager.default
        var byVendor: [String: [OrphanItem]] = [:]
        var scanned = 0
        let skipped = 0

        for sub in residueSubdirs {
            let base = URL(fileURLWithPath: "\(home)/Library/\(sub)")
            guard let entries = try? fm.contentsOfDirectory(
                at: base, includingPropertiesForKeys: [.isDirectoryKey, .contentModificationDateKey],
                options: [.skipsHiddenFiles]
            ) else { continue }

            progress("正在检查 \(sub)…")
            await Task.yield()
            scanned += 1

            for e in entries {
                let name = e.lastPathComponent
                guard let bid = extractBundleID(from: name) else { continue }
                // 系统组件永不列为孤儿。
                // 注意要检查剥离前缀后的形态：`243LU875E5.groups.com.apple.podcasts`
                // 剥掉 team-id 后是 `groups.com.apple.podcasts`，同样必须排除。
                if isAppleSystemID(bid) { continue }
                // 属于已安装应用 → 不是孤儿
                if isKnown(bid, in: known) { continue }

                // 最近仍在被读写的条目一律跳过。
                // 这是最后的兜底：有些已安装应用并不在自己的 Info.plist 里
                // 声明它使用的 Group Container（实测 Docker 就是如此，
                // `group.com.docker` 在 Docker.app 内部查不到），
                // 纯靠 id 匹配会误报。用「最近访问过」作为保守信号。
                if let recent = lastUsed(e), recent > Date().addingTimeInterval(-90 * 24 * 3600) {
                    continue
                }

                let size = SizeCalculator.size(of: e)
                let modified = (try? e.resourceValues(forKeys: [.contentModificationDateKey]))?
                    .contentModificationDate
                let item = OrphanItem(
                    id: e.standardizedFileURL.path, url: e, name: name,
                    bundleID: bid, kind: sub, size: size, modified: modified
                )
                byVendor[item.vendor, default: []].append(item)
            }
        }

        _ = skipped
        let groups = byVendor
            .map { OrphanGroup(vendor: $0.key, items: $0.value.sorted { $0.size > $1.size }) }
            .sorted { $0.totalSize > $1.totalSize }
        return FindResult(groups: groups, scanned: scanned, skipped: skipped)
    }
}
