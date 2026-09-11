import Foundation

/// 内存压力等级。
///
/// 取值直接对齐内核的 `kern.memorystatus_vm_pressure_level`：
/// 1 = normal，2 = warn，4 = critical。
/// 读不到该 sysctl 时（沙箱 / 未来版本改名）回落到按可用比例自行推定。
enum MemoryPressureLevel: Int {
    case normal = 1
    case warning = 2
    case critical = 4

    var label: String {
        switch self {
        case .normal: return "正常"
        case .warning: return "偏高"
        case .critical: return "紧张"
        }
    }

    var symbol: String {
        switch self {
        case .normal: return "checkmark.circle.fill"
        case .warning: return "exclamationmark.triangle.fill"
        case .critical: return "exclamationmark.octagon.fill"
        }
    }

    /// 由可用比例推定等级，仅在读不到内核 sysctl 时使用。
    /// 阈值取自 Apple 对内存压力的一贯口径：可用低于 10% 视为紧张。
    static func infer(freeFraction: Double) -> MemoryPressureLevel {
        if freeFraction < 0.10 { return .critical }
        if freeFraction < 0.25 { return .warning }
        return .normal
    }
}

/// 一次内存采样。
///
/// 数据来源是 `vm_stat` 的 Mach VM 统计。这里刻意**不用** `host_statistics64`
/// 的 C 接口：那需要在 Swift 里手工搭 `mach_host_self()` 与 `vm_statistics64_data_t`
/// 的桥接，而 `vm_stat` 的输出格式自 OS X 时代起就稳定，解析它更省事也更好调试。
/// 唯一的代价是要处理单位 —— 所有数字都是**页数**，必须先乘以页大小。
struct MemoryStats {

    /// 物理内存总量（字节）
    var total: Int64 = 0
    /// App 内存：anonymous + 已压缩，等价于「活动」类的占用
    var app: Int64 = 0
    /// 联动内存（wired）：内核与不可换出的内存，任何情况下都不能被回收
    var wired: Int64 = 0
    /// 已压缩内存：被压缩器占用的物理内存
    var compressed: Int64 = 0
    /// 缓存文件：file-backed 页，系统会在需要时自动回收
    var cachedFiles: Int64 = 0
    /// 交换文件使用量
    var swapUsed: Int64 = 0
    /// 交换文件总量
    var swapTotal: Int64 = 0

    var pressure: MemoryPressureLevel = .normal

    /// 采样时间，用于界面显示「刚刚更新」
    var sampledAt: Date = Date()

    /// 可直接使用的内存。
    ///
    /// 这里把 free + inactive + speculative + purgeable 都算进来：
    /// inactive 页是可被立即回收的干净页，purgeable 是系统标记为「可丢弃」的，
    /// 它们对用户而言等价于可用。只统计 `Pages free` 会严重低估 ——
    /// macOS 会主动把空闲内存用作缓存，free 常年很低是正常现象。
    var available: Int64 = 0

    /// 已用 = 总量 - 可用
    var used: Int64 { max(0, total - available) }

    var usedFraction: Double { total > 0 ? Double(used) / Double(total) : 0 }
    var availableFraction: Double { total > 0 ? Double(available) / Double(total) : 0 }

    /// 压缩率：压缩后占用 / 压缩前内容。
    /// 越接近 1 说明压缩收益越低，内存压力越大。
    var compressionRatio: Double {
        compressed > 0 ? Double(compressedBeforeCompression) / Double(compressed) : 1
    }
    /// 压缩前的原始大小（由 `Pages stored in compressor` 换算）
    var compressedBeforeCompression: Int64 = 0

    /// 是否有交换在使用
    var isSwapping: Bool { swapUsed > 0 }

    /// 一个所有字段为零的空样本，用于首次渲染时占位
    static let empty = MemoryStats()
}
