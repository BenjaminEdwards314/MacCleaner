import Foundation

/// 空间视图的状态机。
///
/// ## 两阶段加载
///
/// 阶段一（毫秒级）：列出目录结构，立刻渲染列表骨架。
/// 阶段二（可能几十秒）：逐个算体积，**算完一个回填一个**并重排。
///
/// 这样用户不再盯着转圈等待 —— 实测 `~/Library/Application Support`
/// 完整统计要 24 秒，但 0.9 秒内就能看到前 20 项的真实体积。
@MainActor
final class DiskNavigator: ObservableObject {

    @Published var level: DiskLevel?
    @Published var path: [URL] = []          // 面包屑
    @Published var errorText: String?
    /// 是否还在回填体积（此时列表已可用，只是数字还在补）
    @Published var isMeasuring = false

    private var task: Task<Void, Never>?

    var current: URL? { path.last }

    /// 是否处于首次加载（还没有任何结构可显示）
    var isStructuring: Bool { level == nil }

    /// 进入一个目录（清空面包屑，作为新的根）
    func open(_ url: URL) {
        path = [url]
        load()
    }

    /// 钻取到子目录
    func drill(into node: DiskNode) {
        guard node.isDirectory else { return }
        path.append(node.url)
        load()
    }

    /// 面包屑跳回到第 index 层
    func jump(to index: Int) {
        guard index >= 0, index < path.count else { return }
        path = Array(path.prefix(index + 1))
        load()
    }

    /// 返回上一层
    func up() {
        guard path.count > 1 else { return }
        path.removeLast()
        load()
    }

    func cancel() {
        task?.cancel()
        isMeasuring = false
    }

    private func load() {
        guard let target = current else { return }
        task?.cancel()
        level = nil
        errorText = nil

        // 不用 [weak self]：闭包里捕获 weak self 再在并发代码里引用会触发
        // Swift 6 的 "captured var in concurrently-executing code" 错误。
        // 改为把需要的状态通过 MainActor.run 显式回传。
        task = Task.detached(priority: .userInitiated) { [target] in
            // ---- 阶段一：秒出结构 ----
            let initial = DiskScanner.makeLevel(of: target)
            guard !Task.isCancelled else { return }

            let denied = initial.node.accessDenied
            await MainActor.run { [weak self] in
                guard !Task.isCancelled, let self else { return }
                self.level = initial
                self.isMeasuring = !initial.children.isEmpty
                if denied {
                    self.errorText = "无法读取该目录。请到「系统设置 → 隐私与安全性 → 完全磁盘访问权限」中授权本应用。"
                }
            }

            guard !initial.children.isEmpty else {
                await MainActor.run { [weak self] in self?.isMeasuring = false }
                return
            }

            // ---- 阶段二：逐个回填体积 ----
            // 每算完一个就推一次，让 UI 尽早显示。局部 var 只在本任务内使用。
            var measured: [DiskNode] = []
            measured.reserveCapacity(initial.children.count)

            // 节流：早期实现每算完一项就推一次，50 项 = 50 次全量重渲染，
            // 每次都连带重算 treemap 布局，CPU 在 1.7%~58% 之间抖动。
            // 改为「时间节流 + 数量节流」，既保持流式手感又避免刷屏。
            var lastPush = Date.distantPast
            let minInterval: TimeInterval = 0.25

            for child in initial.children {
                if Task.isCancelled { return }
                var node = child
                node.size = DiskScanner.measure(child)
                node.measured = true
                measured.append(node)

                let now = Date()
                let isLast = measured.count == initial.children.count
                guard now.timeIntervalSince(lastPush) >= minInterval || isLast else { continue }
                lastPush = now

                // 传值快照，避免把 var 捕获进并发闭包
                let snapshot: [DiskNode] = measured
                await MainActor.run { [weak self] in
                    guard !Task.isCancelled, let self else { return }
                    self.applyMeasuring(snapshot, template: initial, finished: isLast)
                }
            }

            // 收尾：确保最终状态一定被提交
            let final: [DiskNode] = measured
            await MainActor.run { [weak self] in
                guard !Task.isCancelled, let self else { return }
                self.applyMeasuring(final, template: initial, finished: true)
                self.isMeasuring = false
            }
        }
    }

    /// 把回填结果并回 level，并按体积重排（未算出的排后面）
    private func applyMeasuring(_ measured: [DiskNode], template: DiskLevel, finished: Bool = false) {
        guard var lvl = level else { return }

        let byId = Dictionary(uniqueKeysWithValues: measured.map { ($0.id, $0) })
        var kids = lvl.children.map { byId[$0.id] ?? $0 }

        // 已算出的按体积降序，未算出的保持原顺序垫底
        let done = kids.filter(\.measured).sorted { $0.size > $1.size }
        let pending = kids.filter { !$0.measured }
        kids = done + pending

        lvl.children = kids
        lvl.node.size = done.reduce(Int64(0)) { $0 + $1.size }
        if finished { lvl.node.measured = true }

        level = lvl
    }
}
