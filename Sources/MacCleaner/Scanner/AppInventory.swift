import Foundation

/// 已安装应用清单与残留扫描。
///
/// ## 为什么需要它
///
/// 把 `.app` 拖进废纸篓只删掉了程序本体，缓存在 `~/Library` 里的数据会永久留下。
/// 这个类枚举应用本体，并按 bundle identifier 找出它的残留。
///
/// ## 残留识别方式
///
/// 只做**目录列举 + 名称匹配**，不递归遍历、不读文件内容 ——
/// 残留目录的命名约定很固定（要么是 bundle id 本身，要么以其为前缀），
/// 所以列举一层目录就足够，代价极低。
///
/// ## 有意不扫描的位置
///
/// `~/Library/Containers` 与 `~/Library/Group Containers` 未纳入。
/// 沙盒应用的数据在这里，但该目录同时存放系统组件的数据，
/// 误删后果严重，因此不开放（`SafetyGuard` 也会拒绝）。
/// 界面会明确标注这一限制。
@MainActor
final class AppInventory: ObservableObject {

    /// 一个已安装应用及其残留
    struct InstalledApp: Identifiable {
        let id = UUID()
        let bundleURL: URL
        let bundleID: String
        let name: String
        let version: String
        let bundleSize: Int64
        /// 残留项（不含应用本体）
        var residues: [Residue]

        /// 应用本体 + 全部残留
        var totalSize: Int64 { bundleSize + residues.reduce(0) { $0 + $1.size } }
        var residueSize: Int64 { residues.reduce(0) { $0 + $1.size } }
    }

    struct Residue: Identifiable, Hashable {
        let id = UUID()
        let url: URL
        let size: Int64
        /// 所属的 `~/Library` 子目录名，界面上用来分组
        let kind: String
        var isSelected: Bool = false

        var path: String { url.path }
    }

    @Published private(set) var isScanning = false
    @Published private(set) var progressText = ""
    @Published private(set) var apps: [InstalledApp] = []
    @Published private(set) var hasScanned = false
    /// 扫描不到的目录数量，用于提示「部分残留可能未列出」
    @Published private(set) var skippedDirCount = 0

    private var task: Task<Void, Never>?

    func cancel() {
        task?.cancel()
        isScanning = false
    }

    /// 应用本体的搜索目录
    nonisolated static var searchDirs: [URL] {
        ["/Applications", "\(NSHomeDirectory())/Applications"]
            .map { URL(fileURLWithPath: $0) }
    }

