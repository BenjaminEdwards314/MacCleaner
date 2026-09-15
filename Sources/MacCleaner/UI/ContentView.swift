import SwiftUI

@main
struct MacCleanerApp: App {
    var body: some Scene {
        Window("存储清理", id: "main") {
            ContentView()
                .frame(minWidth: 1100, minHeight: 720)
        }
        .windowResizability(.contentMinSize)
        .commands {
            CommandGroup(replacing: .newItem) {}
        }
    }
}

struct ContentView: View {
    @StateObject private var scanner = StorageScanner()
    @StateObject private var engine = CleanupEngine()
    @StateObject private var memoryProbe = MemoryProbe()
    @StateObject private var duplicateFinder = DuplicateFinder()
    @StateObject private var inventory = AppInventory()
    @StateObject private var history = CleanupHistory()
    @StateObject private var diskHealth = DiskHealthProbe()

    @State private var selection: Set<UUID> = []
    @State private var selectedCategory: CleanupCategory?
    @State private var showConfirm = false
    @State private var showResult = false
    @State private var resultText = ""
    @State private var isCleaning = false
    @State private var cleanProgress = ""
    @State private var section: Section = Section.initialFromLaunchArguments
    /// 待清理项，由各子视图通过 onClean 回调提交
    @State private var pendingClean: PendingClean?

    /// 每个子视图提交的清理请求。grant 决定安全护栏放行到哪一档。
    private struct PendingClean {
        let items: [CleanupItem]
        let grant: SafetyGuard.Grant?
        let confirmTitle: String
        let confirmMessage: String
    }

    enum Section: String, CaseIterable, Identifiable {
        case clean, space, memory, duplicates, uninstall, history, health
        var id: String { rawValue }

        var title: String {
            switch self {
            case .clean: return "清理"
            case .space: return "空间"
            case .memory: return "内存"
            case .duplicates: return "重复文件"
            case .uninstall: return "应用卸载"
            case .history: return "清理历史"
            case .health: return "磁盘健康"
            }
        }

        var symbol: String {
            switch self {
            case .clean: return "trash"
            case .space: return "chart.pie"
            case .memory: return "memorychip"
            case .duplicates: return "doc.on.doc"
            case .uninstall: return "shippingbox"
            case .history: return "chart.bar.xaxis"
            case .health: return "internaldrive"
            }
        }

        /// 侧边栏分组
        var group: String {
            switch self {
            case .clean, .space, .duplicates: return "存储"
            case .memory: return "系统"
            case .uninstall, .history, .health: return "工具"
            }
        }

        /// 启动参数 `--section=duplicates` 可直接打开指定页面。
        ///
        /// 用途：界面验证与截图。macOS 在未授予辅助功能权限时会拦截合成点击事件，
        /// 无法用脚本操作界面；有了这个入口就能逐个页面截图核对，而不必手工点。
        /// 非法值一律回落到「清理」，不影响正常启动。
        static var initialFromLaunchArguments: Section {
            let prefix = "--section="
            guard let arg = CommandLine.arguments.first(where: { $0.hasPrefix(prefix) })
            else { return .clean }
            let raw = String(arg.dropFirst(prefix.count))
            return Section(rawValue: raw) ?? .clean
        }
    }

    private var allItems: [CleanupItem] { scanner.groups.flatMap(\.items) }
    private var selectedItems: [CleanupItem] { allItems.filter { selection.contains($0.id) } }
    private var selectedSize: Int64 { selectedItems.reduce(0) { $0 + $1.size } }
    private var reclaimable: Int64 { scanner.groups.reduce(0) { $0 + $1.totalSize } }

    var body: some View {
        NavigationSplitView {
            sidebar
        } detail: {
            VStack(spacing: 0) {
                detailContent

                if section == .clean {
                    Divider()
                    bottomBar
                }
            }
            .background(Color(nsColor: .windowBackgroundColor))
            .navigationTitle(section.title)
        }
        .alert("确认清理", isPresented: $showConfirm) {
            Button("取消", role: .cancel) { pendingClean = nil }
            Button("移到废纸篓", role: .destructive) { performPendingClean() }
        } message: {
            Text(pendingClean?.confirmMessage ?? "")
        }
        .alert("清理完成", isPresented: $showResult) {
            Button("好") {}
        } message: {
            Text(resultText)
        }
        .task {
            // 调试/验证入口：`--autoscan` 启动后自动触发当前页面的扫描。
            // 与 --section 配合，可无人值守地把每个页面的「有数据」状态截图核对。
            guard CommandLine.arguments.contains("--autoscan") else { return }
            try? await Task.sleep(nanoseconds: 800_000_000)
            switch section {
            case .uninstall:    inventory.startScan()
            case .duplicates:   duplicateFinder.startScan()
            case .clean:        scanner.startScan(deepScan: false)
            default:            break
            }
        }
    }

