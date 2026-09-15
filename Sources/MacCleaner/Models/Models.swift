import Foundation

/// 风险等级：直接决定界面上能否勾选、以及删除前的确认强度
enum RiskLevel: String, Codable, CaseIterable {
    case safe        // 可安全删除，删了会自动重建
    case caution     // 需谨慎：可能影响使用体验或需要重新登录
    case dangerous   // 高危：默认禁止删除，仅可手动在 Finder 中操作

    var label: String {
        switch self {
        case .safe: return "安全"
        case .caution: return "谨慎"
        case .dangerous: return "高危"
        }
    }

    var symbol: String {
        switch self {
        case .safe: return "checkmark.shield.fill"
        case .caution: return "exclamationmark.triangle.fill"
        case .dangerous: return "xmark.octagon.fill"
        }
    }
}

/// 清理类别
enum CleanupCategory: String, Codable, CaseIterable, Identifiable {
    case userCache        // 用户缓存
    case systemCache      // 系统/浏览器缓存
    case logs             // 日志
    case trash            // 废纸篓
    case developerCache   // 开发缓存 (npm/pnpm/uv/xcode)
    case crashReports     // 崩溃报告
    case crashpad         // 崩溃转储堆积 (Crashpad pending，可能异常膨胀)
    case downloadsOld     // Downloads 中的旧安装包
    case appSupport       // 应用支持数据
    case largeFiles       // 大文件
    case tempFiles        // 临时文件
    case duplicates       // 重复文件（内容完全一致）
    case appResidue       // 应用卸载残留
    case appBundle        // 应用本体

    var id: String { rawValue }

    var title: String {
        switch self {
        case .userCache: return "用户缓存"
        case .systemCache: return "浏览器缓存"
        case .logs: return "日志文件"
        case .trash: return "废纸篓"
        case .developerCache: return "开发缓存"
        case .crashReports: return "崩溃报告"
        case .crashpad: return "崩溃转储堆积"
        case .downloadsOld: return "下载残留"
        case .appSupport: return "应用支持"
        case .largeFiles: return "大文件"
        case .tempFiles: return "临时文件"
        case .duplicates: return "重复文件"
        case .appResidue: return "应用残留"
        case .appBundle: return "应用本体"
        }
    }

    var symbol: String {
        switch self {
        case .userCache: return "internaldrive"
        case .systemCache: return "globe"
        case .logs: return "doc.text"
        case .trash: return "trash"
        case .developerCache: return "hammer"
        case .crashReports: return "exclamationmark.bubble"
        case .crashpad: return "exclamationmark.triangle"
        case .downloadsOld: return "arrow.down.circle"
        case .appSupport: return "square.stack.3d.up"
        case .largeFiles: return "doc.zipper"
        case .tempFiles: return "clock.arrow.circlepath"
        case .duplicates: return "doc.on.doc"
        case .appResidue: return "shippingbox"
        case .appBundle: return "app.dashed"
        }
    }
}

/// 一个可清理的条目（单个文件或目录）
struct CleanupItem: Identifiable, Hashable {
    let id = UUID()
    let url: URL
    let size: Int64
    let category: CleanupCategory
    let risk: RiskLevel
    /// 给用户看的说明：这是什么、删了会怎样
    let explanation: String
    /// 默认是否勾选
    let defaultSelected: Bool
    var isSelected: Bool = false
    var modified: Date?

    var name: String { url.lastPathComponent }
    var path: String { url.path }

    static func == (lhs: CleanupItem, rhs: CleanupItem) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

/// 扫描结果分组
struct CleanupGroup: Identifiable {
    let id = UUID()
    let category: CleanupCategory
    var items: [CleanupItem]

    var totalSize: Int64 { items.reduce(0) { $0 + $1.size } }
    var selectedSize: Int64 { items.filter(\.isSelected).reduce(0) { $0 + $1.size } }
    var maxRisk: RiskLevel {
        if items.contains(where: { $0.risk == .dangerous }) { return .dangerous }
        if items.contains(where: { $0.risk == .caution }) { return .caution }
        return .safe
    }
}

/// 磁盘卷信息
struct VolumeInfo {
    var total: Int64
    var free: Int64
    var used: Int64 { total - free }
    var usedFraction: Double { total > 0 ? Double(used) / Double(total) : 0 }

    /// 通过 URLResourceValues 读取，无需调用外部命令
    static func current() -> VolumeInfo {
        let url = URL(fileURLWithPath: NSHomeDirectory())
        let keys: Set<URLResourceKey> = [
            .volumeTotalCapacityKey,
            .volumeAvailableCapacityForImportantUsageKey,
            .volumeAvailableCapacityKey
        ]
        guard let v = try? url.resourceValues(forKeys: keys) else {
            return VolumeInfo(total: 0, free: 0)
        }
        let total = Int64(v.volumeTotalCapacity ?? 0)
        // ForImportantUsage 更贴近 Finder 显示的"可用"，因为它把可清除空间算进去
        let free = v.volumeAvailableCapacityForImportantUsage
            ?? Int64(v.volumeAvailableCapacity ?? 0)
        return VolumeInfo(total: total, free: free)
    }
}

/// 格式化辅助
enum Fmt {
    static let byteFormatter: ByteCountFormatter = {
        let f = ByteCountFormatter()
        f.countStyle = .file
        f.allowedUnits = [.useKB, .useMB, .useGB, .useTB]
        return f
    }()

    static func size(_ bytes: Int64) -> String {
        byteFormatter.string(fromByteCount: bytes)
    }

    static func percent(_ v: Double) -> String {
        String(format: "%.0f%%", v * 100)
    }
}
