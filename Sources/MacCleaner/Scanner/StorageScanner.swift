import Foundation

/// 扫描引擎：遍历已知的缓存/日志位置，产出可清理条目。
@MainActor
final class StorageScanner: ObservableObject {

    @Published var isScanning = false
    @Published var progressText = ""
    @Published var progressValue: Double = 0
    @Published var groups: [CleanupGroup] = []
    @Published var volume = VolumeInfo.current()
    @Published var lastScanDate: Date?

    private var task: Task<Void, Never>?

    func cancel() { task?.cancel(); isScanning = false }

    func startScan(deepScan: Bool = false) {
        guard !isScanning else { return }
        isScanning = true
        progressValue = 0
        groups = []
        volume = VolumeInfo.current()

        task = Task.detached(priority: .userInitiated) { [weak self] in
            guard let self else { return }
            let found = await Self.performScan(deepScan: deepScan) { text, pct in
                Task { @MainActor in
                    self.progressText = text
                    self.progressValue = pct
                }
            }
            await MainActor.run {
                self.groups = found
                    .map { CleanupGroup(category: $0.key, items: $0.value.sorted { $0.size > $1.size }) }
                    .sorted { $0.totalSize > $1.totalSize }
                self.isScanning = false
                self.progressText = ""
                self.progressValue = 1
                self.lastScanDate = Date()
                self.volume = VolumeInfo.current()
            }
        }
    }

    // MARK: - 实际扫描逻辑