    // MARK: - 侧边栏

    private var sidebar: some View {
        List(selection: $section) {
            ForEach(["存储", "系统", "工具"], id: \.self) { group in
                SwiftUI.Section(group) {
                    ForEach(Section.allCases.filter { $0.group == group }) { s in
                        Label(s.title, systemImage: s.symbol)
                            .tag(s)
                    }
                }
            }
        }
        .listStyle(.sidebar)
        .navigationSplitViewColumnWidth(min: 180, ideal: 200, max: 240)
        .safeAreaInset(edge: .bottom) {
            sidebarFooter
        }
    }

    /// 侧边栏底部：显示当前磁盘占用，给用户一个全局参照
    private var sidebarFooter: some View {
        let v = scanner.volume
        return VStack(alignment: .leading, spacing: 6) {
            Divider()
            HStack(spacing: 6) {
                Image(systemName: "internaldrive")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("\(Fmt.size(v.free)) 可用")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 3)
                        .fill(Color.secondary.opacity(0.15))
                    RoundedRectangle(cornerRadius: 3)
                        .fill(v.usedFraction > 0.9 ? Color.red : Color.accentColor)
                        .frame(width: max(2, geo.size.width * CGFloat(min(v.usedFraction, 1))))
                }
            }
            .frame(height: 5)

