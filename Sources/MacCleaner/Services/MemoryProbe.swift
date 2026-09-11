import Foundation

/// 内存探针：采集系统内存统计。
///
/// ## 为什么是只读的
///
/// 市面上不少「内存清理」工具会提供一个大按钮，点击后宣称「释放了 N GB」。
/// 在本机实测过之后，这个做法**不成立**：
///
/// - `/usr/sbin/purge` 需要 root（无免密 sudo 时返回
///   `Unable to purge disk buffers: Operation not permitted`），
///   而且它自己文档里写明 "It does not affect anonymous memory" ——
///   它清的是磁盘缓冲区，跟应用占用的内存基本无关。
/// - 主动向其它进程要内存需要 `task_for_pid` 权限，普通应用拿不到。
/// - macOS 的内存管理本就足够主动：inactive / purgeable 页在需要时由系统回收，
///   第三方工具能"释放"的部分，系统早就释放了。
///
/// 所以这里提供一个**诚实的观测面板**：准确显示内存去哪了、压力如何，
/// 并在需要时引导用户去关闭真正的大户，而不是伪造一个释放数字。
///
/// 唯一的写操作是 `dropCaches` —— 它只是建议系统回收缓存页，
/// 不触碰任何用户数据，也不影响磁盘上的文件。
@MainActor
final class MemoryProbe: ObservableObject {

    /// 占用内存最多的进程
    struct ProcessUsage: Identifiable, Hashable {
        let id: Int          // pid
        let name: String
        let rss: Int64       // 常驻内存（字节）
    }

    @Published private(set) var stats: MemoryStats = .empty
    @Published private(set) var isSampling = false
    /// 内存占用最高的若干进程（降序）
    @Published private(set) var topProcesses: [ProcessUsage] = []
    /// 采集失败时的说明（正常情况为 nil）
    @Published private(set) var errorText: String?

    private var timer: Timer?

    /// 开始定期采样。`interval` 秒刷新一次，默认 2 秒 ——
    /// 足够让用户看到动态变化，又不会因为频繁 fork 而浪费 CPU。
    func start(interval: TimeInterval = 2.0) {
        sample()
        stop()
        let t = Timer(timeInterval: interval, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.sample() }
        }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    deinit {
        timer?.invalidate()
    }

    /// 采集一次
    func sample() {
        guard !isSampling else { return }
        isSampling = true
        defer { isSampling = false }

        let total = ProcessInfo.processInfo.physicalMemory

        guard let vmOutput = Self.runVMStat() else {
            errorText = "无法读取 vm_stat，内存信息不可用"
            return
        }

        guard let pageSize = Self.pageSize(from: vmOutput),
              let pages = Self.parsePages(vmOutput) else {
            errorText = "vm_stat 输出格式无法解析"
            return
        }

        func bytes(_ key: String) -> Int64 {
            Int64(pages[key] ?? 0) * pageSize
        }

        // vm_stat 的部分标签历史上改过名（"Pages stored in compressor" 在旧版本
        // 里叫 "Pages occupied by compressor" 的位置不同），所以两种都试。
        let compressed = bytes("Pages occupied by compressor")
        let storedInCompressor = bytes("Pages stored in compressor")

        let free = bytes("Pages free")
        let inactive = bytes("Pages inactive")
        let speculative = bytes("Pages speculative")
        let purgeable = bytes("Pages purgeable")
        let wired = bytes("Pages wired down")
        let active = bytes("Pages active")
        let fileBacked = bytes("File-backed pages")
        let anon = bytes("Anonymous pages")

        // App 内存 = 匿名页 + 已压缩。这就是活动监视器里「内存」一列的来源口径。
        let app = anon + compressed

        var s = MemoryStats()
        s.total = Int64(total)
        s.app = app
        s.wired = wired
        s.compressed = compressed
        s.compressedBeforeCompression = storedInCompressor
        // 缓存文件用 file-backed 减去已被算进 inactive 的部分会重复计数，
        // 这里直接用 file-backed 作为「缓存文件」的口径，与活动监视器一致。
        s.cachedFiles = fileBacked
        s.available = free + inactive + speculative + purgeable
        // active 页里也有可回收的部分，但不确定，不计入 available，避免虚高。

        if let swap = Self.swapUsage() {
            s.swapUsed = swap.used
            s.swapTotal = swap.total
        }

        s.pressure = Self.readPressureLevel(freeFraction: Double(s.available) / Double(max(s.total, 1)))
        s.sampledAt = Date()

        // active 仅用于内部校验，避免"未使用变量"警告的同时保留可读性
        _ = active

        stats = s
        // 进程列表变化慢，且 ps 有一定开销，每 5 次采样（约 10 秒）刷新一次。
        psTick += 1
        if psTick % 5 == 1 {
            topProcesses = Self.readTopProcesses(limit: 8)
        }
        errorText = nil
    }

