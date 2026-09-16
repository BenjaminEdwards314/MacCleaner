import SwiftUI
import AppKit

/// 矩形树图：面积正比于体积。
///
/// 交互：
/// - 悬停高亮，底部显示详情
/// - 单击目录 → 钻取进入
/// - 双击 / 右键 → 在 Finder 中显示
/// - 顶部面包屑返回
struct TreemapView: View {
    let level: DiskLevel
    let measuring: Bool
    let onDrill: (DiskNode) -> Void

    @State private var hovered: String?

    /// 色块调色板：三主角色 + 阳光黄 + 紫，按索引循环。
    ///
    /// 只用**索引**取色，绝不用 `hashValue` —— Swift 的 hashValue 每个进程
    /// 随机加盐，同一次运行内稳定，重启后整张图的颜色会全部错位。
    private static let palette: [Color] = [
        PPG.blossom, PPG.bubbles, PPG.buttercup, PPG.sunny, PPG.grape
    ]

    /// 圆角与描边，块与块之间统一
    private static let corner: CGFloat = 6

    var body: some View {
        GeometryReader { geo in
            let (rects, hiddenCount, hiddenWeight) = computeLayout(in: geo.size)

            ZStack(alignment: .topLeading) {
                // 奶油纸面：受保护块是半透明的主题色，需要一层浅底来调出粉彩效果
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(PPG.cream)

                // 未算完体积的项不参与布局 —— 否则它们会以 0 面积被挤没，
                // 体积回填后整张图会突然重排。
                ForEach(rects, id: \.id) { r in
                    if let node = index[r.id] {
                        block(r, node: node)
                    }
                }

                if rects.isEmpty {
                    emptyHint
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(PPG.ink.opacity(0.7), lineWidth: 2)
            }
            .overlay(alignment: .bottomLeading) {
                if let id = hovered, let node = index[id] {
                    hoverCard(node)
                }
            }
            .overlay(alignment: .topTrailing) {
                if hiddenCount > 0 {
                    ComicBadge(
                        text: "另有 \(hiddenCount) 项过小未显示（\(Fmt.size(Int64(hiddenWeight)))）",
                        tint: PPG.cream,
                        icon: "eye.slash.fill",
                        outlined: true
                    )
                    .padding(9)
                }
            }
            .overlay(alignment: .bottomTrailing) {
                legend
            }
        }
    }

    /// id → node 的索引表。避免每个块都做一次 O(n) 线性查找（50 块即 O(n²)）。
    ///
    /// 注意：这里是计算属性，每次 body 求值都会重建。
    /// 之所以可以接受，是因为上游 DiskNavigator 已对体积回填做了节流
    /// （最多每 250ms 一次），渲染次数不再失控。
    /// 早期版本真正的 CPU 问题是「每算完一项就全量重渲染」，而非这里的建表。
    private var index: [String: DiskNode] {
        Dictionary(level.children.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
    }

    private func computeLayout(in size: CGSize) -> ([TreemapLayout.Rect], Int, Double) {
        // 只把「已算出体积」的项交给布局，且必须降序
        let ready = level.children.filter { $0.measured && $0.size > 0 }
        guard !ready.isEmpty, size.width > 10, size.height > 10 else { return ([], 0, 0) }

        let slices = ready
            .sorted { $0.size > $1.size }
            .map { TreemapLayout.Slice(id: $0.id, weight: Double($0.size)) }

        let bounds = CGRect(origin: .zero, size: size)
        return TreemapLayout.squarify(slices, in: bounds, spacing: 2)
    }

    private func nodeFor(_ id: String) -> DiskNode? { index[id] }

    /// 颜色语义必须写明 —— 否则用户只能猜哪种颜色代表可清理
    private var legend: some View {
        HStack(spacing: 10) {
            legendItem(color: Self.palette[0], label: "可清理")
            legendItem(color: Self.palette[0].opacity(0.4), label: "受保护")
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background {
            Capsule()
                .fill(PPG.cream)
                .overlay { Capsule().strokeBorder(PPG.ink, lineWidth: 2) }
        }
        .padding(9)
    }

    private func legendItem(color: Color, label: String) -> some View {
        HStack(spacing: 4) {
            RoundedRectangle(cornerRadius: 3, style: .continuous)
                .fill(color)
                .overlay {
                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                        .strokeBorder(PPG.ink, lineWidth: 1.4)
                }
                .frame(width: 12, height: 12)
            Text(label)
                .font(.ppg(10.5, .heavy))
                .foregroundStyle(PPG.ink)
        }
    }

    // MARK: - 布局

    private func layout(in size: CGSize) -> ([TreemapLayout.Rect], Int, Double) {
        // 只把「已算出体积」的项交给布局，且必须降序
        let ready = level.children.filter { $0.measured && $0.size > 0 }
        guard !ready.isEmpty, size.width > 10, size.height > 10 else { return ([], 0, 0) }

        let slices = ready
            .sorted { $0.size > $1.size }
            .map { TreemapLayout.Slice(id: $0.id, weight: Double($0.size)) }

        let bounds = CGRect(origin: .zero, size: size)
        return TreemapLayout.squarify(slices, in: bounds, spacing: 2)
    }

    // MARK: - 单个块

    private func block(_ r: TreemapLayout.Rect, node: DiskNode) -> some View {
        let isHover = hovered == node.id
        let f = r.frame
        let corner = Self.corner
        // 只有够大的块才显示文字，否则文字会溢出错乱
        let showLabel = f.width > 68 && f.height > 30
        let showSize = f.width > 68 && f.height > 46

        return RoundedRectangle(cornerRadius: corner, style: .continuous)
            .fill(fill(node))
            // 常规态就是粗黑描边；悬停时加粗到 4pt
            .overlay {
                RoundedRectangle(cornerRadius: corner, style: .continuous)
                    .strokeBorder(PPG.ink, lineWidth: isHover ? 4 : 1.8)
            }
            // 悬停再内嵌一圈阳光黄 —— 在黄块、紫块上都看得见
            .overlay {
                if isHover {
                    RoundedRectangle(cornerRadius: corner, style: .continuous)
                        .strokeBorder(PPG.sunny, lineWidth: 2.5)
                        .padding(4)
                }
            }
            .overlay(alignment: .topLeading) {
                if showLabel {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(node.name)
                            .font(.ppg(11.5, .heavy))
                            .lineLimit(1)
                        if showSize {
                            Text(Fmt.size(node.size))
                                .font(.ppg(10.5, .black))
                                .monospacedDigit()
                                .opacity(0.85)
                                .lineLimit(1)
                        }
                    }
                    .foregroundStyle(PPG.ink)
                    // 奶油色浅晕，保证字在紫、粉等中深色块上也读得清
                    .shadow(color: PPG.cream.opacity(0.9), radius: 1.5, y: 0.5)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 3)
                }
            }
            .frame(width: f.width, height: f.height)
            // 悬停时向右下压出硬阴影，块像被「拿起来」了
            .background {
                if isHover {
                    RoundedRectangle(cornerRadius: corner, style: .continuous)
                        .fill(PPG.ink.opacity(0.75))
                        .offset(x: 3, y: 3)
                }
            }
            .scaleEffect(isHover ? 1.03 : 1)
            .animation(.easeOut(duration: 0.12), value: isHover)
            .position(x: f.midX, y: f.midY)
            .onHover { hovering in
                hovered = hovering ? node.id : (hovered == node.id ? nil : hovered)
            }
            .onTapGesture(count: 2) {
                NSWorkspace.shared.selectFile(node.path, inFileViewerRootedAtPath: "")
            }
            .onTapGesture {
                if node.isDirectory { onDrill(node) }
            }
            .contextMenu {
                Button("在 Finder 中显示") {
                    NSWorkspace.shared.selectFile(node.path, inFileViewerRootedAtPath: "")
                }
                Button("复制路径") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(node.path, forType: .string)
                }
                if node.isDirectory {
                    Divider()
                    Button("钻取进入") { onDrill(node) }
                }
            }
            .help("\(node.name)\n\(Fmt.size(node.size))\n\(node.path)")
    }

