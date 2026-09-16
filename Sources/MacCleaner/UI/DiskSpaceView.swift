import SwiftUI
import AppKit

/// 空间视图：面包屑 + 可钻取的目录列表。
///
/// 与清理视图的分工：这里只读地展示「空间去哪了」，
/// 能不能删由 `DiskNode.cleanable`（背后是 SafetyGuard 白名单）决定。
struct DiskSpaceView: View {
    @StateObject private var nav = DiskNavigator()
    @State private var style: Style = .treemap

    enum Style { case treemap, list }

    var body: some View {
        VStack(spacing: 0) {
            rootPicker
            Divider().overlay(PPG.ink.opacity(0.18))
            breadcrumb
            Divider().overlay(PPG.ink.opacity(0.18))

            if nav.isStructuring {
                loadingCard
            } else if let level = nav.level {
                content(level)
            } else {
                placeholder
            }
        }
        .onAppear {
            if nav.current == nil,
               let first = DiskScanner.roots().first(where: { $0.path == NSHomeDirectory() })
                        ?? DiskScanner.roots().first {
                nav.open(first)
            }
        }
    }

    // MARK: - 快速入口

    private var rootPicker: some View {
        let roots = DiskScanner.roots()

        return VStack(alignment: .leading, spacing: 10) {
            // 页面级标题：用主题区块标题替代系统 headline
            ComicSectionHeader("快速入口", icon: "folder.fill", tint: PPG.grape,
                               trailing: AnyView(viewStyleToggle))

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(Array(roots.enumerated()), id: \.element.path) { idx, url in
                        let isCurrent = nav.current?.path == url.path
                        Button {
                            nav.open(url)
                        } label: {
                            Text(shortName(url))
                        }
                        .buttonStyle(ComicButtonStyle(
                            tint: isCurrent ? PPG.girl(idx) : PPG.cream,
                            size: .regular,
                            burst: false,
                            outlined: !isCurrent
                        ))
                    }
                }
                // 给硬阴影留出空间，避免被 ScrollView 裁掉
                .padding(.horizontal, 4)
                .padding(.vertical, 5)
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 12)
        .padding(.bottom, 10)
        .background(PPG.cream.opacity(0.75))
    }

    /// 视图切换：树图看比例，列表看细节（项太多时树图的小块点不中）。
    ///
    /// 原来是 20pt 高的分段控件，命中区太小 —— 换成两个 42pt 的卡通按钮。
    private var viewStyleToggle: some View {
        HStack(spacing: 8) {
            Button {
                style = .treemap
            } label: {
                Image(systemName: "square.grid.3x3.fill")
            }
            .buttonStyle(ComicButtonStyle(
                tint: style == .treemap ? PPG.bubbles : PPG.cream,
                size: .regular,
                burst: false,
                outlined: style != .treemap
            ))
            .help("矩形树图")

            Button {
                style = .list
            } label: {
                Image(systemName: "list.bullet")
            }
            .buttonStyle(ComicButtonStyle(
                tint: style == .list ? PPG.bubbles : PPG.cream,
                size: .regular,
                burst: false,
                outlined: style != .list
            ))
            .help("列表")
        }
    }

    private func shortName(_ url: URL) -> String {
        let home = NSHomeDirectory()
        if url.path == home { return "主目录" }
        if url.path == "/" { return "整盘" }
        if url.path == "/Applications" { return "应用程序" }
        let p = url.path.replacingOccurrences(of: home + "/", with: "")
        return p.replacingOccurrences(of: "Library/", with: "")
    }

    // MARK: - 面包屑

    private var breadcrumb: some View {
        HStack(spacing: 10) {
            Button {
                nav.up()
            } label: {
                Image(systemName: "chevron.up")
            }
            .buttonStyle(ComicIconButtonStyle(tint: PPG.sunny, diameter: 34))
            .disabled(nav.path.count <= 1)
            .help("返回上一层")

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(Array(nav.path.enumerated()), id: \.offset) { idx, url in
                        if idx > 0 {
                            Image(systemName: "chevron.right")
                                .font(.ppg(10, .black))
                                .foregroundStyle(PPG.ink.opacity(0.4))
                        }
                        Button {
                            nav.jump(to: idx)
                        } label: {
                            Text(displayName(url))
                                .lineLimit(1)
                        }
                        .buttonStyle(ComicButtonStyle(
                            tint: idx == nav.path.count - 1 ? PPG.girl(idx) : PPG.cream,
                            size: .regular,
                            burst: false,
                            outlined: idx != nav.path.count - 1
                        ))
                    }
                }
                .padding(.vertical, 5)
            }

            Spacer(minLength: 8)

            // 回填进度：内容已可用，只是数字还在补
            if nav.isMeasuring, let lvl = nav.level {
                HStack(spacing: 8) {
                    ComicProgressBar(
                        value: Double(lvl.measuredCount) / Double(max(lvl.children.count, 1)),
                        tint: PPG.blossom, height: 12, striped: true
                    )
                    .frame(width: 90)

                    ComicBadge(text: "统计中 \(lvl.measuredCount)/\(lvl.children.count)",
                               tint: PPG.blossom, icon: "hourglass")
                }
            } else if let lvl = nav.level, lvl.node.measured {
                Text(Fmt.size(lvl.node.size))
                    .font(.ppg(13.5, .heavy))
                    .foregroundStyle(PPG.ink)
                    .monospacedDigit()
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    private func displayName(_ url: URL) -> String {
        if url.path == "/" { return "整盘" }
        let home = NSHomeDirectory()
        if url.path == home { return "主目录" }
        return url.lastPathComponent
    }

    // MARK: - 内容

    @ViewBuilder
    private func content(_ level: DiskLevel) -> some View {
        switch style {
        case .treemap:
            VStack(spacing: 0) {
                if let err = nav.errorText {
                    permissionBanner(err)
                } else if level.deniedCount > 0 {
                    permissionBanner("此目录下有 \(level.deniedCount) 项因权限不足无法统计，显示的体积偏小。可在「系统设置 → 隐私与安全性 → 完全磁盘访问权限」中授权。")
                }
                if level.skippedPathological {
                    skippedBanner
                }
                TreemapView(level: level, measuring: nav.isMeasuring) { node in
                    nav.drill(into: node)
                }
                // 树图自带白底方角，套一圈粗描边才和其它区块是一套视觉
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .strokeBorder(PPG.ink, lineWidth: 2.5)
                }
                .padding(12)
            }
        case .list:
            listContent(level)
        }
    }

    private func listContent(_ level: DiskLevel) -> some View {
        ScrollView {
            VStack(spacing: 10) {
                if let err = nav.errorText {
                    permissionBanner(err)
                }

                if level.deniedCount > 0 && nav.errorText == nil {
                    permissionBanner("此目录下有 \(level.deniedCount) 项因权限不足无法统计，显示的体积偏小。可在「系统设置 → 隐私与安全性 → 完全磁盘访问权限」中授权。")
                }

                if level.skippedPathological {
                    skippedBanner
                }

                if !level.children.isEmpty {
                    VStack(spacing: 6) {
                        ForEach(level.children) { node in
                            row(node, parentSize: level.node.size)
                        }

                        if level.hiddenCount > 0 {
                            HStack(spacing: 10) {
                                Image(systemName: "ellipsis.circle")
                                    .font(.ppg(13, .black))
                                    .foregroundStyle(PPG.ink.opacity(0.45))
                                Text("其他 \(level.hiddenCount) 项")
                                    .font(.ppg(12.5, .bold))
                                    .foregroundStyle(PPG.ink.opacity(0.6))
                                Spacer()
                                Text(Fmt.size(level.hiddenSize))
                                    .font(.ppg(12.5, .heavy))
                                    .foregroundStyle(PPG.ink.opacity(0.6))
                                    .monospacedDigit()
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 10)
                            .background {
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .fill(PPG.ink.opacity(0.04))
                            }
                        }
                    }
                    .comicCard(tint: PPG.bubbles, padding: 10)
                } else if level.deniedCount == 0 {
                    ComicEmptyState(
                        icon: "folder",
                        title: "此目录为空",
                        message: "这里没有可显示的条目。换一个位置，或返回上一层继续浏览。",
                        tint: PPG.bubbles
                    )
                    .frame(minHeight: 320)
                }
            }
            .padding(16)
        }
    }

    private func row(_ node: DiskNode, parentSize: Int64) -> some View {
        let fraction = parentSize > 0 ? Double(node.size) / Double(parentSize) : 0
        let tint = rowTint(node)

        return HStack(spacing: 11) {
            ZStack {
                Circle()
                    .fill(node.measured ? tint : PPG.cream)
                    .overlay { Circle().strokeBorder(PPG.ink, lineWidth: 1.8) }
                    .frame(width: 30, height: 30)
                Image(systemName: node.isDirectory ? "folder.fill" : "doc.fill")
                    .font(.ppg(12.5, .black))
                    .foregroundStyle(PPG.ink)
            }

            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 6) {
                    Text(node.name)
                        .font(.ppg(13, .bold))
                        .foregroundStyle(PPG.ink)
                        .lineLimit(1)
                    if node.accessDenied {
                        tag("无权限", PPG.sunny)
                    } else if node.cleanable {
                        tag("可清理", PPG.buttercup)
                    }
                }

                // 占比条 —— 比数字更快看出谁是主要占用
                ComicProgressBar(
                    value: node.measured ? fraction : 0,
                    tint: node.measured ? tint : PPG.ink.opacity(0.3),
                    height: 9
                )
                .opacity(node.measured ? 1 : 0.4)
            }
            // 让占比条吃掉整段剩余宽度，而不是和 Spacer 各分一半
            .frame(maxWidth: .infinity, alignment: .leading)

            Spacer(minLength: 8)

            // 未算出的显示占位符 —— 显示「0 字节」会让用户误以为目录是空的
            if node.measured {
                Text(Fmt.size(node.size))
                    .font(.ppg(13, .heavy))
                    .foregroundStyle(PPG.ink)
                    .monospacedDigit()
                    .frame(width: 84, alignment: .trailing)
            } else {
                Text("…")
                    .font(.ppg(13, .bold))
                    .foregroundStyle(PPG.ink.opacity(0.4))
                    .frame(width: 84, alignment: .trailing)
            }

            if node.isDirectory {
                Button {
                    if node.cleanable {
                        NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: node.path)
                    } else {
                        NSWorkspace.shared.selectFile(node.path, inFileViewerRootedAtPath: "")
                    }
                } label: {
                    Image(systemName: "arrow.up.forward.app")
                }
                .buttonStyle(ComicIconButtonStyle(tint: PPG.sunny, diameter: 32))
                .help("在 Finder 中显示")

                Image(systemName: "chevron.right")
                    .font(.ppg(11, .black))
                    .foregroundStyle(PPG.ink.opacity(0.45))
            } else {
                Color.clear.frame(width: 32)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(PPG.ink.opacity(0.035))
        }
        .contentShape(Rectangle())
        .onTapGesture {
            if node.isDirectory { nav.drill(into: node) }
        }
        .contextMenu {
            Button("在 Finder 中显示") {
                NSWorkspace.shared.selectFile(node.path, inFileViewerRootedAtPath: "")
            }
            if node.cleanable {
                Button("复制路径") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(node.path, forType: .string)
                }
            }
        }
    }

    /// 行配色按节点性质固定取色 —— 不能用 hashValue：
    /// Swift 的 hashValue 每个进程随机加盐，重启后颜色会全部错位。
    private func rowTint(_ node: DiskNode) -> Color {
        if node.accessDenied { return PPG.sunny }
        if node.cleanable { return PPG.buttercup }
        return node.isDirectory ? PPG.bubbles : PPG.grape
    }

    private func tag(_ text: String, _ color: Color) -> some View {
        ComicBadge(text: text, tint: color)
    }

    /// 跳过病态目录时**必须明说**。
    /// 静默跳过会让用户看到一个偏小的数字却不知为何 —— 那比慢更糟。
    private var skippedBanner: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "speedometer")
                .font(.ppg(14, .black))
                .foregroundStyle(PPG.grape)
            VStack(alignment: .leading, spacing: 3) {
                Text("为加快扫描，已跳过崩溃转储目录")
                    .font(.ppg(12.5, .heavy))
                    .foregroundStyle(PPG.ink)
                Text("这些目录（如 Codex Crashpad）含数十万个文件，统计它们极慢且均为可清理的死数据。此处显示的体积不含这部分，实际占用会更大。可在「清理」页查看并清理它们。")
                    .font(.ppgCaption)
                    .foregroundStyle(PPG.ink.opacity(0.6))
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .comicCard(tint: PPG.grape, padding: 12)
        .padding(.horizontal, 16)
        .padding(.top, 12)
    }

    private func permissionBanner(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "lock.fill")
                .font(.ppg(14, .black))
                .foregroundStyle(PPG.danger)
            Text(text)
                .font(.ppg(12.5, .bold))
                .foregroundStyle(PPG.ink.opacity(0.78))
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 8)
            Button("打开设置") {
                if let u = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles") {
                    NSWorkspace.shared.open(u)
                }
            }
            .buttonStyle(ComicButtonStyle(tint: PPG.sunny, size: .regular))
        }
        .comicCard(tint: PPG.danger, padding: 12)
        .padding(.horizontal, 16)
        .padding(.top, 12)
    }

    private var loadingCard: some View {
        VStack(spacing: 14) {
            ProgressView()
                .controlSize(.large)
                .tint(PPG.blossom)
            Text("正在读取目录结构…")
                .font(.ppgBody)
                .foregroundStyle(PPG.ink.opacity(0.6))
        }
        .comicCard(tint: PPG.blossom, padding: 24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var placeholder: some View {
        ComicEmptyState(
            icon: "chart.pie",
            title: "选择一个位置开始查看",
            message: "从上方「快速入口」选一个目录，开始查看空间分布。",
            tint: PPG.grape
        )
    }
}
