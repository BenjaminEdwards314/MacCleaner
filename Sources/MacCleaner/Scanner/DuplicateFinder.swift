import Foundation
import CryptoKit

/// 重复文件查找引擎。
///
/// ## 三阶段筛选
///
/// 全盘哈希代价极高（实测 30 GB 目录完整 SHA256 需要分钟级），
/// 所以按「代价从低到高」逐层淘汰：
///
/// 1. **按体积分组** —— 只读 `resourceValues`，代价几乎为零。
///    体积唯一的文件（占绝大多数）在这里就被排除，不进后续阶段。
/// 2. **头部指纹** —— 只读前 4 KB 做 SHA256。同体积但内容不同的文件
///    （如两个 0 字节或同尺寸的不同图片）在这里被淘汰。
/// 3. **完整哈希** —— 只有前两阶段都相同的文件才做整文件 SHA256。
///
/// 这样实际做完整哈希的文件数通常只有总数的极小一部分。
///
/// ## 为什么不只看文件名或体积
///
/// 体积相同不等于内容相同。只按体积判定会产生大量误报，
/// 而误报的后果是**用户删掉不该删的文件**。所以必须落到内容哈希。
@MainActor
final class DuplicateFinder: ObservableObject {

    /// 一组内容完全相同的文件
    struct DuplicateGroup: Identifiable {
        let id = UUID()
        /// 完整哈希，作为组的稳定标识
        let hash: String
        let size: Int64          // 单个文件的体积
        var files: [FileEntry]

        /// 该组总占用
        var totalSize: Int64 { size * Int64(files.count) }
        /// 删掉冗余副本后能释放的体积（保留一份）
        var reclaimable: Int64 { size * Int64(max(0, files.count - 1)) }
    }

    struct FileEntry: Identifiable, Hashable {
        let id = UUID()
        let url: URL
        let size: Int64
        let modified: Date
        /// 是否被用户勾选为「要删除」
        var isSelected: Bool = false

        var name: String { url.lastPathComponent }
        var path: String { url.path }
        /// 所在目录，界面上比完整路径更好读
        var parentPath: String { url.deletingLastPathComponent().path }
    }

    /// 每组保留哪一份
    enum KeepPolicy: String, CaseIterable, Identifiable {
        case oldest, newest, shortestPath
        var id: String { rawValue }
        var title: String {
            switch self {
            case .oldest: return "保留最早"
            case .newest: return "保留最新"
            case .shortestPath: return "保留路径最短"
            }
        }
    }

    @Published private(set) var isScanning = false
    @Published private(set) var progressText = ""
    @Published private(set) var progressValue: Double = 0
    @Published private(set) var groups: [DuplicateGroup] = []
    @Published var hasScanned = false
    @Published private(set) var errorText: String?

    /// 扫描这些根目录。默认下载 + 文档 + 桌面。
    @Published var roots: [URL] = DuplicateFinder.defaultRoots

    private var task: Task<Void, Never>?

    static var defaultRoots: [URL] {
        let home = NSHomeDirectory()
        return ["Downloads", "Documents", "Desktop"].map {
            URL(fileURLWithPath: "\(home)/\($0)")
        }
    }

    /// 可用于增加扫描范围的可选目录
    static var optionalRoots: [URL] {
        let home = NSHomeDirectory()
        return ["Pictures", "Movies", "Music"].map {
            URL(fileURLWithPath: "\(home)/\($0)")
        }
    }

    func cancel() {
        task?.cancel()
        isScanning = false
    }

    /// 小于此体积的文件不参与比对。
    /// 1 MB 以下重复的往往是系统文件或配置文件，删了收益低、风险高。
    nonisolated static let minimumSize: Int64 = 1024 * 1024

    func startScan() {
        guard !isScanning else { return }
        isScanning = true
        hasScanned = false
        progressValue = 0
        groups = []
        errorText = nil

        let scanRoots = roots

        task = Task.detached(priority: .userInitiated) { [weak self] in
            guard let self else { return }
            let found = await Self.performScan(roots: scanRoots) { text, pct in
                Task { @MainActor in
                    self.progressText = text
                    self.progressValue = pct
                }
            }
            await MainActor.run {
                self.groups = found
                self.isScanning = false
                self.hasScanned = true
                self.progressText = ""
                self.progressValue = 1
            }
        }
    }

    // MARK: - 扫描实现