    /// 配色策略：
    /// - **可清理 = 饱和主题色**（三主角色 + 阳光黄 + 紫循环），是视觉焦点 ——
    ///   用户来这个界面就是为了找能清的
    /// - **受保护 = 同一主题色系的淡化版**（40% 不透明，落在奶油底上成粉彩），
    ///   视觉后退，但仍可辨认
    ///
    /// 注意别把两者反过来：如果让受保护的大块占据最显眼的饱和色，
    /// 用户会盯着最大的色块却不知道那正是不能动的东西。
    ///
    /// 取色只看「在各自子集中的序号」，序号预先算好放进字典
    /// （避免每个块都 filter 一遍，O(n²)），且**与 hashValue 无关**。
    private func fill(_ node: DiskNode) -> Color {
        let palette = Self.palette

        if node.cleanable {
            let idx = cleanableOrder[node.id] ?? 0
            return palette[idx % palette.count]
        }
        let idx = protectedOrder[node.id] ?? 0
        return palette[idx % palette.count].opacity(0.4)
    }

    /// 可清理项 → 其在可清理子集中的序号。预计算一次，避免逐块 O(n) 扫描。
    private var cleanableOrder: [String: Int] {
        var out: [String: Int] = [:]
        var n = 0
        for c in level.children where c.cleanable { out[c.id] = n; n += 1 }
        return out
    }