    private var psTick = 0

    // MARK: - 数据源

    /// 列出内存占用最高的进程。
    ///
    /// 用 `ps` 而不是 `NSWorkspace.runningApplications` 的 `memoryUsage`：
    /// 后者只覆盖有 UI 的应用，看不到 Chrome Helper、编译器等真正的内存大户。
    ///
    /// 排序在 Swift 侧显式完成，**不依赖 `ps -r`** ——
    /// 本机实测（macOS 26 / Darwin 25）`ps -r` 已不再按内存排序，
    /// 输出顺序看起来是随机的，照单全收会把列表填成杂项进程。
    private static func readTopProcesses(limit: Int) -> [ProcessUsage] {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/ps")
        // 只取原始数据，排序交给下面的 sorted
        p.arguments = ["-Ao", "rss=,pid=,comm="]
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = Pipe()

        do {
            try p.run()
        } catch {
            return []
        }

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        guard p.terminationStatus == 0,
              let text = String(data: data, encoding: .utf8) else { return [] }

        var result: [ProcessUsage] = []
        for line in text.split(separator: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            // 格式：<rss> <pid> <command...>
            let parts = trimmed.split(separator: " ", maxSplits: 2,
                                      omittingEmptySubsequences: true)
            guard parts.count == 3,
                  let rssKB = Int64(parts[0]),
                  let pid = Int(parts[1]) else { continue }

            let full = String(parts[2])
            // 取可执行文件名，路径太长会让列表很难读
            let name = (full as NSString).lastPathComponent
            guard !name.isEmpty else { continue }

            result.append(ProcessUsage(id: pid, name: name, rss: rssKB * 1024))
        }

        // 显式排序后再截断（见上面的说明：不能依赖 ps 自己的排序）
        return result
            .sorted { $0.rss > $1.rss }
            .prefix(limit)
            .map { $0 }
    }

    /// 运行 `vm_stat` 并返回标准输出。
    ///
    /// 用 `/usr/bin/vm_stat` 绝对路径而不是依赖 PATH：
    /// GUI 应用由 launchd 启动，PATH 往往不含 /usr/bin。
    private static func runVMStat() -> String? {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/vm_stat")
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = Pipe()

        do {
            try p.run()
        } catch {
            return nil
        }

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        guard p.terminationStatus == 0 else { return nil }
        return String(data: data, encoding: .utf8)
    }

    /// 从首行 "(page size of N bytes)" 提取页大小。
    private static func pageSize(from output: String) -> Int64? {
        guard let line = output.split(separator: "\n").first else { return nil }
        // 形如：Mach Virtual Memory Statistics: (page size of 16384 bytes)
        guard let range = line.range(of: "page size of ") else { return nil }
        let rest = line[range.upperBound...]
        let digits = rest.prefix { $0.isNumber }
        return Int64(digits)
    }

