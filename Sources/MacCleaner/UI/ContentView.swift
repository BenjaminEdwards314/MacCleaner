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
    @StateObject private var orphanScanner = OrphanScanner()

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
    /// 清理成功后的庆祝动画数据。nil 表示不显示。
    @State private var celebration: (freed: Int64, count: Int)?
    /// 庆祝动画关闭后需要补报的失败详情（部分失败时才非空）
    @State private var deferredFailureText: String?

    /// 每个子视图提交的清理请求。grant 决定安全护栏放行到哪一档。
    private struct PendingClean {
        let items: [CleanupItem]
        let grant: SafetyGuard.Grant?
        let confirmTitle: String
        let confirmMessage: String
    }

    enum Section: String, CaseIterable, Identifiable {
        case clean, space, memory, duplicates, uninstall, orphans, history, health
        var id: String { rawValue }

        var title: String {
            switch self {
            case .clean: return "清理"
            case .space: return "空间"
            case .memory: return "内存"
            case .duplicates: return "重复文件"
            case .uninstall: return "应用卸载"
            case .orphans: return "卸载残余"
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
            case .orphans: return "questionmark.folder"
            case .history: return "chart.bar.xaxis"
            case .health: return "internaldrive"
            }
        }

        /// 侧边栏分组
        var group: String {
            switch self {
            case .clean, .space, .duplicates: return "存储"
            case .memory: return "系统"
            case .uninstall, .orphans, .history, .health: return "工具"
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
            .background(PPG.backdrop)
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
        .overlay {
            if let c = celebration {
                CleanCelebrationView(freed: c.freed, count: c.count) {
                    celebration = nil
                    // 如果有部分失败，庆祝完再把详情报出来，
                    // 免得失败信息被庆祝动画盖掉、用户以为全都成功了。
                    if let deferred = deferredFailureText {
                        deferredFailureText = nil
                        resultText = deferred
                        showResult = true
                    }
                }
                .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.25), value: celebration == nil)
        .task {
            // 调试/验证入口：`--autoscan` 启动后自动触发当前页面的扫描。
            // 与 --section 配合，可无人值守地把每个页面的「有数据」状态截图核对。
            // `--demo-celebration` 直接展示清理完成动画。
            // 庆祝动画只在真实清理成功（freed > 0）后出现，而 macOS 在未授予
            // 辅助功能权限时会拦截合成点击，无法脚本触发清理。加这个入口才能
            // 截图核对动画效果，与 --section/--autoscan 同类，不影响正常启动。
            if CommandLine.arguments.contains("--demo-celebration") {
                try? await Task.sleep(nanoseconds: 600_000_000)
                celebration = (4_820_000_000, 37)
                return
            }

            guard CommandLine.arguments.contains("--autoscan") else { return }
            try? await Task.sleep(nanoseconds: 800_000_000)
            switch section {
            case .uninstall:    inventory.startScan()
            case .orphans:      orphanScanner.startScan()
            case .duplicates:   duplicateFinder.startScan()
            case .clean:        scanner.startScan(deepScan: false)
            default:            break
            }
        }
    }

    // MARK: - 侧边栏

    private var sidebar: some View {
        VStack(spacing: 0) {
            // 顶部品牌区
            sidebarBrand
            Divider().overlay(PPG.ink.opacity(0.25))

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    ForEach(["存储", "系统", "工具"], id: \.self) { group in
                        VStack(alignment: .leading, spacing: 6) {
                            Text(group)
                                .font(.ppg(11, .black))
                                .foregroundStyle(PPG.ink.opacity(0.45))
                                .padding(.horizontal, 12)

                            ForEach(Section.allCases.filter { $0.group == group }) { item in
                                sidebarRow(item)
                            }
                        }
                    }
                }
                .padding(.vertical, 12)
            }
        }
        .background(PPG.sidebarBackdrop)
        .navigationSplitViewColumnWidth(min: 208, ideal: 226, max: 260)
        .safeAreaInset(edge: .bottom) { sidebarFooter }
    }

    /// 侧边栏顶部：星形徽标 + 应用名
    private var sidebarBrand: some View {
        HStack(spacing: 10) {
            ZStack {
                StarburstShape(points: 12, innerRatio: 0.7)
                    .fill(PPG.sunny)
                    .overlay {
                        StarburstShape(points: 12, innerRatio: 0.7)
                            .stroke(PPG.ink, lineWidth: 2)
                    }
                    .frame(width: 36, height: 36)
                Image(systemName: "sparkles")
                    .font(.ppg(15, .black))
                    .foregroundStyle(PPG.ink)
            }

            VStack(alignment: .leading, spacing: 1) {
                Text("MacCleaner")
                    .font(.ppg(15, .black))
                    .foregroundStyle(PPG.ink)
                Text("磁盘与内存清理")
                    .font(.ppg(10, .bold))
                    .foregroundStyle(PPG.ink.opacity(0.5))
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 12)
        .background {
            HalftoneDots(spacing: 8, dot: 1.8, opacity: 0.05)
        }
    }

    /// 单个导航项。用 Button 而非 List 行 —— 自绘才能做出按下回弹和选中态描边。
    private func sidebarRow(_ item: Section) -> some View {
        let isSel = section == item
        let tint = PPG.girl(Section.allCases.firstIndex(of: item) ?? 0)

        return Button {
            withAnimation(.spring(response: 0.28, dampingFraction: 0.72)) {
                section = item
            }
        } label: {
            HStack(spacing: 10) {
                // 图标放在圆形色块里，选中时填充主角色
                ZStack {
                    Circle()
                        .fill(isSel ? tint : PPG.cream)
                        .overlay {
                            Circle().strokeBorder(
                                isSel ? PPG.ink : PPG.ink.opacity(0.28),
                                lineWidth: isSel ? 2.2 : 1.6
                            )
                        }
                        .frame(width: 27, height: 27)
                    Image(systemName: item.symbol)
                        .font(.ppg(12.5, .black))
                        .foregroundStyle(PPG.ink.opacity(isSel ? 1 : 0.62))
                }

                Text(item.title)
                    .font(.ppg(13.5, isSel ? .black : .semibold))
                    .foregroundStyle(PPG.ink.opacity(isSel ? 1 : 0.72))

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 7)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                if isSel {
                    RoundedRectangle(cornerRadius: 13, style: .continuous)
                        .fill(tint.opacity(0.42))
                        .overlay {
                            RoundedRectangle(cornerRadius: 13, style: .continuous)
                                .strokeBorder(PPG.ink, lineWidth: 2.2)
                        }
                        .background {
                            RoundedRectangle(cornerRadius: 13, style: .continuous)
                                .fill(PPG.ink.opacity(0.8))
                                .offset(x: 2.5, y: 2.5)
                        }
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(SidebarRowStyle())
        .padding(.horizontal, 8)
    }

    private var sidebarFooter: some View {
        let v = scanner.volume
        let frac = min(max(v.usedFraction, 0), 1)
        // 超过 90% 转红，给一个明确的视觉警示
        let tint = frac > 0.9 ? PPG.danger : (frac > 0.75 ? PPG.sunny : PPG.buttercup)

        return VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 6) {
                Image(systemName: "internaldrive.fill")
                    .font(.ppg(11, .black))
                    .foregroundStyle(tint)
                Text("\(Fmt.size(v.free)) 可用")
                    .font(.ppg(12.5, .heavy))
                    .foregroundStyle(PPG.ink)
                    .monospacedDigit()
            }

            ComicProgressBar(value: frac, tint: tint, height: 12)

            Text("共 \(Fmt.size(v.total))")
                .font(.ppg(10.5, .semibold))
                .foregroundStyle(PPG.ink.opacity(0.45))
                .monospacedDigit()
        }
        .padding(.horizontal, 14)
        .padding(.top, 10)
        .padding(.bottom, 12)
        .background {
            PPG.cream.opacity(0.92)
                .overlay(alignment: .top) {
                    Rectangle().fill(PPG.ink.opacity(0.2)).frame(height: 1.5)
                }
        }
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
        case .orphans:
            OrphanResidueView(scanner: orphanScanner) { items in
                requestClean(items, grant: .orphanResidue)
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
            ZStack {
                Circle().fill(PPG.sunny)
                    .overlay { Circle().strokeBorder(PPG.ink, lineWidth: 2) }
                    .frame(width: 30, height: 30)
                Image(systemName: "sparkles")
                    .font(.ppg(13, .black))
                    .foregroundStyle(PPG.ink)
            }

            Text("扫描缓存、日志与开发残留")
                .font(.ppgBody)
                .foregroundStyle(PPG.ink.opacity(0.7))

            Spacer()

            if scanner.isScanning {
                Button("取消") { scanner.cancel() }
                    .buttonStyle(ComicButtonStyle(tint: PPG.danger, size: .regular))
            } else {
                Button {
                    selection.removeAll()
                    selectedCategory = nil
                    scanner.startScan(deepScan: false)
                } label: {
                    Label("快速扫描", systemImage: "bolt.fill")
                }
                .buttonStyle(ComicButtonStyle(tint: PPG.sunny, size: .regular))

                Button {
                    selection.removeAll()
                    selectedCategory = nil
                    scanner.startScan(deepScan: true)
                } label: {
                    Label("深度扫描", systemImage: "magnifyingglass")
                }
                .buttonStyle(ComicButtonStyle(tint: PPG.bubbles, size: .regular))
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 13)
        .background {
            PPG.cream.opacity(0.75)
                .overlay(alignment: .bottom) {
                    Rectangle().fill(PPG.ink.opacity(0.18)).frame(height: 1.5)
                }
        }
    }

    // MARK: - 卡片

    private var scanningCard: some View {
        VStack(spacing: 16) {
            HStack(spacing: 10) {
                Image(systemName: "sparkles")
                    .font(.ppg(20, .black))
                    .foregroundStyle(PPG.blossom)
                Text("正在扫描…")
                    .font(.ppg(20, .black))
                    .foregroundStyle(PPG.ink)
                Spacer()
                Text("\(Int(scanner.progressValue * 100))%")
                    .font(.ppg(20, .black))
                    .foregroundStyle(PPG.ink.opacity(0.5))
                    .monospacedDigit()
            }

            ComicProgressBar(value: scanner.progressValue,
                             tint: PPG.blossom, height: 20, striped: true)

            Text(scanner.progressText)
                .font(.ppgBody)
                .foregroundStyle(PPG.ink.opacity(0.6))
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .comicCard(tint: PPG.blossom, padding: 22)
    }

    private var emptyCard: some View {
        ComicEmptyState(
            icon: "internaldrive",
            title: "准备就绪",
            message: "快速扫描检查常见缓存与日志；深度扫描额外查找大文件，耗时更长。",
            tint: PPG.bubbles
        )
        .comicCard(tint: PPG.bubbles, padding: 10)
    }

    // MARK: - 底栏

    private var bottomBar: some View {
        HStack(spacing: 12) {
            if isCleaning {
                ProgressView().controlSize(.small)
                Text(cleanProgress)
                    .font(.ppgBody)
                    .foregroundStyle(PPG.ink.opacity(0.7))
                Spacer()
            } else {
                Button("全选安全项") {
                    // 按 defaultSelected 而非 risk 来选。
                    // 两者会矛盾：Crashpad 堆积是 .caution 但需要先退应用，
                    // 而旧逻辑只认 .safe，会漏掉真正的大头、勾上 112KB 的小文件。
                    selection = Set(allItems.filter { $0.defaultSelected && $0.risk != .dangerous }.map(\.id))
                }
                .buttonStyle(ComicButtonStyle(tint: PPG.buttercup, size: .regular, burst: false))

                Button("清空选择") { selection.removeAll() }
                    .buttonStyle(ComicButtonStyle(tint: PPG.cream, size: .regular,
                                                  burst: false, outlined: true))

                Spacer()

                if !selection.isEmpty {
                    ComicBadge(text: "已选 \(selectedItems.count) 项 · \(Fmt.size(selectedSize))",
                               tint: PPG.sunny, icon: "checkmark.circle.fill")
                }

                Button {
                    showConfirm = true
                } label: {
                    Label("清理所选", systemImage: "trash.fill")
                }
                .buttonStyle(ComicButtonStyle(tint: PPG.dangerDeep, size: .large,
                                              textColor: .white))
                .keyboardShortcut(.return, modifiers: .command)
                .disabled(selection.isEmpty)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 13)
        .background {
            PPG.cream.opacity(0.9)
                .overlay(alignment: .top) {
                    Rectangle().fill(PPG.ink.opacity(0.18)).frame(height: 1.5)
                }
        }
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
                // 成功（有实际释放）走庆祝动画；否则弹 alert 说明为什么没删掉。
                // 全部失败时绝不能庆祝 —— 那等于给一次失败鼓掌。
                if outcome.freed > 0 && outcome.deleted > 0 {
                    if outcome.failures.isEmpty {
                        celebration = (outcome.freed, outcome.deleted)
                    } else {
                        // 部分成功：先庆祝，失败详情留到庆祝关闭后再报
                        deferredFailureText = msg
                        celebration = (outcome.freed, outcome.deleted)
                    }
                } else {
                    resultText = msg
                    showResult = true
                }

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
