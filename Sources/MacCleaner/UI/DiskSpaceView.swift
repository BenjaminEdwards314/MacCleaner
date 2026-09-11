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
            Divider()
            breadcrumb
            Divider()

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
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(DiskScanner.roots(), id: \.path) { url in
                    Button {
                        nav.open(url)
                    } label: {
                        Text(shortName(url))
                            .font(.callout)
                    }
                    .buttonStyle(.bordered)
                    .tint(nav.current?.path == url.path ? .accentColor : nil)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
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
        HStack(spacing: 4) {
            Button {
                nav.up()
            } label: {
                Image(systemName: "chevron.up")
            }
            .disabled(nav.path.count <= 1)
            .help("返回上一层")

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 2) {
                    ForEach(Array(nav.path.enumerated()), id: \.offset) { idx, url in
                        if idx > 0 {
                            Image(systemName: "chevron.right")
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                        }
                        Button {
                            nav.jump(to: idx)
                        } label: {
                            Text(displayName(url))
                                .font(.callout)
                                .lineLimit(1)
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(idx == nav.path.count - 1 ? .primary : .secondary)
                    }
                }
            }

            Spacer()

            // 视图切换：树图看比例，列表看细节（项太多时树图的小块点不中）
            Picker("", selection: $style) {
                Image(systemName: "square.grid.3x3.fill").tag(Style.treemap).help("矩形树图")
                Image(systemName: "list.bullet").tag(Style.list).help("列表")
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(width: 84)

            // 回填进度：内容已可用，只是数字还在补
            if nav.isMeasuring, let lvl = nav.level {
                HStack(spacing: 5) {
                    ProgressView().controlSize(.small).scaleEffect(0.7)
                    Text("统计中 \(lvl.measuredCount)/\(lvl.children.count)")
                        .font(.caption).foregroundStyle(.secondary).monospacedDigit()
                }
            } else if let lvl = nav.level, lvl.node.measured {
                Text(Fmt.size(lvl.node.size))
                    .font(.callout).monospacedDigit()
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 7)
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
                .padding(10)
            }
        case .list:
            listContent(level)
        }
    }

    private func listContent(_ level: DiskLevel) -> some View {
        ScrollView {
            VStack(spacing: 0) {
                if let err = nav.errorText {
                    permissionBanner(err)
                }

                if level.deniedCount > 0 && nav.errorText == nil {
                    permissionBanner("此目录下有 \(level.deniedCount) 项因权限不足无法统计，显示的体积偏小。可在「系统设置 → 隐私与安全性 → 完全磁盘访问权限」中授权。")
                }

                if level.skippedPathological {
                    skippedBanner
                }

                ForEach(level.children) { node in
                    row(node, parentSize: level.node.size)
                    Divider().padding(.leading, 44)
                }

                if level.hiddenCount > 0 {
                    HStack {
                        Image(systemName: "ellipsis.circle")
                            .foregroundStyle(.tertiary)
                        Text("其他 \(level.hiddenCount) 项")
                        Spacer()
                        Text(Fmt.size(level.hiddenSize)).monospacedDigit()
                    }
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 9)
                }

                if level.children.isEmpty && level.deniedCount == 0 {
                    Text("此目录为空")
                        .foregroundStyle(.secondary)
                        .padding(30)
                }
            }
        }
    }

    private func row(_ node: DiskNode, parentSize: Int64) -> some View {
        let fraction = parentSize > 0 ? Double(node.size) / Double(parentSize) : 0

        return HStack(spacing: 12) {
            Image(systemName: node.isDirectory ? "folder.fill" : "doc.fill")
                .foregroundStyle(node.cleanable ? Color.accentColor : Color.secondary)
                .frame(width: 20)

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(node.name).lineLimit(1)
                    if node.accessDenied {
                        tag("无权限", .orange)
                    } else if node.cleanable {
                        tag("可清理", .green)
                    }
                }

                // 占比条 —— 比数字更快看出谁是主要占用
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.secondary.opacity(0.15))
                        Capsule()
                            .fill(node.cleanable ? Color.accentColor : Color.secondary)
                            .frame(width: max(2, geo.size.width * fraction))
                    }
                }
                .frame(height: 4)
                .opacity(node.measured ? 1 : 0.3)
            }

            Spacer(minLength: 8)

            // 未算出的显示占位符 —— 显示「0 字节」会让用户误以为目录是空的
            if node.measured {
                Text(Fmt.size(node.size))
                    .font(.callout).monospacedDigit()
                    .foregroundStyle(.secondary)
                    .frame(width: 84, alignment: .trailing)
            } else {
                Text("…")
                    .font(.callout)
                    .foregroundStyle(.tertiary)
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
                .buttonStyle(.borderless)
                .help("在 Finder 中显示")

                Image(systemName: "chevron.right")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            } else {
                Color.clear.frame(width: 30)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 7)
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

    private func tag(_ text: String, _ color: Color) -> some View {
        Text(text)
            .font(.caption2)
            .padding(.horizontal, 5)
            .padding(.vertical, 1)
            .background(color.opacity(0.16), in: Capsule())
            .foregroundStyle(color)
    }

    /// 跳过病态目录时**必须明说**。
    /// 静默跳过会让用户看到一个偏小的数字却不知为何 —— 那比慢更糟。
    private var skippedBanner: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "speedometer").foregroundStyle(.blue)
            VStack(alignment: .leading, spacing: 2) {
                Text("为加快扫描，已跳过崩溃转储目录")
                    .font(.caption).fontWeight(.medium)
                Text("这些目录（如 Codex Crashpad）含数十万个文件，统计它们极慢且均为可清理的死数据。此处显示的体积不含这部分，实际占用会更大。可在「清理」页查看并清理它们。")
                    .font(.caption2).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
        }
        .padding(11)
        .background(Color.blue.opacity(0.10), in: RoundedRectangle(cornerRadius: 9))
        .padding(.horizontal, 16)
        .padding(.top, 11)
    }

    private func permissionBanner(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "lock.fill").foregroundStyle(.orange)
            Text(text).font(.caption).fixedSize(horizontal: false, vertical: true)
            Spacer()
            Button("打开设置") {
                if let u = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles") {
                    NSWorkspace.shared.open(u)
                }
            }
            .font(.caption)
        }
        .padding(11)
        .background(Color.orange.opacity(0.10), in: RoundedRectangle(cornerRadius: 9))
        .padding(.horizontal, 16)
        .padding(.top, 11)
    }

    private var loadingCard: some View {
        VStack(spacing: 11) {
            ProgressView()
            Text("正在读取目录结构…").font(.callout).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var placeholder: some View {
        VStack(spacing: 9) {
            Image(systemName: "chart.pie").font(.system(size: 32)).foregroundStyle(.tertiary)
            Text("选择一个位置开始查看").foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
