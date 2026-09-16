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
            Divider().overlay(PPG.ink.opacity(0.18))

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
        VStack(spacing: 0) {
            ComicSectionHeader(
                "卸载残余", icon: "questionmark.folder", tint: PPG.grape,
                trailing: AnyView(
                    HStack(spacing: 10) {
                        if !scanner.groups.isEmpty {
                            ComicBadge(
                                text: "\(scanner.groups.count) 个来源 · \(scanner.itemCount) 项 · \(Fmt.size(scanner.totalSize))",
                                tint: PPG.sunny, icon: "shippingbox.fill"
                            )
                        }

                        Button {
                            checked.removeAll()
                            scanner.startScan()
                        } label: {
                            Label(scanner.hasScanned ? "重新扫描" : "开始扫描",
                                  systemImage: "arrow.clockwise")
                        }
                        .buttonStyle(ComicButtonStyle(tint: PPG.sunny, size: .regular))
                        .disabled(scanner.isScanning)
                    }
                )
            )
            .padding(.horizontal, 20)
            .padding(.top, 15)

            Text("找出已删除应用留在 ~/Library 里的无主文件")
                .font(.ppgBody)
                .foregroundStyle(PPG.ink.opacity(0.6))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 20)
                .padding(.top, 5)
                .padding(.bottom, 14)
        }
        .background {
            PPG.cream.opacity(0.75)
                .overlay(alignment: .bottom) {
                    Rectangle().fill(PPG.ink.opacity(0.18)).frame(height: 1.5)
                }
        }
    }

    // MARK: - 各种状态

    private var scanningState: some View {
        VStack(spacing: 0) {
            VStack(spacing: 14) {
                HStack(spacing: 10) {
                    Image(systemName: "sparkles")
                        .font(.ppg(20, .black))
                        .foregroundStyle(PPG.grape)
                    Text(scanner.progressText.isEmpty ? "正在扫描…" : scanner.progressText)
                        .font(.ppg(20, .black))
                        .foregroundStyle(PPG.ink)
                        .lineLimit(1)
                    Spacer(minLength: 10)
                    ProgressView().controlSize(.small)
                }

                Text("会先读取所有已安装应用的内部标识，再比对 ~/Library 中的文件")
                    .font(.ppgBody)
                    .foregroundStyle(PPG.ink.opacity(0.6))
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .comicCard(tint: PPG.grape, padding: 22)
            .frame(maxWidth: 620)

            Spacer(minLength: 0)
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    private var emptyState: some View {
        ComicEmptyState(
            icon: "questionmark.folder",
            title: "还没有扫描过",
            message: "点击「开始扫描」，找出已被卸载但仍在占用空间的文件",
            tint: PPG.grape,
            action: (title: "开始扫描", handler: {
                checked.removeAll()
                scanner.startScan()
            })
        )
        .padding(20)
    }

    private var nothingFoundState: some View {
        ComicEmptyState(
            icon: "checkmark.circle",
            title: "没有发现卸载残余",
            message: "已比对了 \(scanner.knownIDCount) 个应用标识，~/Library 中没有无主文件",
            tint: PPG.buttercup
        )
        .padding(20)
    }

    // MARK: - 左侧：来源列表

    private var vendorList: some View {
        ScrollView {
            LazyVStack(spacing: 7) {
                ForEach(scanner.groups) { group in
                    vendorRow(group)
                }
            }
            .padding(10)
        }
    }

    private func vendorRow(_ group: OrphanGroup) -> some View {
        let isSel = selectedGroup?.vendor == group.vendor
        let allChecked = group.items.allSatisfy { checked.contains($0.id) }
        // 按来源在列表里的固定序号循环取主角色，不用 hashValue
        let idx = scanner.groups.firstIndex { $0.vendor == group.vendor } ?? 0
        let tint = PPG.girl(idx)

        return Button {
            withAnimation(.spring(response: 0.26, dampingFraction: 0.75)) {
                selectedVendor = group.vendor
            }
        } label: {
            HStack(spacing: 10) {
                // 已勾选状态放进圆形色块，比裸图标更醒目
                ZStack {
                    Circle()
                        .fill(allChecked ? tint : PPG.cream)
                        .overlay {
                            Circle().strokeBorder(
                                allChecked ? PPG.ink : PPG.ink.opacity(0.3),
                                lineWidth: allChecked ? 2.2 : 1.6
                            )
                        }
                        .frame(width: 26, height: 26)
                    Image(systemName: allChecked ? "checkmark.circle.fill" : "circle.dashed")
                        .font(.ppg(12, .black))
                        .foregroundStyle(PPG.ink.opacity(allChecked ? 1 : 0.55))
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(group.vendor)
                        .font(.ppg(13.5, isSel ? .black : .bold))
                        .foregroundStyle(PPG.ink)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Text("\(group.items.count) 项")
                        .font(.ppgCaption)
                        .foregroundStyle(PPG.ink.opacity(0.5))
                }

                Spacer(minLength: 6)

                Text(Fmt.size(group.totalSize))
                    .font(.ppg(12.5, .heavy))
                    .foregroundStyle(PPG.ink.opacity(isSel ? 1 : 0.62))
                    .monospacedDigit()
            }
            .padding(.horizontal, 9)
            .padding(.vertical, 9)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                // 选中态：主角色填充 + 黑描边 + 硬阴影（与侧边栏导航一致）
                if isSel {
                    RoundedRectangle(cornerRadius: 13, style: .continuous)
                        .fill(tint.opacity(0.34))
                        .overlay {
                            RoundedRectangle(cornerRadius: 13, style: .continuous)
                                .strokeBorder(PPG.ink, lineWidth: 2.2)
                        }
                        .background {
                            RoundedRectangle(cornerRadius: 13, style: .continuous)
                                .fill(PPG.ink.opacity(0.8))
                                .offset(x: 2.5, y: 2.5)
                        }
                } else {
                    RoundedRectangle(cornerRadius: 13, style: .continuous)
                        .fill(PPG.ink.opacity(0.04))
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(SidebarRowStyle())
    }

    // MARK: - 右侧：明细

    private var detailPane: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                if let g = selectedGroup {
                    detailHeader(g)
                    itemList(g)
                    limitationsNote
                }
            }
            .padding(20)
        }
    }

    private func detailHeader(_ g: OrphanGroup) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 12) {
                ZStack {
                    Circle()
                        .fill(PPG.grape)
                        .overlay { Circle().strokeBorder(PPG.ink, lineWidth: 2.2) }
                        .frame(width: 46, height: 46)
                    Image(systemName: "questionmark.folder")
                        .font(.ppg(20, .black))
                        .foregroundStyle(PPG.ink)
                }

                VStack(alignment: .leading, spacing: 5) {
                    Text(g.vendor)
                        .font(.ppg(21, .black))
                        .foregroundStyle(PPG.ink)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    ComicBadge(text: "未找到对应的已安装应用",
                               tint: PPG.danger, icon: "exclamationmark.triangle.fill")
                }
                Spacer(minLength: 8)
            }

            HStack(spacing: 10) {
                Button {
                    toggleAll(g)
                } label: {
                    Label(allChecked(g) ? "取消全选" : "全选此项",
                          systemImage: allChecked(g) ? "circle.dashed" : "checkmark.circle")
                }
                .buttonStyle(ComicButtonStyle(tint: PPG.buttercup, size: .regular))

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
                    Label("清理勾选的 \(checkedFor(g)) 项", systemImage: "trash.fill")
                }
                // 破坏性操作：红底白字，与「移入废纸篓」的语义对齐
                .buttonStyle(ComicButtonStyle(tint: PPG.dangerDeep, size: .large,
                                              textColor: .white))
                .disabled(checkedFor(g) == 0)

                Spacer(minLength: 0)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .comicCard(tint: PPG.grape, padding: 16)
    }

    private func itemList(_ g: OrphanGroup) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            ComicSectionHeader(
                "残余文件", icon: "shippingbox", tint: PPG.buttercup,
                trailing: AnyView(
                    ComicBadge(text: "\(checkedFor(g)) / \(g.items.count) 项已勾选",
                               tint: PPG.sunny, icon: "checkmark.circle.fill")
                )
            )

            VStack(spacing: 3) {
                ForEach(Array(g.items.enumerated()), id: \.element.id) { ri, item in
                    itemRow(item, tint: PPG.girl(ri))
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .comicCard(tint: PPG.buttercup, padding: 12)
    }

    private func itemRow(_ item: OrphanItem, tint: Color) -> some View {
        let on = checked.contains(item.id)

        return HStack(spacing: 11) {
            ComicCheckbox(isOn: on, tint: tint) {
                if on { checked.remove(item.id) } else { checked.insert(item.id) }
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(item.name)
                    .font(.ppg(13, .bold))
                    .foregroundStyle(PPG.ink)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text("~/Library/\(item.kind)")
                    .font(.ppg(10.5, .medium))
                    .foregroundStyle(PPG.ink.opacity(0.45))
            }

            Spacer(minLength: 6)

            if let m = item.modified {
                Text(m, format: .dateTime.year().month().day())
                    .font(.ppgCaption)
                    .foregroundStyle(PPG.ink.opacity(0.45))
                    .monospacedDigit()
            }

            Text(Fmt.size(item.size))
                .font(.ppg(12.5, .heavy))
                .foregroundStyle(PPG.ink)
                .monospacedDigit()
                .frame(width: 74, alignment: .trailing)

            Button {
                NSWorkspace.shared.activateFileViewerSelecting([item.url])
            } label: {
                Image(systemName: "folder.fill")
            }
            .buttonStyle(ComicIconButtonStyle(tint: PPG.sunny, diameter: 32))
            .help("在访达中显示")
        }
        .padding(.horizontal, 11)
        .padding(.vertical, 7)
        .background {
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .fill(on ? tint.opacity(0.2) : PPG.ink.opacity(0.04))
        }
        // 整行可点：命中区从勾选框扩大到整行
        .contentShape(Rectangle())
        .onTapGesture {
            if on { checked.remove(item.id) } else { checked.insert(item.id) }
        }
    }

    private var limitationsNote: some View {
        VStack(alignment: .leading, spacing: 8) {
            ComicSectionHeader("判定依据与限制", icon: "info.circle", tint: PPG.sunny)

            Text("• 判定方式是「该标识不被任何已安装应用引用」。会读取每个应用**内部**的全部标识，以及它在 entitlements 里声明的 group container（实测本机共 \(scanner.knownIDCount) 个）—— 只比对顶层标识会大量误判。")
                .font(.ppgCaption)
                .foregroundStyle(PPG.ink.opacity(0.6))
                .fixedSize(horizontal: false, vertical: true)
            Text("• 同时要求 30 天内未被访问，作为最后一道保守兜底。")
                .font(.ppgCaption)
                .foregroundStyle(PPG.ink.opacity(0.6))
                .fixedSize(horizontal: false, vertical: true)
            Text("• 只移入废纸篓，不提供永久删除。删错了可以从废纸篓取回。")
                .font(.ppgCaption)
                .foregroundStyle(PPG.ink.opacity(0.6))
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .comicCard(tint: PPG.sunny, padding: 14)
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