    /// 受保护项 → 序号，同样预计算
    private var protectedOrder: [String: Int] {
        var out: [String: Int] = [:]
        var n = 0
        for c in level.children where !c.cleanable { out[c.id] = n; n += 1 }
        return out
    }

    // MARK: - 悬停详情

    private func hoverCard(_ node: DiskNode) -> some View {
        HStack(spacing: 10) {
            ZStack {
                Circle()
                    .fill(node.isDirectory ? PPG.sunny : PPG.bubbles)
                    .overlay { Circle().strokeBorder(PPG.ink, lineWidth: 2) }
                    .frame(width: 30, height: 30)
                Image(systemName: node.isDirectory ? "folder.fill" : "doc.fill")
                    .font(.ppg(12.5, .black))
                    .foregroundStyle(PPG.ink)
            }

            VStack(alignment: .leading, spacing: 1) {
                Text(node.name)
                    .font(.ppg(13.5, .black))
                    .foregroundStyle(PPG.ink)
                    .lineLimit(1)
                Text(node.path)
                    .font(.ppg(10.5, .medium))
                    .foregroundStyle(PPG.ink.opacity(0.55))
                    .lineLimit(1).truncationMode(.middle)
            }

            Text(Fmt.size(node.size))
                .font(.ppg(14, .black))
                .foregroundStyle(PPG.ink)
                .monospacedDigit()

            if node.cleanable {
                ComicBadge(text: "可清理", tint: PPG.buttercup, icon: "checkmark.circle.fill")
            } else {
                ComicBadge(text: "受保护", tint: PPG.cream, icon: "lock.fill", outlined: true)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(PPG.cream, in: RoundedRectangle(cornerRadius: 15, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 15, style: .continuous)
                .strokeBorder(PPG.ink, lineWidth: 2.5)
        }
        .background {
            RoundedRectangle(cornerRadius: 15, style: .continuous)
                .fill(PPG.ink.opacity(0.8))
                .offset(x: 3, y: 3)
        }
        .padding(9)
        .frame(maxWidth: 460, alignment: .leading)
    }

    private var emptyHint: some View {
        ComicEmptyState(
            icon: measuring ? "hourglass" : "square.grid.3x3",
            title: measuring ? "正在统计体积，稍候…" : "此目录没有可显示的内容",
            message: measuring
                ? "体积算完一项就会立刻上图，不必等全部统计结束。"
                : "换一层目录，或回到上一层看看别处。",
            tint: measuring ? PPG.bubbles : PPG.grape
        )
        .padding(20)
    }
}
