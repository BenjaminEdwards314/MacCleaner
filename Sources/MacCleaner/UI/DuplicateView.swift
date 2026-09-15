import SwiftUI

/// 重复文件查找视图。
///
/// 交互设计的两条硬规则：
/// 1. **默认一个都不勾选** —— 「重复」是内容判断，但用户可能刻意在不同位置
///    保留同一份文件（如两个项目目录下的同一份素材）。
/// 2. **每组必须保留一份** —— 批量勾选按钮只会勾选「除保留项之外的副本」，
///    不存在把一组全部删空的路径。
struct DuplicateView: View {
    @ObservedObject var finder: DuplicateFinder
    /// 执行清理的回调，由 ContentView 统一处理（复用清理引擎与结果弹窗）
    let onClean: ([CleanupItem]) -> Void

    @State private var keepPolicy: DuplicateFinder.KeepPolicy = .oldest
    @State private var showCleanConfirm = false
    @State private var expandedGroups: Set<UUID> = []

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider()

            if finder.isScanning {
                scanningState
            } else if !finder.hasScanned {
                emptyState
            } else if finder.groups.isEmpty {
                noResultState
            } else {
                resultList
            }
        }
        .alert("确认清理重复文件？", isPresented: $showCleanConfirm) {
            Button("取消", role: .cancel) {}
            Button("移入废纸篓", role: .destructive) {
                onClean(finder.selectedItems())
            }
        } message: {
            Text("将把 \(finder.selectedCount) 个文件移入废纸篓，可释放 \(Fmt.size(finder.selectedSize))。\n每组至少保留了一份，删除后仍可从废纸篓恢复。")
        }
    }

    // MARK: - 顶部工具栏

    private var toolbar: some View {
        VStack(spacing: 10) {
            HStack(spacing: 12) {
                Image(systemName: "doc.on.doc")
                    .font(.title2)
                    .foregroundStyle(.blue)

                VStack(alignment: .leading, spacing: 2) {
                    Text("重复文件查找")
                        .font(.headline)
                    Text("按内容哈希比对，找出完全相同的文件")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                if finder.isScanning {
                    Button("取消") { finder.cancel() }
                } else {
                    Button {
                        finder.startScan()
                    } label: {
                        Label(finder.hasScanned ? "重新扫描" : "开始扫描", systemImage: "magnifyingglass")
                    }
                    .keyboardShortcut("r", modifiers: .command)
                    .buttonStyle(.borderedProminent)
                }
            }

            HStack(spacing: 8) {
                Text("扫描范围")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                ForEach(scanScopeChips, id: \.self) { name in
                    scopeChip(name)
                }

                Spacer()

                Text("跳过小于 1 MB 的文件")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
    }

    private var scanScopeChips: [String] {
        ["下载", "文档", "桌面", "图片", "影片", "音乐"]
    }

    private func scopeChip(_ name: String) -> some View {
        let home = NSHomeDirectory()
        let url = URL(fileURLWithPath: "\(home)/\(englishName(name))")
        let on = finder.roots.contains(url)

        return Button {
            if on {
                // 至少保留一个范围，否则扫描没有意义
                guard finder.roots.count > 1 else { return }
                finder.roots.removeAll { $0 == url }
            } else {
                finder.roots.append(url)
            }
        } label: {
            Text(name)
                .font(.caption)
                .padding(.horizontal, 9)
                .padding(.vertical, 4)
                .background(
                    on ? Color.accentColor.opacity(0.18) : Color.secondary.opacity(0.10),
                    in: Capsule()
                )
                .foregroundStyle(on ? Color.accentColor : .secondary)
        }
        .buttonStyle(.plain)
        .help(on ? "点击移出扫描范围" : "点击加入扫描范围")
    }

    private func englishName(_ cn: String) -> String {
        switch cn {
        case "下载": return "Downloads"
        case "文档": return "Documents"
        case "桌面": return "Desktop"
        case "图片": return "Pictures"
        case "影片": return "Movies"
        default: return "Music"
        }
    }

    // MARK: - 各状态

    private var scanningState: some View {
        VStack(spacing: 14) {
            ProgressView()
                .controlSize(.large)
            Text(finder.progressText.isEmpty ? "正在扫描…" : finder.progressText)
                .font(.callout)
                .foregroundStyle(.secondary)
            ProgressView(value: finder.progressValue)
                .frame(width: 320)
            Text("先按体积初筛，再做内容哈希 —— 只有真正相同的文件才会被列出")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "doc.on.doc")
                .font(.system(size: 44))
                .foregroundStyle(.tertiary)
            Text("还没有扫描过")
                .font(.title3)
            Text("点击右上角「开始扫描」，在 \(finder.roots.count) 个位置查找内容相同的文件")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var noResultState: some View {
        VStack(spacing: 12) {
            Image(systemName: "checkmark.circle")
                .font(.system(size: 44))
                .foregroundStyle(.green)
            Text("未发现重复文件")
                .font(.title3)
            Text("扫描范围内没有内容完全相同的文件（已跳过 1 MB 以下的）")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - 结果列表

    private var resultList: some View {
        VStack(spacing: 0) {
            summaryBar
            Divider()

            ScrollView {
                LazyVStack(spacing: 10) {
                    ForEach(Array(finder.groups.enumerated()), id: \.element.id) { gi, group in
                        groupCard(gi: gi, group: group)
                    }
                }
                .padding(16)
            }
        }
    }

    private var summaryBar: some View {
        HStack(spacing: 16) {
            Label("\(finder.groups.count) 组重复", systemImage: "square.stack.3d.up")
                .font(.callout)

            Text("可回收 \(Fmt.size(finder.groups.reduce(0) { $0 + $1.reclaimable }))")
                .font(.callout)
                .foregroundStyle(.orange)

            if finder.selectedCount > 0 {
                Text("已选 \(finder.selectedCount) 项 · \(Fmt.size(finder.selectedSize))")
                    .font(.callout)
                    .foregroundStyle(.blue)
            }

            Spacer()

            // 批量勾选：这是唯一会批量选中删除项的地方，规则明确写在按钮上
            Menu {
                ForEach(DuplicateFinder.KeepPolicy.allCases) { p in
                    Button("每组\(p.title)，其余勾选删除") {
                        keepPolicy = p
                        finder.selectDuplicates(keeping: p)
                    }
                }
                Divider()
                Button("清空所有勾选") { finder.clearSelection() }
            } label: {
                Label("批量勾选", systemImage: "checklist")
            }
            .frame(width: 130)

            Button {
                showCleanConfirm = true
            } label: {
                Label("清理所选", systemImage: "trash")
            }
            .buttonStyle(.borderedProminent)
            .tint(.red)
            .disabled(finder.selectedCount == 0)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 10)
    }

    private func groupCard(gi: Int, group: DuplicateFinder.DuplicateGroup) -> some View {
        let expanded = expandedGroups.contains(group.id)

        return VStack(spacing: 0) {
            // 组头
            HStack(spacing: 10) {
                Button {
                    if expanded { expandedGroups.remove(group.id) }
                    else { expandedGroups.insert(group.id) }
                } label: {
                    Image(systemName: expanded ? "chevron.down" : "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: 14)
                }
                .buttonStyle(.plain)

                Image(systemName: "square.on.square")
                    .foregroundStyle(.blue)

                VStack(alignment: .leading, spacing: 2) {
                    Text("\(group.files.count) 个相同文件 · 每个 \(Fmt.size(group.size))")
                        .font(.callout.weight(.medium))
                    Text(group.files[0].name)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer()

                Text("可回收 \(Fmt.size(group.reclaimable))")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.orange)
                    .monospacedDigit()

                Button("仅看此组") {
                    finder.clearSelection()
                    selectAllButFirst(gi: gi)
                }
                .font(.caption)
                .buttonStyle(.link)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .contentShape(Rectangle())
            .onTapGesture {
                if expanded { expandedGroups.remove(group.id) }
                else { expandedGroups.insert(group.id) }
            }

            if expanded {
                Divider()
                VStack(spacing: 0) {
                    ForEach(Array(group.files.enumerated()), id: \.element.id) { fi, file in
                        fileRow(gi: gi, fi: fi, file: file, isFirst: fi == 0)
                        if fi != group.files.count - 1 {
                            Divider().padding(.leading, 42)
                        }
                    }
                }
            }
        }
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(Color.secondary.opacity(0.15), lineWidth: 1)
        )
    }

    /// 勾选本组除第一个之外的所有副本
    private func selectAllButFirst(gi: Int) {
        guard finder.groups.indices.contains(gi) else { return }
        let group = finder.groups[gi]
        for fi in group.files.indices where fi != 0 {
            finder.toggle(groupIndex: gi, fileIndex: fi)
        }
    }

    private func fileRow(
        gi: Int, fi: Int,
        file: DuplicateFinder.FileEntry,
        isFirst: Bool
    ) -> some View {
        HStack(spacing: 10) {
            Toggle("", isOn: Binding(
                get: { file.isSelected },
                set: { _ in finder.toggle(groupIndex: gi, fileIndex: fi) }
            ))
            .labelsHidden()
            .toggleStyle(.checkbox)

            Image(systemName: iconFor(file.url))
                .foregroundStyle(isFirst ? Color.green : Color.secondary)
                .frame(width: 18)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(file.name)
                        .font(.callout)
                        .lineLimit(1)
                    if isFirst {
                        Text("保留")
                            .font(.caption2.weight(.semibold))
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(Color.green.opacity(0.18), in: Capsule())
                            .foregroundStyle(.green)
                    }
                }
                Text(file.parentPath)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Spacer()

            Text(file.modified.formatted(date: .numeric, time: .omitted))
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .monospacedDigit()

            Button {
                NSWorkspace.shared.activateFileViewerSelecting([file.url])
            } label: {
                Image(systemName: "folder")
                    .font(.caption)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .help("在访达中显示")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 7)
    }

    /// 按扩展名给个图标，纯装饰
    private func iconFor(_ url: URL) -> String {
        switch url.pathExtension.lowercased() {
        case "png", "jpg", "jpeg", "heic", "gif", "webp", "tiff": return "photo"
        case "mp4", "mov", "avi", "mkv": return "film"
        case "mp3", "m4a", "wav", "flac": return "music.note"
        case "pdf": return "doc.richtext"
        case "zip", "rar", "7z", "dmg", "pkg": return "shippingbox"
        case "swift", "js", "ts", "py", "rs", "go", "java": return "chevron.left.forwardslash.chevron.right"
        default: return "doc"
        }
    }
}
