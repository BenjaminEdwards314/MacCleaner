import SwiftUI
import AppKit

/// 应用卸载视图。
///
/// 拆成两级：左侧应用列表，右侧该应用的本体与残留明细。
/// 这样单个应用的删除范围一目了然 —— 卸载是破坏性最强的操作，
/// 不应该用「一行一个应用 + 一个删除按钮」的紧凑列表糊过去。
struct UninstallerView: View {
    @ObservedObject var inventory: AppInventory
    /// 执行清理，由 ContentView 统一处理
    let onClean: ([CleanupItem]) -> Void

    @State private var selectedAppID: UUID?
    @State private var confirmPayload: ConfirmPayload?
    @State private var searchText = ""

    /// 待确认的删除请求
    private struct ConfirmPayload: Identifiable {
        let id = UUID()
        let items: [CleanupItem]
        let title: String
        let message: String
    }

    private var filteredApps: [AppInventory.InstalledApp] {
        guard !searchText.isEmpty else { return inventory.apps }
        let q = searchText.lowercased()
        return inventory.apps.filter {
            $0.name.lowercased().contains(q) || $0.bundleID.lowercased().contains(q)
        }
    }

    private var selectedApp: AppInventory.InstalledApp? {
        guard let id = selectedAppID else { return filteredApps.first }
        return inventory.apps.first { $0.id == id } ?? filteredApps.first
    }

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider().overlay(PPG.ink.opacity(0.18))