    /// 残留可能出现的位置：`~/Library` 下的子目录名
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
    ]

    func startScan() {
        guard !isScanning else { return }
        isScanning = true
        hasScanned = false
        apps = []
        skippedDirCount = 0
        progressText = "正在枚举应用…"

        task = Task.detached(priority: .userInitiated) { [weak self] in
            guard let self else { return }

            let found = await Self.enumerateApps { text in
                Task { @MainActor in self.progressText = text }
            }
            let skipped = await Self.lastSkippedCount

            await MainActor.run {
                self.apps = found
                self.skippedDirCount = skipped
                self.isScanning = false
                self.hasScanned = true
                self.progressText = ""
            }
        }
    }

    /// 扫描过程中遇到的不可读目录数。用 actor 隔离，避免并发写。
    private actor Counter {
        var value = 0
        func increment() { value += 1 }
        var count: Int { value }
    }
    private static let skipCounter = Counter()
    private static var lastSkippedCount: Int {
        get async { await skipCounter.count }
    }

    // MARK: - 枚举实现

    private nonisolated static func enumerateApps(
        progress: @escaping (String) -> Void
    ) async -> [InstalledApp] {

        let fm = FileManager.default
        var bundles: [URL] = []

        for dir in searchDirs {
            guard let entries = try? fm.contentsOfDirectory(
                at: dir,
                includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey],
                options: [.skipsHiddenFiles]
            ) else { continue }

            for e in entries where e.pathExtension == "app" {
                // 跳过符号链接，避免把同一个应用统计两次
                let isLink = (try? e.resourceValues(forKeys: [.isSymbolicLinkKey]))?.isSymbolicLink
                if isLink == true { continue }
                bundles.append(e)
            }
        }

        bundles.sort { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }

        var result: [InstalledApp] = []
        var residueIndex: [String: [Residue]] = [:]

        // 一次性列举 ~/Library 各残留目录，并建立「名称 → URL」索引，
        // 避免为每个应用重复列举同一批目录（27 个应用 × 10 个目录 = 270 次列举）。
        progress("正在索引残留目录…")
        let library = NSHomeDirectory() + "/Library"
        var dirContents: [String: [String: URL]] = [:]

        for sub in residueSubdirs {
            let dirPath = "\(library)/\(sub)"
            guard let entries = try? fm.contentsOfDirectory(
                at: URL(fileURLWithPath: dirPath),
                includingPropertiesForKeys: nil,
                options: [.skipsHiddenFiles]
            ) else {
                await skipCounter.increment()
                continue
            }
            // 键统一小写：bundle id 大小写不敏感，但文件名大小写可能不一致
            var map: [String: URL] = [:]
            for e in entries { map[e.lastPathComponent.lowercased()] = e }
            dirContents[sub] = map
        }

        // 逐个应用解析 Info.plist 并匹配残留
        for (idx, bundle) in bundles.enumerated() {
            if Task.isCancelled { return [] }
            progress("正在分析 \(bundle.lastPathComponent)…（\(idx + 1)/\(bundles.count)）")

            guard let info = readInfoPlist(bundle) else { continue }
            let bid = info.bundleID
            let name = info.name

            // 系统应用不参与卸载（用户无法删除，也不该显示）
            if bid.hasPrefix("com.apple.") { continue }

            let size = SizeCalculator.size(of: bundle)
            let residues = residuesFor(
                bundleID: bid,
                appName: name,
                dirContents: dirContents,
                cache: &residueIndex
            )

            result.append(InstalledApp(
                bundleURL: bundle,
                bundleID: bid,
                name: name,
                version: info.version,
                bundleSize: size,
                residues: residues
            ))
        }

        // 有残留的排前面，其次按总体积降序
        result.sort {
            if ($0.residueSize > 0) != ($1.residueSize > 0) { return $0.residueSize > 0 }
            return $0.totalSize > $1.totalSize
        }
        return result
    }

    private struct AppInfo {
        let bundleID: String
        let name: String
        let version: String
    }

    private nonisolated static func readInfoPlist(_ bundle: URL) -> AppInfo? {
        let plist = bundle.appendingPathComponent("Contents/Info.plist")
        guard let data = try? Data(contentsOf: plist),
              let obj = try? PropertyListSerialization.propertyList(
                from: data, options: [], format: nil) as? [String: Any]
        else { return nil }

        let bid = obj["CFBundleIdentifier"] as? String ?? ""
        guard !bid.isEmpty else { return nil }

        // 显示名优先取 CFBundleDisplayName，退回 CFBundleName，再退回文件名
        let name = (obj["CFBundleDisplayName"] as? String)
            ?? (obj["CFBundleName"] as? String)
            ?? bundle.deletingPathExtension().lastPathComponent

        return AppInfo(
            bundleID: bid,
            name: name,
            version: obj["CFBundleShortVersionString"] as? String ?? "—"
        )
    }

    /// 按 bundle id 匹配残留。
    ///
    /// 匹配规则：条目名等于 bundle id，或以 `<bundle id>.` 开头
    /// （例如 `com.x.y.plist`、`com.x.y.savedState`）。
    /// 应用名匹配只在少数几个目录里额外尝试，因为按名字匹配误报率高。
    private nonisolated static func residuesFor(
        bundleID: String,
        appName: String,
        dirContents: [String: [String: URL]],
        cache: inout [String: [Residue]]
    ) -> [Residue] {

        if let cached = cache[bundleID] { return cached }

        let bid = bundleID.lowercased()
        var found: [Residue] = []

        for sub in residueSubdirs {
            guard let map = dirContents[sub] else { continue }
            for (entryName, url) in map {
                let isMatch = entryName == bid || entryName.hasPrefix(bid + ".")
                guard isMatch else { continue }
                found.append(Residue(
                    url: url,
                    size: SizeCalculator.size(of: url),
                    kind: sub
                ))
            }
        }

        found.sort { $0.size > $1.size }
        cache[bundleID] = found
        return found
    }

    // MARK: - 选择

    func toggle(appIndex ai: Int, residueIndex ri: Int) {
        guard apps.indices.contains(ai),
              apps[ai].residues.indices.contains(ri) else { return }
        apps[ai].residues[ri].isSelected.toggle()
    }

    /// 勾选某应用的全部残留（应用本体不勾 —— 用户可能只想清残留）
    func selectAllResidues(appIndex ai: Int) {
        guard apps.indices.contains(ai) else { return }
        for ri in apps[ai].residues.indices {
            apps[ai].residues[ri].isSelected = true
        }
    }

    func selectNothing(appIndex ai: Int) {
        guard apps.indices.contains(ai) else { return }
        for ri in apps[ai].residues.indices {
            apps[ai].residues[ri].isSelected = false
        }
    }

    var selectedCount: Int {
        apps.reduce(0) { $0 + $1.residues.filter(\.isSelected).count }
    }

    var selectedResidueSize: Int64 {
        apps.reduce(0) { acc, app in
            acc + app.residues.filter(\.isSelected).reduce(0) { $0 + $1.size }
        }
    }

    /// 把勾选的残留转成统一的 CleanupItem。
    /// 应用本体由 `uninstallItems(appIndex:)` 单独产出 —— 它的风险更高，
    /// 与残留分开是刻意的。
    func selectedResidueItems() -> [CleanupItem] {
        var out: [CleanupItem] = []
        for app in apps {
            for r in app.residues where r.isSelected {
                out.append(CleanupItem(
                    url: r.url,
                    size: r.size,
                    category: .appResidue,
                    risk: .caution,
                    explanation: "「\(app.name)」的残留（\(r.kind)）",
                    defaultSelected: false,
                    isSelected: true
                ))
            }
        }
        return out
    }

    /// 应用本体条目
    func bundleItem(appIndex ai: Int) -> CleanupItem? {
        guard apps.indices.contains(ai) else { return nil }
        let app = apps[ai]
        return CleanupItem(
            url: app.bundleURL,
            size: app.bundleSize,
            category: .appBundle,
            risk: .dangerous,
            explanation: "应用本体，删除后该应用将不可用",
            defaultSelected: false,
            isSelected: true
        )
    }
}