            Text("共 \(Fmt.size(v.total))")
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .monospacedDigit()
        }
        .padding(.horizontal, 14)
        .padding(.bottom, 10)
        .background(.bar)
    }

    // MARK: - 内容分发

    @ViewBuilder
    private var detailContent: some View {
        switch section {
        case .clean:
            cleanTab
        case .space:
            DiskSpaceView()
        case .memory:
            MemoryView(probe: memoryProbe)
        case .duplicates:
            DuplicateView(finder: duplicateFinder) { items in
                requestClean(items, grant: .verifiedDuplicate)
            }
        case .uninstall:
            UninstallerView(inventory: inventory) { items in
                requestClean(items, grant: .appUninstall)
            }
        case .history:
            HistoryView(history: history)
        case .health:
            DiskHealthView(probe: diskHealth)
        }
    }

    // MARK: - 清理页

    private var cleanTab: some View {
        VStack(spacing: 0) {
            cleanToolbar
            Divider()

            ScrollView {
                VStack(spacing: 18) {
                    DiskOverviewView(volume: scanner.volume, reclaimable: reclaimable)

                    if scanner.isScanning {
                        scanningCard
                    } else if scanner.groups.isEmpty {
                        emptyCard
                    } else {
                        HStack(alignment: .top, spacing: 18) {
                            CategoryDonutView(groups: scanner.groups, selected: $selectedCategory)
                                .frame(width: 280)
                            DetailListView(
                                groups: scanner.groups,
                                selectedCategory: $selectedCategory,
                                selection: $selection
                            )
                            .frame(maxWidth: .infinity)
                            .frame(minHeight: 380)
                        }
                    }
                }
                .padding(20)
            }
        }
    }

    private var cleanToolbar: some View {
        HStack(spacing: 12) {
            Image(systemName: "sparkles")
                .foregroundStyle(.blue)
            Text("扫描缓存、日志与开发残留")
                .font(.callout)
                .foregroundStyle(.secondary)

            Spacer()

            if scanner.isScanning {
                Button("取消") { scanner.cancel() }
            } else {
                Button {
                    selection.removeAll()
                    selectedCategory = nil
                    scanner.startScan(deepScan: false)
                } label: {
                    Label("快速扫描", systemImage: "bolt.fill")
                }

                Button {
                    selection.removeAll()
                    selectedCategory = nil
                    scanner.startScan(deepScan: true)
                } label: {
                    Label("深度扫描", systemImage: "magnifyingglass")
                }
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 11)
    }

    // MARK: - 卡片

    private var scanningCard: some View {
        VStack(spacing: 12) {
            ProgressView(value: scanner.progressValue)
                .progressViewStyle(.linear)
            Text(scanner.progressText)
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .padding(40)
        .frame(maxWidth: .infinity)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
    }

    private var emptyCard: some View {
        VStack(spacing: 10) {
            Image(systemName: "internaldrive")
                .font(.system(size: 34))
                .foregroundStyle(.tertiary)
            Text("点击「快速扫描」开始检查")
                .foregroundStyle(.secondary)
            Text("快速扫描检查常见缓存与日志；深度扫描额外查找大文件，耗时更长。")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .padding(50)
        .frame(maxWidth: .infinity)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
    }

    // MARK: - 底栏

    private var bottomBar: some View {
        HStack(spacing: 14) {
            if isCleaning {
                ProgressView().controlSize(.small)
                Text(cleanProgress).font(.callout).foregroundStyle(.secondary)
            } else {
                Button("全选安全项") {
                    // 按 defaultSelected 而非 risk 来选。
                    // 两者会矛盾：Crashpad 堆积是 .caution 但需要先退应用，
                    // 而旧逻辑只认 .safe，会漏掉真正的大头、勾上 112KB 的小文件。
                    selection = Set(allItems.filter { $0.defaultSelected && $0.risk != .dangerous }.map(\.id))
                }
                Button("清空选择") { selection.removeAll() }

                Spacer()

                if !selection.isEmpty {
                    Text("已选 \(selectedItems.count) 项 · \(Fmt.size(selectedSize))")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }

                Button {
                    showConfirm = true
                } label: {
                    Label("清理所选", systemImage: "trash")
                }
                .keyboardShortcut(.return, modifiers: .command)
                .disabled(selection.isEmpty)
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 11)
    }

    // MARK: - 执行

    /// 子视图提交清理请求：统一走确认弹窗
    private func requestClean(_ items: [CleanupItem], grant: SafetyGuard.Grant?) {
        guard !items.isEmpty else { return }
        let total = items.reduce(0) { $0 + $1.size }

        pendingClean = PendingClean(
            items: items,
            grant: grant,
            confirmTitle: "确认清理",
            confirmMessage: "将清理 \(items.count) 项，释放约 \(Fmt.size(total))。\n\n所有内容会移入废纸篓，可随时恢复。"
        )
        showConfirm = true
    }

    private func performPendingClean() {
        guard let pending = pendingClean else { return }
        pendingClean = nil

        // 清理页走原有路径（选择集在 @State 里），其余走通用路径
        if pending.grant == nil {
            performClean(items: selectedItems, grant: nil)
        } else {
            performClean(items: pending.items, grant: pending.grant)
        }
    }

    private func performClean(items: [CleanupItem], grant: SafetyGuard.Grant?) {
        guard !items.isEmpty else { return }
        isCleaning = true

        Task {
            let outcome = await engine.clean(items: items, permanent: false, grant: grant) { done, total, name in
                Task { @MainActor in
                    cleanProgress = total > 0 ? "正在清理 \(done)/\(total)… \(name)" : "收尾中…"
                }
            }

            await MainActor.run {
                isCleaning = false
                cleanProgress = ""

                // 只有成功的项才算进释放量
                let freedItems = items.filter { item in
                    !outcome.failures.contains { $0.0 == item.url }
                }
                history.record(items: freedItems, freed: outcome.freed, failureCount: outcome.failures.count)

                var msg: String
                if outcome.deleted == 0 && !outcome.failures.isEmpty {
                    // 全部失败：不能说「已清理 0 项，释放 Zero KB」还补一句
                    // 「内容已移入废纸篓」—— 那是假话，会让人以为按钮没反应。
                    msg = "没有删除任何内容，\(outcome.failures.count) 项被安全护栏拦下：\n"
                } else {
                    msg = "已清理 \(outcome.deleted) 项，释放 \(Fmt.size(outcome.freed))。"
                    if !outcome.failures.isEmpty {
                        msg += "\n\n另有 \(outcome.failures.count) 项失败：\n"
                    }
                }
                if !outcome.failures.isEmpty {
                    msg += outcome.failures.prefix(5).map { "· \($0.0.lastPathComponent)：\($0.1)" }
                        .joined(separator: "\n")
                }
                // 只有在确实有东西被移走时才提废纸篓
                if outcome.deleted > 0 {
                    msg += "\n\n内容已移入废纸篓，可随时恢复。"
                }
                resultText = msg
                showResult = true

                // 刷新受影响的数据源
                if grant == nil {
                    selection.removeAll()
                    scanner.volume = VolumeInfo.current()
                    scanner.startScan(deepScan: false)
                } else if grant == .appUninstall {
                    scanner.volume = VolumeInfo.current()
                    inventory.startScan()
                } else {
                    scanner.volume = VolumeInfo.current()
                    duplicateFinder.startScan()
                }
            }
        }
    }
}