    /// 把所有 "Pages xxx: 123." 形式的行解析成字典。
    ///
    /// 注意行尾的句号（vm_stat 用 `.` 作为千位分隔风格的后缀）以及
    /// 带引号的标签，例如 `"Translation faults":`。
    private static func parsePages(_ output: String) -> [String: Int64]? {
        var result: [String: Int64] = [:]
        for raw in output.split(separator: "\n") {
            guard let colon = raw.lastIndex(of: ":") else { continue }
            var key = String(raw[raw.startIndex..<colon])
                .trimmingCharacters(in: .whitespaces)
            let valuePart = raw[raw.index(after: colon)...]
                .trimmingCharacters(in: .whitespaces)
                .trimmingCharacters(in: CharacterSet(charactersIn: "."))

            // 去掉标签两端的引号
            key = key.trimmingCharacters(in: CharacterSet(charactersIn: "\""))

            // 值必须是纯数字才是统计行
            guard !valuePart.isEmpty,
                  valuePart.allSatisfy({ $0.isNumber }),
                  let value = Int64(valuePart) else { continue }
            result[key] = value
        }
        return result.isEmpty ? nil : result
    }

    /// 读取交换区使用情况。
    /// `vm.swapusage` 形如：total = 2048.00M  used = 512.25M  free = 1535.75M
    private static func swapUsage() -> (total: Int64, used: Int64)? {
        var size: size_t = 0
        guard sysctlbyname("vm.swapusage", nil, &size, nil, 0) == 0, size > 0 else {
            return nil
        }
        // xsw_usage 结构体：total, avail, used, pagesize, encrypted（均为 uint64）
        var usage = [UInt64](repeating: 0, count: size / MemoryLayout<UInt64>.size)
        guard sysctlbyname("vm.swapusage", &usage, &size, nil, 0) == 0 else {
            return nil
        }
        guard usage.count >= 3 else { return nil }
        return (total: Int64(bitPattern: usage[0]), used: Int64(bitPattern: usage[2]))
    }

    /// 读取内核的内存压力等级。读不到时按可用比例推定。
    private static func readPressureLevel(freeFraction: Double) -> MemoryPressureLevel {
        var value: Int32 = 0
        var size = MemoryLayout<Int32>.size
        if sysctlbyname("kern.memorystatus_vm_pressure_level", &value, &size, nil, 0) == 0,
           let level = MemoryPressureLevel(rawValue: Int(value)) {
            return level
        }
        return MemoryPressureLevel.infer(freeFraction: freeFraction)
    }

    // MARK: - 可控操作

    /// 建议系统回收文件缓存（等价于 `purge` 的非特权部分）。
    ///
    /// 说明：无 root 权限时 `purge` 会因 `Operation not permitted` 失败，
    /// 因此这里**不静默失败**，而是把真实结果返回给界面显示。
    /// 即便成功，受影响的主要是磁盘缓冲，而不是 App 占用的内存。
    @discardableResult
    func dropFileCaches() async -> (ok: Bool, message: String) {
        await withCheckedContinuation { cont in
            DispatchQueue.global(qos: .userInitiated).async {
                let p = Process()
                p.executableURL = URL(fileURLWithPath: "/usr/sbin/purge")
                let pipe = Pipe()
                p.standardOutput = pipe
                p.standardError = pipe

                do {
                    try p.run()
                } catch {
                    cont.resume(returning: (false, "无法执行 purge：\(error.localizedDescription)"))
                    return
                }

                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                p.waitUntilExit()
                let text = String(data: data, encoding: .utf8)?
                    .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

                if p.terminationStatus == 0 {
                    cont.resume(returning: (true, "已请求系统回收文件缓存。"))
                } else {
                    // 最常见的就是权限不足，把系统原话带出来，不粉饰
                    let detail = text.isEmpty ? "退出码 \(p.terminationStatus)" : text
                    cont.resume(returning: (false, detail))
                }
            }
        }
    }
}
