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
            Divider()

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
        HStack(spacing: 12) {
            Image(systemName: "shippingbox")
                .font(.title2)
                .foregroundStyle(.purple)

            VStack(alignment: .leading, spacing: 2) {
                Text("应用卸载")
                    .font(.headline)
                Text("删除应用本体，并清理它在 ~/Library 里的残留")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if inventory.hasScanned {
                TextField("搜索应用", text: $searchText)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 160)
            }

            if inventory.isScanning {
                Button("取消") { inventory.cancel() }
            } else {
                Button {
                    inventory.startScan()
                } label: {
                    Label(inventory.hasScanned ? "重新扫描" : "开始扫描", systemImage: "arrow.clockwise")
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
    }

    // MARK: - 状态

    private var scanningState: some View {
        VStack(spacing: 14) {
            ProgressView().controlSize(.large)
            Text(inventory.progressText.isEmpty ? "正在扫描…" : inventory.progressText)
                .font(.callout)
                .foregroundStyle(.secondary)
            Text("只列举 ~/Library 各目录的一层内容来匹配残留，不递归遍历")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "shippingbox")
                .font(.system(size: 44))
                .foregroundStyle(.tertiary)
            Text("还没有扫描过")
                .font(.title3)
            Text("点击「开始扫描」列出已安装的应用及其残留")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var noAppsState: some View {
        VStack(spacing: 12) {
            Image(systemName: "questionmark.folder")
                .font(.system(size: 44))
                .foregroundStyle(.tertiary)
            Text("未找到可卸载的应用")
                .font(.title3)
            Text("系统自带应用不在此列出")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - 左侧应用列表

    private var appList: some View {
        List(selection: $selectedAppID) {
            ForEach(filteredApps) { app in
                HStack(spacing: 10) {
                    AppIconView(url: app.bundleURL)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(app.name)
                            .font(.callout.weight(.medium))
                            .lineLimit(1)
                        HStack(spacing: 5) {
                            if app.residueSize > 0 {
                                Text("残留 \(Fmt.size(app.residueSize))")
                                    .font(.caption2)
                                    .foregroundStyle(.orange)
                            } else {
                                Text("无残留")
                                    .font(.caption2)
                                    .foregroundStyle(.tertiary)
                            }
                        }
                    }

                    Spacer()

                    Text(Fmt.size(app.totalSize))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
                .tag(app.id)
                .padding(.vertical, 2)
            }
        }
        .listStyle(.sidebar)
    }

    // MARK: - 右侧详情

    @ViewBuilder
    private var detailPane: some View {
        if let app = selectedApp {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    detailHeader(app)

                    bundleSection(app)
                    residueSection(app)

                    limitationsNote
                }
                .padding(18)
            }
        } else {
            VStack {
                Text("从左侧选择一个应用")
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func detailHeader(_ app: AppInventory.InstalledApp) -> some View {
        HStack(spacing: 14) {
            AppIconView(url: app.bundleURL, size: 56)

            VStack(alignment: .leading, spacing: 4) {
                Text(app.name)
                    .font(.title3.weight(.semibold))
                Text(app.bundleID)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                Text("版本 \(app.version)")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }

            Spacer()
        }
    }

    private func bundleSection(_ app: AppInventory.InstalledApp) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionTitle("应用本体", icon: "app.dashed", detail: Fmt.size(app.bundleSize))

            HStack(spacing: 10) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                Text("删除后该应用将无法使用，需要重新下载安装")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()

                Button {
                    confirmPayload = ConfirmPayload(
                        items: [inventory.bundleItem(appIndex: indexOf(app))].compactMap { $0 },
                        title: "卸载「\(app.name)」？",
                        message: "将把应用本体移入废纸篓（\(Fmt.size(app.bundleSize))）。\n如需彻底清理，请同时勾选下方的残留项。"
                    )
                } label: {
                    Label("仅卸载本体", systemImage: "trash")
                }
                .tint(.red)

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
                    Label("彻底卸载", systemImage: "trash.slash")
                }
                .buttonStyle(.borderedProminent)
                .tint(.red)

                Button {
                    NSWorkspace.shared.activateFileViewerSelecting([app.bundleURL])
                } label: {
                    Image(systemName: "folder")
                }
                .help("在访达中显示")
            }
            .padding(12)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
        }
    }

    private func residueSection(_ app: AppInventory.InstalledApp) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                sectionTitle("残留文件", icon: "shippingbox", detail: Fmt.size(app.residueSize))
                Spacer()
                if !app.residues.isEmpty {
                    Button("全选") { inventory.selectAllResidues(appIndex: indexOf(app)) }
                        .font(.caption)
                    Button("全不选") { inventory.selectNothing(appIndex: indexOf(app)) }
                        .font(.caption)
                }
            }

            if app.residues.isEmpty {
                Text("未发现该应用的残留文件")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .padding(.vertical, 8)
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(app.residues.enumerated()), id: \.element.id) { ri, residue in
                        residueRow(appIndex: indexOf(app), ri: ri, residue: residue)
                        if ri != app.residues.count - 1 {
                            Divider().padding(.leading, 34)
                        }
                    }
                }
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))

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
                        Label("清理勾选的残留", systemImage: "trash")
                    }
                    .tint(.orange)
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
        HStack(spacing: 10) {
            Toggle("", isOn: Binding(
                get: { residue.isSelected },
                set: { _ in inventory.toggle(appIndex: appIndex, residueIndex: ri) }
            ))
            .labelsHidden()
            .toggleStyle(.checkbox)

            VStack(alignment: .leading, spacing: 2) {
                Text(residue.url.lastPathComponent)
                    .font(.callout)
                    .lineLimit(1)
                Text("~/Library/\(residue.kind)")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }

            Spacer()

            Text(Fmt.size(residue.size))
                .font(.caption)
                .foregroundStyle(.secondary)
                .monospacedDigit()

            Button {
                NSWorkspace.shared.activateFileViewerSelecting([residue.url])
            } label: {
                Image(systemName: "folder").font(.caption)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
    }

    private var limitationsNote: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("未纳入清理范围", systemImage: "info.circle")
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
            Text("• ~/Library/Containers 与 Group Containers 中的沙盒数据未开放清理 —— 该目录同时存放系统组件数据，误删风险高。\n• 应用可能在其他位置留有数据，本工具只能识别 ~/Library 下的常见残留位置。")
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)

            if inventory.skippedDirCount > 0 {
                Text("• 有 \(inventory.skippedDirCount) 个目录因权限无法读取（可在「系统设置 → 隐私与安全性 → 完全磁盘访问权限」中授权后重试）。")
                    .font(.caption2)
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(12)
        .background(Color.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 10))
    }

    private func sectionTitle(_ text: String, icon: String, detail: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .foregroundStyle(.secondary)
            Text(text)
                .font(.callout.weight(.semibold))
            Text(detail)
                .font(.caption)
                .foregroundStyle(.secondary)
                .monospacedDigit()
        }
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
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: size, height: size)
    }
}
