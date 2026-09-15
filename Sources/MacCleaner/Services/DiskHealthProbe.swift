import Foundation

/// 磁盘健康信息采集。
///
/// 数据源全部是系统自带命令行工具，不引入任何依赖：
/// `diskutil info`、`diskutil apfs list`、`tmutil listlocalsnapshots`。
///
/// ## 为什么有些字段会缺失
///
/// Apple Silicon 的内置盘上，多数 SMART 细项（通电时间、写入量、坏块）
/// **不可读**，`diskutil` 只返回一个总体状态。外接 USB 盘通常连总体状态
/// 也读不到。所以这里的字段全部是可选的，界面会明确显示「不可读」
/// 而不是编造一个数值。
@MainActor
final class DiskHealthProbe: ObservableObject {

    struct VolumeInfo {
        var name: String = "—"
        var mountPoint: String = "/"
        var fileSystem: String = "—"
        var deviceNode: String = "—"
        var isSolidState: Bool?
        var isEncrypted: Bool?
        var isReadOnly: Bool?
        var smartStatus: String?
        /// 容量（来自卷本身）
        var totalBytes: Int64 = 0
        var freeBytes: Int64 = 0
        /// 所在 APFS 容器（若有）
        var containerTotal: Int64?
        var containerFree: Int64?
    }

    struct Container {
        var reference: String
        var totalBytes: Int64
        var usedBytes: Int64
        var freeBytes: Int64
        var volumeCount: Int
        var snapshotCount: Int
    }

    @Published private(set) var volume = VolumeInfo()
    @Published private(set) var containers: [Container] = []
    @Published private(set) var localSnapshots: [String] = []
    @Published private(set) var isLoading = false
    @Published private(set) var lastUpdated: Date?

    private var task: Task<Void, Never>?

    func refresh() {
        guard !isLoading else { return }
        isLoading = true

        task = Task.detached(priority: .userInitiated) { [weak self] in
            guard let self else { return }
            let v = Self.readVolume()
            let c = Self.readContainers()
            let s = Self.readSnapshots()

            await MainActor.run {
                self.volume = v
                self.containers = c
                self.localSnapshots = s
                self.isLoading = false
                self.lastUpdated = Date()
            }
        }
    }

    // MARK: - 命令执行

    /// 运行命令并返回标准输出。失败返回 nil（不抛错 —— 健康信息缺失是常态）。
    private nonisolated static func run(_ launchPath: String, _ args: [String]) -> String? {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: launchPath)
        p.arguments = args

        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = Pipe()   // 丢弃 stderr，避免污染

        do { try p.run() } catch { return nil }

        // 必须在 waitUntilExit 之前读完，否则管道缓冲区满会死锁
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()

        guard p.terminationStatus == 0 else { return nil }
        return String(data: data, encoding: .utf8)
    }

    /// 从 `diskutil info` 的输出里取字段值。
    /// 输出格式为 `   Key:   Value`，键名长度不一，所以按第一个冒号切分。
    private nonisolated static func field(_ output: String, _ key: String) -> String? {
        for line in output.split(separator: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard trimmed.hasPrefix(key + ":") else { continue }
            let value = trimmed.dropFirst(key.count + 1).trimmingCharacters(in: .whitespaces)
            return value.isEmpty ? nil : value
        }
        return nil
    }

    /// 从形如 `245.1 GB (245107195904 Bytes)` 的字符串里取出括号内的字节数。
    private nonisolated static func bytes(_ value: String?) -> Int64? {
        guard let value else { return nil }
        // 优先取括号内的精确字节数
        if let open = value.firstIndex(of: "("),
           let close = value.range(of: " Bytes", range: open..<value.endIndex)?.lowerBound,
           open < close {
            let inner = value[value.index(after: open)..<close]
            if let n = Int64(inner.trimmingCharacters(in: .whitespaces)) { return n }
        }
        // 兜底：取开头连续的数字
        let digits = value.drop(while: { !$0.isNumber }).prefix(while: { $0.isNumber })
        return Int64(digits)
    }

    private nonisolated static func bool(_ value: String?) -> Bool? {
        guard let value else { return nil }
        if value.hasPrefix("Yes") { return true }
        if value.hasPrefix("No") { return false }
        return nil
    }

    // MARK: - 各项读取

    private nonisolated static func readVolume() -> VolumeInfo {
        var v = VolumeInfo()
        guard let out = run("/usr/sbin/diskutil", ["info", "/"]) else { return v }

        v.name = field(out, "Volume Name") ?? "—"
        v.mountPoint = field(out, "Mount Point") ?? "/"
        v.fileSystem = field(out, "File System Personality") ?? "—"
        v.deviceNode = field(out, "Device Node") ?? "—"
        v.isSolidState = bool(field(out, "Solid State"))
        v.isEncrypted = bool(field(out, "Encrypted"))
        v.isReadOnly = bool(field(out, "Volume Read-Only"))
        v.smartStatus = field(out, "SMART Status")

        // 优先用卷容量；APFS 上卷容量可能是共享的，退回容器容量
        if let t = bytes(field(out, "Container Total Space")) { v.totalBytes = t }
        if let f = bytes(field(out, "Container Free Space")) { v.freeBytes = f }
        if v.totalBytes == 0, let t = bytes(field(out, "Total Size")) { v.totalBytes = t }
        if v.freeBytes == 0, let f = bytes(field(out, "Free Space")) { v.freeBytes = f }

        v.containerTotal = bytes(field(out, "Container Total Space"))
        v.containerFree = bytes(field(out, "Container Free Space"))
        return v
    }

    private nonisolated static func readContainers() -> [Container] {
        guard let out = run("/usr/sbin/diskutil", ["apfs", "list"]) else { return [] }

        var result: [Container] = []
        var current: Container?

        for line in out.split(separator: "\n") {
            let t = line.trimmingCharacters(in: .whitespaces)

            if t.hasPrefix("APFS Container Reference:") {
                if let c = current { result.append(c) }
                let ref = t.dropFirst("APFS Container Reference:".count).trimmingCharacters(in: .whitespaces)
                current = Container(reference: ref, totalBytes: 0, usedBytes: 0,
                                    freeBytes: 0, volumeCount: 0, snapshotCount: 0)
                continue
            }

            guard current != nil else { continue }

            if t.hasPrefix("Size (Capacity Ceiling):") {
                current?.totalBytes = bytes(String(t.dropFirst("Size (Capacity Ceiling):".count))) ?? 0
            } else if t.hasPrefix("Capacity In Use By Volumes:") {
                current?.usedBytes = bytes(String(t.dropFirst("Capacity In Use By Volumes:".count))) ?? 0
            } else if t.hasPrefix("Capacity Not Allocated:") {
                current?.freeBytes = bytes(String(t.dropFirst("Capacity Not Allocated:".count))) ?? 0
            } else if t.hasPrefix("Snapshot:") {
                current?.snapshotCount += 1
            } else if t.hasPrefix("+--") || t.contains("APFS Volume Disk") {
                current?.volumeCount += 1
            }
        }
        if let c = current { result.append(c) }
        return result
    }

    private nonisolated static func readSnapshots() -> [String] {
        guard let out = run("/usr/bin/tmutil", ["listlocalsnapshots", "/"]) else { return [] }
        return out.split(separator: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { $0.hasPrefix("com.apple.TimeMachine") }
    }
}