            if inventory.isScanning {
                scanningState
            } else if !inventory.hasScanned {
                emptyState
            } else if inventory.apps.isEmpty {
                noAppsState
            } else {
                HSplitView {
                    appList
                        .frame(minWidth: 240, idealWidth: 280)
                    detailPane
                        .frame(minWidth: 380)
                }
            }
        }
        .alert(item: $confirmPayload) { payload in
            Alert(
                title: Text(payload.title),
                message: Text(payload.message),
                primaryButton: .destructive(Text("移入废纸篓")) {
                    onClean(payload.items)
                },
                secondaryButton: .cancel(Text("取消"))
            )
        }
    }

    // MARK: - 顶部

    private var toolbar: some View {
        VStack(spacing: 0) {
            ComicSectionHeader(
                "应用卸载", icon: "shippingbox", tint: PPG.grape,
                trailing: AnyView(
                    HStack(spacing: 10) {
                        if inventory.hasScanned {
                            TextField("搜索应用", text: $searchText)
                                .textFieldStyle(.plain)
                                .font(.ppg(12.5, .bold))
                                .foregroundStyle(PPG.ink)
                                .padding(.horizontal, 11)
                                .padding(.vertical, 8)
                                .frame(width: 180)
                                .background {
                                    RoundedRectangle(cornerRadius: 11, style: .continuous)
                                        .fill(PPG.cream)
                                        .overlay {
                                            RoundedRectangle(cornerRadius: 11, style: .continuous)
                                                .strokeBorder(PPG.ink, lineWidth: 2.2)
                                        }
                                }
                        }

                        if inventory.isScanning {
                            Button("取消") { inventory.cancel() }
                                .buttonStyle(ComicButtonStyle(tint: PPG.dangerDeep, size: .regular,
                                                              textColor: .white))
                        } else {
                            Button {
                                inventory.startScan()
                            } label: {
                                Label(inventory.hasScanned ? "重新扫描" : "开始扫描",
                                      systemImage: "arrow.clockwise")
                            }
                            .buttonStyle(ComicButtonStyle(tint: PPG.sunny, size: .regular))
                        }
                    }
                )
            )
            .padding(.horizontal, 18)
            .padding(.top, 14)

            Text("删除应用本体，并清理它在 ~/Library 里的残留")
                .font(.ppgBody)
                .foregroundStyle(PPG.ink.opacity(0.6))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 18)
                .padding(.top, 5)
                .padding(.bottom, 13)
        }
        .background {
            PPG.cream.opacity(0.75)
                .overlay(alignment: .bottom) {
                    Rectangle().fill(PPG.ink.opacity(0.18)).frame(height: 1.5)
                }
        }
    }

    // MARK: - 状态

    private var scanningState: some View {
        VStack(spacing: 0) {
            VStack(spacing: 14) {
                HStack(spacing: 10) {
                    Image(systemName: "sparkles")
                        .font(.ppg(20, .black))
                        .foregroundStyle(PPG.bubbles)
                    Text(inventory.progressText.isEmpty ? "正在扫描…" : inventory.progressText)
                        .font(.ppg(20, .black))
                        .foregroundStyle(PPG.ink)
                        .lineLimit(1)
                    Spacer(minLength: 10)
                    ProgressView().controlSize(.small)
                }

                Text("只列举 ~/Library 各目录的一层内容来匹配残留，不递归遍历")
                    .font(.ppgBody)
                    .foregroundStyle(PPG.ink.opacity(0.6))
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .comicCard(tint: PPG.bubbles, padding: 22)
            .frame(maxWidth: 620)

            Spacer(minLength: 0)
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    private var emptyState: some View {
        ComicEmptyState(
            icon: "shippingbox",
            title: "还没有扫描过",
            message: "点击「开始扫描」列出已安装的应用及其残留",
            tint: PPG.grape,
            action: (title: "开始扫描", handler: { inventory.startScan() })
        )
        .padding(20)
    }

    private var noAppsState: some View {
        ComicEmptyState(
            icon: "questionmark.folder",
            title: "未找到可卸载的应用",
            message: "系统自带应用不在此列出",
            tint: PPG.sunny
        )
        .padding(20)
    }

    // MARK: - 左侧应用列表

    private var appList: some View {
        ScrollView {
            LazyVStack(spacing: 7) {
                ForEach(filteredApps) { app in
                    appRow(app)
                }
            }
            .padding(10)
        }
    }

    private func appRow(_ app: AppInventory.InstalledApp) -> some View {
        let isSel = selectedApp?.id == app.id
        // 用应用在筛选结果里的固定序号循环取色，不用 hashValue
        let idx = filteredApps.firstIndex { $0.id == app.id } ?? 0
        let tint = PPG.girl(idx)

        return Button {
            withAnimation(.spring(response: 0.26, dampingFraction: 0.75)) {
                selectedAppID = app.id
            }
        } label: {
            HStack(spacing: 10) {
                AppIconView(url: app.bundleURL, size: 30)

                VStack(alignment: .leading, spacing: 3) {
                    Text(app.name)
                        .font(.ppg(13.5, isSel ? .black : .bold))
                        .foregroundStyle(PPG.ink)
                        .lineLimit(1)

                    if app.residueSize > 0 {
                        ComicBadge(text: "残留 \(Fmt.size(app.residueSize))",
                                   tint: PPG.sunny, icon: "shippingbox.fill")
                    } else {
                        ComicBadge(text: "无残留", tint: PPG.cream,
                                   icon: "checkmark", outlined: true)
                    }
                }

                Spacer(minLength: 6)

                Text(Fmt.size(app.totalSize))
                    .font(.ppg(12.5, .heavy))
                    .foregroundStyle(PPG.ink.opacity(0.7))
                    .monospacedDigit()
            }
            .padding(.horizontal, 9)
            .padding(.vertical, 9)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                // 选中态：主角色填充 + 黑描边 + 硬阴影
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

    // MARK: - 右侧详情

    @ViewBuilder
    private var detailPane: some View {
        if let app = selectedApp {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    detailHeader(app)

                    bundleSection(app)
                    residueSection(app)

                    limitationsNote
                }
                .padding(18)
            }
        } else {
            ComicEmptyState(
                icon: "hand.point.left.fill",
                title: "从左侧选择一个应用",
                message: "选中后可查看它的本体与残留明细",
                tint: PPG.grape
            )
            .padding(20)
        }
    }

    private func detailHeader(_ app: AppInventory.InstalledApp) -> some View {
        HStack(spacing: 14) {
            AppIconView(url: app.bundleURL, size: 56)

            VStack(alignment: .leading, spacing: 4) {
                Text(app.name)
                    .font(.ppg(20, .black))
                    .foregroundStyle(PPG.ink)
                Text(app.bundleID)
                    .font(.ppg(11.5, .semibold))
                    .foregroundStyle(PPG.ink.opacity(0.55))
                    .textSelection(.enabled)
                    .lineLimit(1)
                    .truncationMode(.middle)
                ComicBadge(text: "版本 \(app.version)", tint: PPG.bubbles, icon: "tag.fill")
            }

            Spacer(minLength: 8)
        }
        .comicCard(tint: PPG.grape, padding: 16)
    }

    private func bundleSection(_ app: AppInventory.InstalledApp) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionTitle("应用本体", icon: "app.dashed", detail: Fmt.size(app.bundleSize))

            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top, spacing: 9) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.ppg(13, .black))
                        .foregroundStyle(PPG.danger)
                    Text("删除后该应用将无法使用，需要重新下载安装")
                        .font(.ppgBody)
                        .foregroundStyle(PPG.ink.opacity(0.65))
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 8)
                }

                HStack(spacing: 10) {
                    Spacer(minLength: 0)

                    Button {
                        confirmPayload = ConfirmPayload(
                            items: [inventory.bundleItem(appIndex: indexOf(app))].compactMap { $0 },
                            title: "卸载「\(app.name)」？",
                            message: "将把应用本体移入废纸篓（\(Fmt.size(app.bundleSize))）。\n如需彻底清理，请同时勾选下方的残留项。"
                        )
                    } label: {
                        Label("仅卸载本体", systemImage: "trash.fill")
                    }
                    .buttonStyle(ComicButtonStyle(tint: PPG.dangerDeep, size: .regular,
                                                  textColor: .white))

                    Button {
                        var items: [CleanupItem] = []
                        if let b = inventory.bundleItem(appIndex: indexOf(app)) { items.append(b) }
                        inventory.selectAllResidues(appIndex: indexOf(app))
                        items.append(contentsOf: inventory.selectedResidueItems().filter { item in
                            app.residues.contains { $0.url == item.url }
                        })
                        confirmPayload = ConfirmPayload(
                            items: items,
                            title: "彻底卸载「\(app.name)」？",
                            message: "将把应用本体（\(Fmt.size(app.bundleSize))）与 \(app.residues.count) 项残留（\(Fmt.size(app.residueSize))）一起移入废纸篓。\n共释放约 \(Fmt.size(app.totalSize))。"
                        )
                    } label: {
                        Label("彻底卸载", systemImage: "trash.slash.fill")
                    }
                    .buttonStyle(ComicButtonStyle(tint: PPG.dangerDeep, size: .large,
                                                  textColor: .white))

                    Button {
                        NSWorkspace.shared.activateFileViewerSelecting([app.bundleURL])
                    } label: {
                        Image(systemName: "folder.fill")
                    }
                    .buttonStyle(ComicIconButtonStyle(tint: PPG.sunny, diameter: 42))
                    .help("在访达中显示")
                }
            }
            .comicCard(tint: PPG.danger, padding: 14)
        }
    }

    private func residueSection(_ app: AppInventory.InstalledApp) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                sectionTitle("残留文件", icon: "shippingbox", detail: Fmt.size(app.residueSize))

                if !app.residues.isEmpty {
                    Button("全选") { inventory.selectAllResidues(appIndex: indexOf(app)) }
                        .buttonStyle(ComicButtonStyle(tint: PPG.buttercup, size: .regular,
                                                      burst: false))
                    Button("全不选") { inventory.selectNothing(appIndex: indexOf(app)) }
                        .buttonStyle(ComicButtonStyle(tint: PPG.cream, size: .regular,
                                                      burst: false, outlined: true))
                }
            }

            if app.residues.isEmpty {
                Text("未发现该应用的残留文件")
                    .font(.ppgBody)
                    .foregroundStyle(PPG.ink.opacity(0.45))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .comicCard(tint: PPG.grape, padding: 0)
            } else {
                VStack(spacing: 3) {
                    ForEach(Array(app.residues.enumerated()), id: \.element.id) { ri, residue in
                        residueRow(appIndex: indexOf(app), ri: ri, residue: residue)
                    }
                }
                .comicCard(tint: PPG.buttercup, padding: 8)

                HStack {
                    Spacer()
                    Button {
                        confirmPayload = ConfirmPayload(
                            items: inventory.selectedResidueItems().filter { item in
                                app.residues.contains { $0.url == item.url }
                            },
                            title: "清理「\(app.name)」的残留？",
                            message: "将把 \(inventory.selectedCount) 项残留移入废纸篓。\n应用本体保留，仍可正常使用。"
                        )
                    } label: {
                        Label("清理勾选的残留", systemImage: "trash.fill")
                    }
                    .buttonStyle(ComicButtonStyle(tint: PPG.dangerDeep, size: .regular,
                                                  textColor: .white))
                    .disabled(inventory.selectedCount == 0)
                }
            }
        }
    }

    private func residueRow(
        appIndex: Int,
        ri: Int,
        residue: AppInventory.Residue
    ) -> some View {
        // 按行号循环取主角色，不用 hashValue
        let tint = PPG.girl(ri)

        return HStack(spacing: 11) {
            ComicCheckbox(isOn: residue.isSelected, tint: tint) {
                inventory.toggle(appIndex: appIndex, residueIndex: ri)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(residue.url.lastPathComponent)
                    .font(.ppg(13, .bold))
                    .foregroundStyle(PPG.ink)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text("~/Library/\(residue.kind)")
                    .font(.ppg(10.5, .medium))
                    .foregroundStyle(PPG.ink.opacity(0.45))
            }

            Spacer(minLength: 6)

            Text(Fmt.size(residue.size))
                .font(.ppg(12.5, .heavy))
                .foregroundStyle(PPG.ink)
                .monospacedDigit()

            Button {
                NSWorkspace.shared.activateFileViewerSelecting([residue.url])
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
                .fill(residue.isSelected ? tint.opacity(0.2) : PPG.ink.opacity(0.04))
        }
        // 整行可点：命中区从勾选框扩大到整行
        .contentShape(Rectangle())
        .onTapGesture {
            inventory.toggle(appIndex: appIndex, residueIndex: ri)
        }
    }

    private var limitationsNote: some View {
        VStack(alignment: .leading, spacing: 8) {
            ComicSectionHeader("未纳入清理范围", icon: "info.circle", tint: PPG.sunny)

            Text("• ~/Library/Containers 与 Group Containers 中的沙盒数据未开放清理 —— 该目录同时存放系统组件数据，误删风险高。\n• 应用可能在其他位置留有数据，本工具只能识别 ~/Library 下的常见残留位置。")
                .font(.ppgCaption)
                .foregroundStyle(PPG.ink.opacity(0.6))
                .fixedSize(horizontal: false, vertical: true)

            if inventory.skippedDirCount > 0 {
                Text("• 有 \(inventory.skippedDirCount) 个目录因权限无法读取（可在「系统设置 → 隐私与安全性 → 完全磁盘访问权限」中授权后重试）。")
                    .font(.ppgCaption)
                    .foregroundStyle(PPG.danger)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .comicCard(tint: PPG.sunny, padding: 14)
    }

    private func sectionTitle(_ text: String, icon: String, detail: String) -> some View {
        ComicSectionHeader(
            text, icon: icon, tint: PPG.buttercup,
            trailing: AnyView(
                Text(detail)
                    .font(.ppg(13, .heavy))
                    .foregroundStyle(PPG.ink)
                    .monospacedDigit()
            )
        )
    }

    private func indexOf(_ app: AppInventory.InstalledApp) -> Int {
        inventory.apps.firstIndex { $0.id == app.id } ?? 0
    }
}

/// 取应用图标。取不到时退回通用图标。
private struct AppIconView: View {
    let url: URL
    var size: CGFloat = 28

    var body: some View {
        Group {
            if let icon = NSWorkspace.shared.icon(forFile: url.path) as NSImage? {
                Image(nsImage: icon)
                    .resizable()
                    .interpolation(.high)
            } else {
                Image(systemName: "app.dashed")
                    .resizable()
                    .foregroundStyle(PPG.ink.opacity(0.45))
            }
        }
        .frame(width: size, height: size)
    }
}
