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

    var body: some View {
        GeometryReader { geo in
            let (rects, hiddenCount, hiddenWeight) = computeLayout(in: geo.size)

            ZStack(alignment: .topLeading) {
                Color(nsColor: .textBackgroundColor)

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
            .overlay(alignment: .bottomLeading) {
                if let id = hovered, let node = index[id] {
                    hoverCard(node)
                }
            }
            .overlay(alignment: .topTrailing) {
                if hiddenCount > 0 {
                    Text("另有 \(hiddenCount) 项过小未显示（\(Fmt.size(Int64(hiddenWeight)))）")
                        .font(.caption2)
                        .padding(.horizontal, 7).padding(.vertical, 3)
                        .background(.thinMaterial, in: Capsule())
                        .padding(7)
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
            HStack(spacing: 4) {
                RoundedRectangle(cornerRadius: 2)
                    .fill(Color(hue: 0.07, saturation: 0.72, brightness: 0.90))
                    .frame(width: 10, height: 10)
                Text("可清理").font(.caption2)
            }
            HStack(spacing: 4) {
                RoundedRectangle(cornerRadius: 2)
                    .fill(Color(hue: 0.58, saturation: 0.13, brightness: 0.72))
                    .frame(width: 10, height: 10)
                Text("受保护").font(.caption2)
            }
        }
        .padding(.horizontal, 8).padding(.vertical, 4)
        .background(.thinMaterial, in: Capsule())
        .padding(7)
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
        // 只有够大的块才显示文字，否则文字会溢出错乱
        let showLabel = f.width > 68 && f.height > 30
        let showSize = f.width > 68 && f.height > 46

        return RoundedRectangle(cornerRadius: 4)
            .fill(fill(node))
            .overlay(
                RoundedRectangle(cornerRadius: 4)
                    .stroke(isHover ? Color.primary.opacity(0.85) : Color.black.opacity(0.10),
                            lineWidth: isHover ? 2 : 0.5)
            )
            .overlay(alignment: .topLeading) {
                if showLabel {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(node.name)
                            .font(.system(size: 11, weight: .medium))
                            .lineLimit(1)
                        if showSize {
                            Text(Fmt.size(node.size))
                                .font(.system(size: 10))
                                .opacity(0.8)
                                .lineLimit(1)
                        }
                    }
                    .foregroundStyle(.white)
                    .shadow(color: .black.opacity(0.5), radius: 1.5, y: 0.5)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 3)
                }
            }
            .frame(width: f.width, height: f.height)
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
    /// - **可清理 = 高饱和暖色**，是视觉焦点 —— 用户来这个界面就是为了找能清的
    /// - **受保护 = 低饱和冷灰**，视觉后退，但仍可辨认
    /// - **其他（过小合并） = 中性灰**
    ///
    /// 注意别把两者反过来：如果让受保护的大块占据最显眼的中性色，
    /// 用户会盯着最大的灰块却不知道那正是不能动的东西。
    ///
    /// 色相按「可清理子集中的序号」错开，保证相邻块可区分。
    /// 该序号预先算好放进字典，避免每个块都 filter 一遍（O(n²)）。
    private func fill(_ node: DiskNode) -> Color {
        if node.cleanable {
            let idx = cleanableOrder[node.id] ?? 0
            let hues: [Double] = [0.07, 0.11, 0.03, 0.15, 0.09, 0.13]
            return Color(hue: hues[idx % hues.count], saturation: 0.72, brightness: 0.90)
        }
        // 受保护：低饱和蓝灰，靠亮度微差区分相邻块
        let idx = protectedOrder[node.id] ?? 0
        let b = 0.66 + Double(idx % 3) * 0.06
        return Color(hue: 0.58, saturation: 0.13, brightness: b)
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
        HStack(spacing: 8) {
            Image(systemName: node.isDirectory ? "folder.fill" : "doc.fill")
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 1) {
                Text(node.name).font(.callout).lineLimit(1)
                Text(node.path)
                    .font(.caption2).foregroundStyle(.secondary)
                    .lineLimit(1).truncationMode(.middle)
            }
            Text(Fmt.size(node.size)).font(.callout).monospacedDigit()
            if node.cleanable {
                Text("可清理")
                    .font(.caption2)
                    .padding(.horizontal, 5).padding(.vertical, 1)
                    .background(Color.green.opacity(0.18), in: Capsule())
                    .foregroundStyle(.green)
            }
        }
        .padding(.horizontal, 10).padding(.vertical, 6)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
        .shadow(radius: 5, y: 2)
        .padding(9)
        .frame(maxWidth: 460, alignment: .leading)
    }

    private var emptyHint: some View {
        VStack(spacing: 9) {
            Image(systemName: "square.grid.3x3").font(.system(size: 30)).foregroundStyle(.tertiary)
            Text(measuring ? "正在统计体积，稍候…" : "此目录没有可显示的内容")
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