    private nonisolated static func performScan(
        deepScan: Bool,
        report: @escaping (String, Double) -> Void
    ) async -> [CleanupCategory: [CleanupItem]] {
        let home = NSHomeDirectory()
        var out: [CleanupCategory: [CleanupItem]] = [:]

        func add(_ item: CleanupItem) {
            guard item.size > 0 else { return }
            out[item.category, default: []].append(item)
        }

        var step = 0.0
        let totalSteps = deepScan ? 9.0 : 7.0
        func tick(_ msg: String) {
            step += 1
            report(msg, step / totalSteps)
        }

        // ---------- 1. 用户缓存 ----------
        tick("扫描用户缓存…")
        await scanChildren(
            of: "\(home)/Library/Caches",
            category: .userCache,
            minSize: 5 * 1024 * 1024,
            risk: .safe,
            explanation: "应用缓存，删除后应用会自动重建。首次启动可能稍慢。"
        ) { add($0) }

        // ---------- 2. 日志 ----------
        tick("扫描日志文件…")
        await scanChildren(
            of: "\(home)/Library/Logs",
            category: .logs,
            minSize: 1 * 1024 * 1024,
            risk: .safe,
            explanation: "应用日志，用于排查问题，可安全删除。"
        ) { add($0) }

        // ---------- 3. 崩溃报告 ----------
        tick("扫描崩溃报告…")
        await scanChildren(
            of: "\(home)/Library/Logs/DiagnosticReports",
            category: .crashReports,
            minSize: 0,
            risk: .safe,
            explanation: "系统崩溃日志，可安全删除。"
        ) { add($0) }

        // 崩溃转储堆积（Crashpad）—— 独立类别，因为这类目录可能异常膨胀
        // （这台机器上 Codex 曾出现 26 万文件的死循环，单目录 21GB）。
        // 单独归类避免它被「崩溃报告」这个 112KB 的小类别掩盖掉。
        let crashpadPending = "\(home)/Library/Application Support/Codex/Crashpad/pending"
        if FileManager.default.fileExists(atPath: crashpadPending) {
            let url = URL(fileURLWithPath: crashpadPending)
            let size = SizeCalculator.size(of: url)
            if size > 100 * 1024 * 1024 {
                let count = SizeCalculator.fileCount(of: url)
                add(CleanupItem(
                    url: url, size: size, category: .crashpad, risk: .caution,
                    explanation: "Codex 崩溃转储堆积（\(count) 个文件）。这是崩溃循环产生的死数据，通常可安全清理。⚠️ 删除前请先退出 ChatGPT/Codex，否则 Crashpad handler 持有目录会失败。",
                    defaultSelected: false   // 需要先退应用，默认不勾选
                ))
            }
        }

        // ---------- 4. 开发缓存 ----------
        tick("扫描开发缓存…")
        let devTargets: [(String, String, Int64)] = [
            ("\(home)/.npm/_cacache", "npm 包缓存，可用 npm cache clean --force 重建", 0),
            ("\(home)/.npm/_npx", "npx 临时包，可安全删除", 0),
            ("\(home)/.cache/uv", "Python uv 包缓存，会自动重建", 0),
            ("\(home)/.cache/codex-runtimes", "Codex 运行时缓存，会自动重新下载", 0),
            ("\(home)/Library/pnpm/store", "pnpm 全局包存储，会自动重建", 0),
            ("\(home)/.cache/pip", "pip 下载缓存，可安全删除", 0),
            ("\(home)/.gradle/caches", "Gradle 构建缓存，会自动重建", 0),
            ("\(home)/.cargo/registry", "Rust cargo 下载缓存", 0),
        ]
        for (path, desc, _) in devTargets {
            let url = URL(fileURLWithPath: path)
            var isDir: ObjCBool = false
            guard FileManager.default.fileExists(atPath: path, isDirectory: &isDir), isDir.boolValue else { continue }
            let s = SizeCalculator.size(of: url)
            if s > 10 * 1024 * 1024 {
                add(CleanupItem(
                    url: url, size: s, category: .developerCache, risk: .safe,
                    explanation: desc, defaultSelected: true
                ))
            }
        }

        // Xcode DerivedData / iOS DeviceSupport
        for (sub, desc) in [
            ("Library/Developer/Xcode/DerivedData", "Xcode 构建产物，删除后重新编译即可"),
            ("Library/Developer/Xcode/Archives", "Xcode 归档文件，⚠️ 打包发布需要，确认后再删"),
        ] {
            let path = "\(home)/\(sub)"
            let url = URL(fileURLWithPath: path)
            guard FileManager.default.fileExists(atPath: path) else { continue }
            let s = SizeCalculator.size(of: url)
            if s > 50 * 1024 * 1024 {
                add(CleanupItem(
                    url: url, size: s, category: .developerCache,
                    risk: sub.contains("Archives") ? .caution : .safe,
                    explanation: desc,
                    defaultSelected: !sub.contains("Archives")
                ))
            }
        }

        // ---------- 5. 废纸篓 ----------
        tick("检查废纸篓…")
        let trashPath = "\(home)/.Trash"
        let trashSize = SizeCalculator.size(of: URL(fileURLWithPath: trashPath))
        if trashSize > 0 {
            add(CleanupItem(
                url: URL(fileURLWithPath: trashPath), size: trashSize,
                category: .trash, risk: .safe,
                explanation: "废纸篓中的内容，清空后无法恢复",
                defaultSelected: false
            ))
        }

        // ---------- 6. 下载残留（旧安装包） ----------
        tick("扫描下载目录…")
        await scanDownloads { add($0) }

        // ---------- 7. 系统临时文件 ----------
        tick("扫描临时文件…")
        scanTempFiles { add($0) }

        if deepScan {
            // ---------- 8. 应用支持（大块头，谨慎） ----------
            tick("扫描应用支持数据…")
            await scanAppSupport { add($0) }

            // ---------- 9. 大文件 ----------
            tick("搜索大文件…")
            await findLargeFiles { add($0) }
        }

        _ = home
        return out
    }

    // MARK: - 辅助扫描函数

    private nonisolated static func scanChildren(
        of path: String,
        category: CleanupCategory,
        minSize: Int64,
        risk: RiskLevel,
        explanation: String,
        emit: @escaping (CleanupItem) -> Void
    ) async {
        let url = URL(fileURLWithPath: path)
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: path, isDirectory: &isDir), isDir.boolValue else { return }