    private nonisolated static func performScan(
        roots: [URL],
        report: @escaping (String, Double) -> Void
    ) async -> [DuplicateGroup] {

        // ---------- 阶段 1：收集文件并按体积分组 ----------
        report("正在收集文件…", 0.02)

        var bySize: [Int64: [FileEntry]] = [:]
        // 记录已见过的 inode，用于识别硬链接 —— 同一份数据被多个路径指向时
        // 不能算作「重复」，否则用户会以为有两份而删掉其中「一份」，
        // 实际上删哪个都指向同一份数据。
        var seenInodes = Set<String>()
        var scannedCount = 0

        for (idx, root) in roots.enumerated() {
            if Task.isCancelled { return [] }
            report("正在收集文件… \(root.lastPathComponent)", 0.02 + 0.28 * Double(idx) / Double(max(roots.count, 1)))

            collectFiles(at: root, into: &bySize, seenInodes: &seenInodes, scannedCount: &scannedCount)
        }

        // 只保留出现两次以上的体积组
        let candidates = bySize.filter { $0.value.count > 1 }
        let candidateFiles = candidates.values.reduce(0) { $0 + $1.count }

        if candidateFiles == 0 {
            report("未发现重复文件", 1.0)
            return []
        }

        // ---------- 阶段 2：头部指纹 ----------
        report("正在比对文件指纹…", 0.32)

        var byHead: [String: [FileEntry]] = [:]
        var processed = 0
        let headTotal = Double(candidateFiles)

        for (_, entries) in candidates {
            for entry in entries {
                if Task.isCancelled { return [] }
                processed += 1

                guard let head = headHash(of: entry.url) else { continue }
                // 头部相同还不够，必须体积也相同（同体积已在组内，这里用 size 拼 key）
                let key = "\(entry.size)-\(head)"
                byHead[key, default: []].append(entry)

                if processed % 50 == 0 {
                    report("正在比对文件指纹… \(processed)/\(candidateFiles)",
                           0.32 + 0.28 * Double(processed) / headTotal)
                }
            }
        }

        let headCandidates = byHead.filter { $0.value.count > 1 }
        let toFullHash = headCandidates.values.reduce(0) { $0 + $1.count }

        if toFullHash == 0 {
            report("未发现重复文件", 1.0)
            return []
        }

        // ---------- 阶段 3：完整哈希 ----------
        report("正在计算完整哈希…", 0.62)

        var byFull: [String: [FileEntry]] = [:]
        var hashed = 0
        let hashTotal = Double(toFullHash)

        for (_, entries) in headCandidates {
            for entry in entries {
                if Task.isCancelled { return [] }
                hashed += 1

                guard let full = fullHash(of: entry.url) else { continue }
                byFull[full, default: []].append(entry)

                if hashed % 10 == 0 {
                    report("正在计算完整哈希… \(hashed)/\(toFullHash)",
                           0.62 + 0.36 * Double(hashed) / hashTotal)
                }
            }
        }

        // ---------- 组装结果 ----------
        var result: [DuplicateGroup] = []
        for (hash, entries) in byFull where entries.count > 1 {
            guard let size = entries.first?.size else { continue }
            result.append(DuplicateGroup(
                hash: hash,
                size: size,
                files: entries.sorted { $0.modified < $1.modified }
            ))
        }

        // 按「可回收体积」降序 —— 用户最关心能省多少
        result.sort { $0.reclaimable > $1.reclaimable }

        report("扫描完成，发现 \(result.count) 组重复", 1.0)
        return result
    }

    /// 递归收集文件。跳过符号链接（会被解析成别处的文件，导致误判重复），
    /// 并用 inode 去重硬链接。
    private nonisolated static func collectFiles(
        at root: URL,
        into bySize: inout [Int64: [FileEntry]],
        seenInodes: inout Set<String>,
        scannedCount: inout Int
    ) {
        let fm = FileManager.default
        var isDir: ObjCBool = false
        guard fm.fileExists(atPath: root.path, isDirectory: &isDir), isDir.boolValue else { return }

        let keys: Set<URLResourceKey> = [
            .isRegularFileKey, .isDirectoryKey, .isSymbolicLinkKey,
            .fileSizeKey, .totalFileAllocatedSizeKey, .contentModificationDateKey,
            .fileResourceIdentifierKey
        ]

        guard let en = fm.enumerator(
            at: root,
            includingPropertiesForKeys: Array(keys),
            options: [],                        // 不跳过隐藏文件
            errorHandler: { _, _ in true }      // 无权限目录跳过，不中断
        ) else { return }

        for case let url as URL in en {
            if Task.isCancelled { return }
            guard let v = try? url.resourceValues(forKeys: keys) else { continue }

            // 符号链接本身不参与比对
            if v.isSymbolicLink == true {
                if v.isDirectory == true { en.skipDescendants() }
                continue
            }

            guard v.isRegularFile == true else { continue }

            let size = Int64(v.fileSize ?? 0)
            // 太小的文件不参与
            guard size >= minimumSize else { continue }

            scannedCount += 1

            // 硬链接去重：fileResourceIdentifier 对硬链接返回相同的值。
            // 用「inode 标识 + 体积」作为键，避免把同一份数据当成两份。
            if let rid = v.fileResourceIdentifier {
                let key = "\(String(describing: rid))-\(size)"
                if seenInodes.contains(key) { continue }
                seenInodes.insert(key)
            }

            let entry = FileEntry(
                url: url,
                size: size,
                modified: v.contentModificationDate ?? .distantPast
            )
            bySize[size, default: []].append(entry)
        }
    }

