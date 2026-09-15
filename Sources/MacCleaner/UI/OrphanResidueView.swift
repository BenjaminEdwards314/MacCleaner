import SwiftUI
import AppKit

/// 「卸载残余」页面：列出已卸载应用留下的文件。
///
/// 与「应用卸载」页的区别：
///   - 应用卸载：应用**还在**，要连本体一起删；
///   - 卸载残余：应用**已经不在了**，只剩这些无主文件。
struct OrphanResidueView: View {
    @ObservedObject var scanner: OrphanScanner
    let onClean: ([CleanupItem]) -> Void

    @State private var selectedVendor: String?
    @State private var checked: Set<String> = []
    @State private var confirmPayload: ConfirmPayload?

    private struct ConfirmPayload: Identifiable {
        let id = UUID()
        let items: [CleanupItem]
        let title: String
        let message: String
    }

    private var selectedGroup: OrphanGroup? {
        guard let v = selectedVendor else { return scanner.groups.first }
        return scanner.groups.first { $0.vendor == v } ?? scanner.groups.first
    }

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider()

            if scanner.isScanning {
                scanningState
            } else if !scanner.hasScanned {
                emptyState
            } else if scanner.groups.isEmpty {
                nothingFoundState
            } else {
                HSplitView {
                    vendorList
                        .frame(minWidth: 240, idealWidth: 300)
                    detailPane
                        .frame(minWidth: 400)
                }
            }
        }
        .alert(item: $confirmPayload) { payload in
            Alert(
                title: Text(payload.title),
                message: Text(payload.message),
                primaryButton: .destructive(Text("移入废纸篓")) {
                    onClean(payload.items)
                    checked.removeAll()
                },
                secondaryButton: .cancel(Text("取消"))
            )
        }
    }

    // MARK: - 顶部

    private var toolbar: some View {
        HStack(spacing: 12) {
            Image(systemName: "questionmark.folder")
                .font(.title2)
                .foregroundStyle(.orange)

            VStack(alignment: .leading, spacing: 2) {
                Text("卸载残余")
                    .font(.headline)
                Text("找出已删除应用留在 ~/Library 里的无主文件")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if !scanner.groups.isEmpty {
                Text("\(scanner.groups.count) 个来源 · \(scanner.itemCount) 项 · \(Fmt.size(scanner.totalSize))")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            Button {
                checked.removeAll()
                scanner.startScan()
            } label: {
                Label(scanner.hasScanned ? "重新扫描" : "开始扫描", systemImage: "arrow.clockwise")
            }
            .buttonStyle(.borderedProminent)
            .disabled(scanner.isScanning)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
    }

    // MARK: - 各种状态

    private var scanningState: some View {
        VStack(spacing: 14) {
            ProgressView()
            Text(scanner.progressText.isEmpty ? "正在扫描…" : scanner.progressText)
                .font(.callout)
                .foregroundStyle(.secondary)
            Text("会先读取所有已安装应用的内部标识，再比对 ~/Library 中的文件")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var emptyState: some View {
        VStack(spacing: 14) {
            Image(systemName: "questionmark.folder")
                .font(.system(size: 52))
                .foregroundStyle(.tertiary)
            Text("还没有扫描过")
                .font(.title3.weight(.medium))
            Text("点击「开始扫描」，找出已被卸载但仍在占用空间的文件")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var nothingFoundState: some View {
        VStack(spacing: 14) {
            Image(systemName: "checkmark.circle")
                .font(.system(size: 52))
                .foregroundStyle(.green)
            Text("没有发现卸载残余")
                .font(.title3.weight(.medium))
            Text("已比对了 \(scanner.knownIDCount) 个应用标识，~/Library 中没有无主文件")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - 左侧：来源列表

    private var vendorList: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(scanner.groups) { group in
                    vendorRow(group)
                }
            }
        }
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.4))
    }

    private func vendorRow(_ group: OrphanGroup) -> some View {
        let isSel = selectedGroup?.vendor == group.vendor
        let allChecked = group.items.allSatisfy { checked.contains($0.id) }

        return Button {
            selectedVendor = group.vendor
        } label: {
            HStack(spacing: 10) {
                Image(systemName: allChecked ? "checkmark.circle.fill" : "circle.dashed")
                    .foregroundStyle(allChecked ? .orange : .secondary)
                    .font(.callout)

                VStack(alignment: .leading, spacing: 2) {
                    Text(group.vendor)
                        .font(.callout.weight(.medium))
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Text("\(group.items.count) 项")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Text(Fmt.size(group.totalSize))
                    .font(.callout)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
            .padding(.vertical, 9)
            .padding(.horizontal, 10)
            .contentShape(Rectangle())
            .background(isSel ? Color.accentColor.opacity(0.16) : Color.clear)
        }
        .buttonStyle(.plain)
    }

    // MARK: - 右侧：明细

    private var detailPane: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                if let g = selectedGroup {
                    detailHeader(g)
                    Divider().padding(.vertical, 12)
                    itemList(g)
                    Divider().padding(.vertical, 12)
                    limitationsNote
                }
            }
            .padding(20)
        }
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.25))
    }

    private func detailHeader(_ g: OrphanGroup) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "questionmark.folder")
                    .font(.system(size: 34))
                    .foregroundStyle(.orange)

                VStack(alignment: .leading, spacing: 4) {
                    Text(g.vendor)
                        .font(.title2.weight(.semibold))
                    Text("未找到对应的已安装应用")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }

            HStack(spacing: 10) {
                Button {
                    toggleAll(g)
                } label: {
                    Label(allChecked(g) ? "取消全选" : "全选此项",
                          systemImage: allChecked(g) ? "circle.dashed" : "checkmark.circle")
                }
                .buttonStyle(.bordered)

                Button {
                    let items = g.items
                        .filter { checked.contains($0.id) }
                        .map { toCleanupItem($0) }
                    guard !items.isEmpty else { return }
                    let total = items.reduce(Int64(0)) { $0 + $1.size }
                    confirmPayload = ConfirmPayload(
                        items: items,
                        title: "删除 \(items.count) 项残余？",
                        message: """
                        来源：\(g.vendor)
                        合计：\(Fmt.size(total))

                        这些文件将被移入废纸篓，可随时恢复。
                        若你其实还在使用这个应用，请先取消勾选。
                        """
                    )
                } label: {
                    Label("清理勾选的 \(checkedFor(g)) 项", systemImage: "trash")
                }
                .buttonStyle(.borderedProminent)
                .tint(.orange)
                .disabled(checkedFor(g) == 0)
            }
        }
    }

    private func itemList(_ g: OrphanGroup) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("残余文件")
                .font(.headline)

            ForEach(g.items) { item in
                HStack(spacing: 10) {
                    Button {
                        if checked.contains(item.id) { checked.remove(item.id) }
                        else { checked.insert(item.id) }
                    } label: {
                        Image(systemName: checked.contains(item.id) ? "checkmark.square.fill" : "square")
                            .foregroundStyle(checked.contains(item.id) ? .orange : .secondary)
                    }
                    .buttonStyle(.plain)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(item.name)
                            .font(.callout)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Text("~/Library/\(item.kind)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    if let m = item.modified {
                        Text(m, format: .dateTime.year().month().day())
                            .font(.caption)
                            .monospacedDigit()
                            .foregroundStyle(.tertiary)
                    }

                    Text(Fmt.size(item.size))
                        .font(.callout)
                        .monospacedDigit()
                        .foregroundStyle(.secondary)

                    Button {
                        NSWorkspace.shared.activateFileViewerSelecting([item.url])
                    } label: {
                        Image(systemName: "folder")
                    }
                    .buttonStyle(.plain)
                    .help("在访达中显示")
                }
                .padding(.vertical, 7)
                .padding(.horizontal, 8)
                .background(Color.secondary.opacity(0.045))
                .clipShape(RoundedRectangle(cornerRadius: 6))
            }
        }
    }

    private var limitationsNote: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("判定依据与限制", systemImage: "info.circle")
                .font(.callout.weight(.medium))
                .foregroundStyle(.secondary)

            Text("• 判定方式是「该标识不被任何已安装应用引用」。会读取每个应用**内部**的全部标识，以及它在 entitlements 里声明的 group container（实测本机共 \(scanner.knownIDCount) 个）—— 只比对顶层标识会大量误判。")
                .font(.caption)
                .foregroundStyle(.secondary)
            Text("• 同时要求 30 天内未被访问，作为最后一道保守兜底。")
                .font(.caption)
                .foregroundStyle(.secondary)
            Text("• 只移入废纸篓，不提供永久删除。删错了可以从废纸篓取回。")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.orange.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    // MARK: - 辅助

    private func allChecked(_ g: OrphanGroup) -> Bool {
        !g.items.isEmpty && g.items.allSatisfy { checked.contains($0.id) }
    }

    private func toggleAll(_ g: OrphanGroup) {
        if allChecked(g) {
            for i in g.items { checked.remove(i.id) }
        } else {
            for i in g.items { checked.insert(i.id) }
        }
    }

    private func checkedFor(_ g: OrphanGroup) -> Int {
        g.items.filter { checked.contains($0.id) }.count
    }

    private func toCleanupItem(_ o: OrphanItem) -> CleanupItem {
        CleanupItem(
            url: o.url, size: o.size, category: .orphanResidue, risk: .caution,
            explanation: "已卸载应用 \(o.vendor) 的残余文件",
            defaultSelected: false, modified: o.modified
        )
    }
}