        for (child, size) in SizeCalculator.children(of: url, minSize: minSize) {
            let item = CleanupItem(
                url: child, size: size, category: category, risk: risk,
                explanation: explanation, defaultSelected: risk == .safe
            )
            emit(item)
            await Task.yield()
        }
    }

    private nonisolated static func scanDownloads(emit: @escaping (CleanupItem) -> Void) async {
        let dl = URL(fileURLWithPath: NSHomeDirectory() + "/Downloads")
        guard let entries = try? FileManager.default.contentsOfDirectory(
            at: dl, includingPropertiesForKeys: [.isDirectoryKey, .contentModificationDateKey], options: []
        ) else { return }

        let installerExts: Set<String> = ["dmg", "pkg", "iso", "mpkg"]
        let cutoff = Date().addingTimeInterval(-30 * 24 * 3600)   // 30 天前

        for e in entries {
            let ext = e.pathExtension.lowercased()
            guard let v = try? e.resourceValues(forKeys: [.isDirectoryKey, .contentModificationDateKey]) else { continue }
            guard v.isDirectory != true else { continue }

            let modified = v.contentModificationDate ?? Date()
            let size = SizeCalculator.fileSize(e)

            // 只收安装包类，且超过 30 天未修改
            if installerExts.contains(ext) && modified < cutoff && size > 1024 * 1024 {
                emit(CleanupItem(
                    url: e, size: size, category: .downloadsOld, risk: .caution,
                    explanation: "已下载 \(Int(-modified.timeIntervalSinceNow / 86400)) 天的安装包，软件通常已安装完成",
                    defaultSelected: false, modified: modified
                ))
            }
            await Task.yield()
        }
    }

    private nonisolated static func scanTempFiles(emit: @escaping (CleanupItem) -> Void) {
        // 用户级 temp 目录
        let tmp = URL(fileURLWithPath: NSTemporaryDirectory())
        guard let entries = try? FileManager.default.contentsOfDirectory(
            at: tmp, includingPropertiesForKeys: [.isDirectoryKey, .contentModificationDateKey], options: []
        ) else { return }

        let cutoff = Date().addingTimeInterval(-7 * 24 * 3600)
        for e in entries {
            guard let v = try? e.resourceValues(forKeys: [.contentModificationDateKey, .isDirectoryKey]) else { continue }
            let modified = v.contentModificationDate ?? Date()
            guard modified < cutoff else { continue }
            let s = SizeCalculator.size(of: e)
            guard s > 10 * 1024 * 1024 else { continue }
            emit(CleanupItem(
                url: e, size: s, category: .tempFiles, risk: .safe,
                explanation: "7 天前的临时文件。常见于应用更新残留（如 ShipIt）。",
                defaultSelected: true, modified: modified
            ))
        }
    }

    private nonisolated static func scanAppSupport(emit: @escaping (CleanupItem) -> Void) async {
        let path = NSHomeDirectory() + "/Library/Application Support"
        let url = URL(fileURLWithPath: path)
        guard let entries = try? FileManager.default.contentsOfDirectory(
            at: url, includingPropertiesForKeys: [.isDirectoryKey], options: []
        ) else { return }

        for e in entries {
            let s = SizeCalculator.size(of: e)
            guard s > 500 * 1024 * 1024 else { continue }   // 只报 >500MB 的
            emit(CleanupItem(
                url: e, size: s, category: .appSupport, risk: .dangerous,
                explanation: "应用数据目录。内含登录状态、配置、本地数据库。删除会导致该应用重置，请勿轻易删除。",
                defaultSelected: false
            ))
            await Task.yield()
        }
    }

    private nonisolated static func findLargeFiles(emit: @escaping (CleanupItem) -> Void) async {
        let home = NSHomeDirectory()
        // 只扫常见的大文件聚集地，避免全盘遍历过慢
        let roots = ["\(home)/Downloads", "\(home)/Movies", "\(home)/Documents", "\(home)/Desktop"]
        let threshold: Int64 = 500 * 1024 * 1024

        for root in roots {
            let rootURL = URL(fileURLWithPath: root)
            guard let en = FileManager.default.enumerator(
                at: rootURL,
                includingPropertiesForKeys: [.fileSizeKey, .totalFileAllocatedSizeKey, .isRegularFileKey],
                options: [.skipsHiddenFiles, .skipsPackageDescendants],
                errorHandler: { _, _ in true }
            ) else { continue }

            // 先同步枚举完，再逐条 emit —— 枚举器不能在 await 之间跨步
            var batch: [CleanupItem] = []
            en.forEach { element in
                guard let f = element as? URL,
                      let v = try? f.resourceValues(forKeys: [.isRegularFileKey, .totalFileAllocatedSizeKey]),
                      v.isRegularFile == true else { return }
                let s = Int64(v.totalFileAllocatedSize ?? 0)
                if s >= threshold {
                    batch.append(CleanupItem(
                        url: f, size: s, category: .largeFiles, risk: .dangerous,
                        explanation: "大文件（\(Fmt.size(s))）。可能是重要资料，请确认后再决定。",
                        defaultSelected: false
                    ))
                }
            }
            for item in batch {
                emit(item)
                await Task.yield()
            }
        }
    }
}