    /// 前 4 KB 的 SHA256。读不到（权限/损坏）时返回 nil，该文件被跳过。
    private nonisolated static func headHash(of url: URL) -> String? {
        guard let fh = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? fh.close() }
        // read(upToCount:) 在 macOS 10.15.4+ 可用
        guard let data = try? fh.read(upToCount: 4096), !data.isEmpty else { return nil }
        return SHA256.hash(data: data).compactMap { String(format: "%02x", $0) }.joined()
    }

    /// 整文件流式 SHA256。用分块读取，避免把大文件整个载入内存。
    private nonisolated static func fullHash(of url: URL) -> String? {
        guard let fh = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? fh.close() }

        var hasher = SHA256()
        let chunkSize = 1 << 20   // 1 MB
        while true {
            guard let chunk = try? fh.read(upToCount: chunkSize), !chunk.isEmpty else { break }
            hasher.update(data: chunk)
        }
        return hasher.finalize().compactMap { String(format: "%02x", $0) }.joined()
    }

    // MARK: - 选择辅助

    /// 按策略给每组勾选「要删除的副本」，每组保留一份。
    ///
    /// 这是重复文件清理里唯一会批量勾选的地方，所以规则必须显式且可预期：
    /// 保留一份，其余全部标记为删除。
    func selectDuplicates(keeping policy: KeepPolicy) {
        for gi in groups.indices {
            let files = groups[gi].files
            guard files.count > 1 else { continue }

            let keepIndex: Int
            switch policy {
            case .oldest:
                keepIndex = files.indices.min { files[$0].modified < files[$1].modified } ?? 0
            case .newest:
                keepIndex = files.indices.max { files[$0].modified < files[$1].modified } ?? 0
            case .shortestPath:
                keepIndex = files.indices.min {
                    (files[$0].path.count, files[$0].path) < (files[$1].path.count, files[$1].path)
                } ?? 0
            }

            for fi in groups[gi].files.indices {
                groups[gi].files[fi].isSelected = (fi != keepIndex)
            }
        }
    }

    func clearSelection() {
        for gi in groups.indices {
            for fi in groups[gi].files.indices {
                groups[gi].files[fi].isSelected = false
            }
        }
    }

    func toggle(groupIndex gi: Int, fileIndex fi: Int) {
        guard groups.indices.contains(gi),
              groups[gi].files.indices.contains(fi) else { return }
        groups[gi].files[fi].isSelected.toggle()
    }

    /// 当前勾选的项目总数与可释放体积
    var selectedCount: Int {
        groups.reduce(0) { acc, g in acc + g.files.filter(\.isSelected).count }
    }

    var selectedSize: Int64 {
        groups.reduce(0) { acc, g in
            acc + g.files.filter(\.isSelected).reduce(0) { $0 + $1.size }
        }
    }

    /// 把勾选项转成统一的 CleanupItem，复用现有的清理引擎与安全护栏。
    ///
    /// 注意 category 用 `.duplicates`，风险等级为 `.caution` ——
    /// 「重复」是内容层面的判断，用户仍可能想保留不同位置的副本
    /// （例如同一份合同存在两个项目目录里）。所以不当作 safe。
    func selectedItems() -> [CleanupItem] {
        var out: [CleanupItem] = []
        for g in groups {
            for f in g.files where f.isSelected {
                out.append(CleanupItem(
                    url: f.url,
                    size: f.size,
                    category: .duplicates,
                    risk: .caution,
                    explanation: "与其他 \(g.files.count - 1) 个文件内容完全相同（SHA256 一致）",
                    defaultSelected: false,
                    isSelected: true,
                    modified: f.modified
                ))
            }
        }
        return out
    }
}
