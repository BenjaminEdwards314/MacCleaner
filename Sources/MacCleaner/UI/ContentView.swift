import SwiftUI

@main
struct MacCleanerApp: App {
    var body: some Scene {
        Window("存储清理", id: "main") {
            ContentView()
                .frame(minWidth: 1040, minHeight: 700)
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

    @State private var selection: Set<UUID> = []
    @State private var selectedCategory: CleanupCategory?
    @State private var showConfirm = false
    @State private var showResult = false
    @State private var resultText = ""
    @State private var isCleaning = false
    @State private var cleanProgress = ""
    @State private var mode: Mode = .clean

    enum Mode: String, CaseIterable {
        case clean, space, memory
        var title: String {
            switch self {
            case .clean: return "清理"
            case .space: return "空间"
            case .memory: return "内存"
            }
        }
        var symbol: String {
            switch self {
            case .clean: return "trash"
            case .space: return "chart.pie"
            case .memory: return "memorychip"
            }
        }
    }

    private var allItems: [CleanupItem] { scanner.groups.flatMap(\.items) }
    private var selectedItems: [CleanupItem] { allItems.filter { selection.contains($0.id) } }
    private var selectedSize: Int64 { selectedItems.reduce(0) { $0 + $1.size } }
    private var reclaimable: Int64 { scanner.groups.reduce(0) { $0 + $1.totalSize } }

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider()

            if mode == .space {
                DiskSpaceView()
            } else if mode == .memory {
                MemoryView(probe: memoryProbe)
            } else {
                cleanTab
            }

            if mode == .clean {
                Divider()
                bottomBar
            }
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .alert("确认清理", isPresented: $showConfirm) {
            Button("取消", role: .cancel) {}
            Button("移到废纸篓", role: .destructive) { performClean() }
        } message: {
            Text("将清理 \(selectedItems.count) 项，释放约 \(Fmt.size(selectedSize))。\n\n所有内容会移入废纸篓，可随时恢复。")
        }
        .alert("清理完成", isPresented: $showResult) {
            Button("好") {}
        } message: {
            Text(resultText)
        }
    }

    // MARK: - 清理页

    private var cleanTab: some View {
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

    // MARK: - 顶栏

    private var toolbar: some View {
        HStack(spacing: 12) {
            Image(systemName: "sparkles")
                .foregroundStyle(.blue)
            Text("Mac 存储清理")
                .font(.headline)

            Picker("", selection: $mode) {
                ForEach(Mode.allCases, id: \.self) { m in
                    Label(m.title, systemImage: m.symbol).tag(m)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(width: 250)

            Spacer()

            if mode == .clean {
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

    private func performClean() {
        let items = selectedItems
        guard !items.isEmpty else { return }
        isCleaning = true

        Task {
            let outcome = await engine.clean(items: items, permanent: false) { done, total, name in
                Task { @MainActor in
                    cleanProgress = total > 0 ? "正在清理 \(done)/\(total)… \(name)" : "收尾中…"
                }
            }

            await MainActor.run {
                isCleaning = false
                cleanProgress = ""

                var msg = "已清理 \(outcome.deleted) 项，释放 \(Fmt.size(outcome.freed))。"
                if !outcome.failures.isEmpty {
                    msg += "\n\n\(outcome.failures.count) 项失败：\n"
                    msg += outcome.failures.prefix(5).map { "· \($0.0.lastPathComponent)：\($0.1)" }
                        .joined(separator: "\n")
                }
                msg += "\n\n内容已移入废纸篓，可随时恢复。"
                resultText = msg
                showResult = true

                selection.removeAll()
                scanner.volume = VolumeInfo.current()
                scanner.startScan(deepScan: false)
            }
        }
    }
}
