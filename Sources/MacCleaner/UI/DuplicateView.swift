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
            Divider().overlay(PPG.ink.opacity(0.18))

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
        VStack(spacing: 0) {
            ComicSectionHeader(
                "重复文件查找", icon: "doc.on.doc", tint: PPG.bubbles,
                trailing: AnyView(
                    HStack(spacing: 10) {
                        if finder.isScanning {
                            Button("取消") { finder.cancel() }
                                .buttonStyle(ComicButtonStyle(tint: PPG.dangerDeep, size: .regular,
                                                              textColor: .white))
                        } else {
                            Button {
                                finder.startScan()
                            } label: {
                                Label(finder.hasScanned ? "重新扫描" : "开始扫描",
                                      systemImage: "magnifyingglass")
                            }
                            .keyboardShortcut("r", modifiers: .command)
                            .buttonStyle(ComicButtonStyle(tint: PPG.sunny, size: .regular))
                        }
                    }
                )
            )
            .padding(.horizontal, 18)
            .padding(.top, 14)

            Text("按内容哈希比对，找出完全相同的文件")
                .font(.ppgBody)
                .foregroundStyle(PPG.ink.opacity(0.6))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 18)
                .padding(.top, 5)

            scopeBar
                .padding(.horizontal, 18)
                .padding(.top, 11)
                .padding(.bottom, 13)
        }
        .background {
            PPG.cream.opacity(0.75)
                .overlay(alignment: .bottom) {
                    Rectangle().fill(PPG.ink.opacity(0.18)).frame(height: 1.5)
                }
        }
    }

    private var scanScopeChips: [String] {
        ["下载", "文档", "桌面", "图片", "影片", "音乐"]
    }

    private var scopeBar: some View {
        HStack(spacing: 8) {
            Text("扫描范围")
                .font(.ppg(12.5, .bold))
                .foregroundStyle(PPG.ink.opacity(0.55))

            ForEach(scanScopeChips, id: \.self) { name in
                scopeChip(name)
            }

            Spacer(minLength: 12)

            Text("跳过小于 1 MB 的文件")
                .font(.ppgCaption)
                .foregroundStyle(PPG.ink.opacity(0.45))
        }
    }

    private func scopeChip(_ name: String) -> some View {
        let home = NSHomeDirectory()
        let url = URL(fileURLWithPath: "\(home)/\(englishName(name))")
        let on = finder.roots.contains(url)
        // 用固定顺序取色，不用 hashValue —— hash 每进程随机加盐，
        // 重启后同一范围的配色会错位。
        let tint = PPG.girl(scanScopeChips.firstIndex(of: name) ?? 0)

        return Button {
            if on {
                // 至少保留一个范围，否则扫描没有意义
                guard finder.roots.count > 1 else { return }
                finder.roots.removeAll { $0 == url }
            } else {
                finder.roots.append(url)
            }
        } label: {
            HStack(spacing: 5) {
                Image(systemName: on ? "checkmark" : "plus")
                    .font(.ppg(11, .black))
                Text(name)
            }
        }
        // 选中 = 实心主角色，未选 = 奶油底描边款。两者都是 42pt 高，好点。
        .buttonStyle(ComicButtonStyle(tint: on ? tint : PPG.cream, size: .regular,
                                      burst: false, outlined: !on))
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
        VStack(spacing: 0) {
            VStack(spacing: 16) {
                HStack(spacing: 10) {
                    Image(systemName: "sparkles")
                        .font(.ppg(20, .black))
                        .foregroundStyle(PPG.blossom)
                    Text(finder.progressText.isEmpty ? "正在扫描…" : finder.progressText)
                        .font(.ppg(20, .black))
                        .foregroundStyle(PPG.ink)
                        .lineLimit(1)
                    Spacer(minLength: 10)
                    Text("\(Int(finder.progressValue * 100))%")
                        .font(.ppg(20, .black))
                        .foregroundStyle(PPG.ink.opacity(0.5))
                        .monospacedDigit()
                }

                ComicProgressBar(value: finder.progressValue,
                                 tint: PPG.blossom, height: 20, striped: true)

                Text("先按体积初筛，再做内容哈希 —— 只有真正相同的文件才会被列出")
                    .font(.ppgBody)
                    .foregroundStyle(PPG.ink.opacity(0.6))
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .comicCard(tint: PPG.blossom, padding: 22)
            .frame(maxWidth: 620)

            Spacer(minLength: 0)
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    private var emptyState: some View {
        ComicEmptyState(
            icon: "doc.on.doc",
            title: "还没有扫描过",
            message: "点击右上角「开始扫描」，在 \(finder.roots.count) 个位置查找内容相同的文件",
            tint: PPG.bubbles,
            action: (title: "开始扫描", handler: { finder.startScan() })
        )
        .padding(20)
    }

    private var noResultState: some View {
        ComicEmptyState(
            icon: "checkmark.circle",
            title: "未发现重复文件",
            message: "扫描范围内没有内容完全相同的文件（已跳过 1 MB 以下的）",
            tint: PPG.buttercup
        )
        .padding(20)
    }

    // MARK: - 结果列表

    private var resultList: some View {
        VStack(spacing: 0) {
            summaryBar
                .padding(16)

            ScrollView {
                LazyVStack(spacing: 12) {
                    ForEach(Array(finder.groups.enumerated()), id: \.element.id) { gi, group in
                        groupCard(gi: gi, group: group)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 18)
            }
        }
    }

    private var summaryBar: some View {
        HStack(spacing: 10) {
            ComicBadge(text: "\(finder.groups.count) 组重复",
                       tint: PPG.grape, icon: "square.stack.3d.up.fill")

            ComicBadge(text: "可回收 \(Fmt.size(finder.groups.reduce(0) { $0 + $1.reclaimable }))",
                       tint: PPG.sunny, icon: "arrow.down.circle.fill")

            if finder.selectedCount > 0 {
                ComicBadge(text: "已选 \(finder.selectedCount) 项 · \(Fmt.size(finder.selectedSize))",
                           tint: PPG.blossom, icon: "checkmark.circle.fill")
            }

            Spacer(minLength: 8)

            // 批量勾选：这是唯一会批量选中删除项的地方，规则明确写在菜单项上。
            // 用 ComicMenuStyle 而非 buttonStyle —— macOS 上 Menu 只认 MenuStyle，
            // 套 ButtonStyle 会被忽略并退化成裸系统控件（已实测，见 PPGControls）。
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
            .menuStyle(ComicMenuStyle(tint: PPG.bubbles, size: .regular))

            Button {
                showCleanConfirm = true
            } label: {
                Label("清理所选", systemImage: "trash.fill")
            }
            .buttonStyle(ComicButtonStyle(tint: PPG.dangerDeep, size: .regular,
                                          textColor: .white))
            .disabled(finder.selectedCount == 0)
        }
        .comicCard(tint: PPG.bubbles, padding: 12)
    }

    private func groupCard(gi: Int, group: DuplicateFinder.DuplicateGroup) -> some View {
        let expanded = expandedGroups.contains(group.id)
        // 按组在列表里的固定序号循环取主角色，不用 hashValue
        let tint = PPG.girl(gi)

        return VStack(spacing: 0) {
            // 组头：整行可点，用来展开 / 收起
            HStack(spacing: 11) {
                Image(systemName: expanded ? "chevron.down" : "chevron.right")
                    .font(.ppg(11, .black))
                    .foregroundStyle(PPG.ink)
                    .frame(width: 14)

                ZStack {
                    Circle()
                        .fill(tint)
                        .overlay { Circle().strokeBorder(PPG.ink, lineWidth: 1.8) }
                        .frame(width: 28, height: 28)
                    Image(systemName: "square.on.square")
                        .font(.ppg(12.5, .black))
                        .foregroundStyle(PPG.ink)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text("\(group.files.count) 个相同文件 · 每个 \(Fmt.size(group.size))")
                        .font(.ppg(13.5, .heavy))
                        .foregroundStyle(PPG.ink)
                    Text(group.files[0].name)
                        .font(.ppg(11, .medium))
                        .foregroundStyle(PPG.ink.opacity(0.5))
                        .lineLimit(1)
                        .truncationMode(.middle)
                }

                Spacer(minLength: 8)

                ComicBadge(text: "可回收 \(Fmt.size(group.reclaimable))",
                           tint: PPG.sunny, icon: "arrow.down.circle.fill")

                Button("仅看此组") {
                    finder.clearSelection()
                    selectAllButFirst(gi: gi)
                }
                .buttonStyle(ComicButtonStyle(tint: tint, size: .regular, burst: false))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .frame(minHeight: 52)
            .background {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(tint.opacity(expanded ? 0.26 : 0.14))
            }
            .contentShape(Rectangle())
            .onTapGesture {
                if expanded { expandedGroups.remove(group.id) }
                else { expandedGroups.insert(group.id) }
            }

            if expanded {
                Rectangle()
                    .fill(PPG.ink.opacity(0.16))
                    .frame(height: 1.5)
                    .padding(.horizontal, 10)

                VStack(spacing: 3) {
                    ForEach(Array(group.files.enumerated()), id: \.element.id) { fi, file in
                        fileRow(gi: gi, fi: fi, file: file, isFirst: fi == 0)
                    }
                }
                .padding(.top, 7)
                .padding(.bottom, 4)
                .padding(.horizontal, 6)
            }
        }
        .comicCard(tint: tint, padding: 0)
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
        // 与所属组同一主角色配色，序号仍然来自列表位置而非 hashValue
        let tint = PPG.girl(gi)

        return HStack(spacing: 11) {
            ComicCheckbox(isOn: file.isSelected,
                          tint: isFirst ? PPG.buttercup : tint) {
                finder.toggle(groupIndex: gi, fileIndex: fi)
            }

            Image(systemName: iconFor(file.url))
                .font(.ppg(13, .black))
                .foregroundStyle(isFirst ? PPG.ink : PPG.ink.opacity(0.5))
                .frame(width: 20)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(file.name)
                        .font(.ppg(13, .bold))
                        .foregroundStyle(PPG.ink)
                        .lineLimit(1)
                    if isFirst {
                        ComicBadge(text: "保留", tint: PPG.buttercup, icon: "lock.fill")
                    }
                }
                Text(file.parentPath)
                    .font(.ppg(10.5, .medium))
                    .foregroundStyle(PPG.ink.opacity(0.45))
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Spacer(minLength: 6)

            Text(file.modified.formatted(date: .numeric, time: .omitted))
                .font(.ppgCaption)
                .foregroundStyle(PPG.ink.opacity(0.45))
                .monospacedDigit()

            Button {
                NSWorkspace.shared.activateFileViewerSelecting([file.url])
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
                .fill(file.isSelected ? tint.opacity(0.2) : PPG.ink.opacity(0.04))
        }
        // 整行可点：命中区从 26pt 的勾选框扩大到整行
        .contentShape(Rectangle())
        .onTapGesture {
            finder.toggle(groupIndex: gi, fileIndex: fi)
        }
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
