import Foundation
import CoreGraphics

/// 树图（treemap）布局。
///
/// 用 squarified 算法（Bruls et al. 2000）：把矩形按面积切成尽量接近正方形的块。
/// 朴素的 slice-and-dice 会切出细长条，面积再对也读不出比例，所以必须 squarify。
///
/// 面积正比于体积 —— 这是树图的全部意义：一眼看出谁大。
enum TreemapLayout {

    /// 一个待布局的块
    struct Slice {
        let id: String
        let weight: Double      // 体积（Int64 转 Double 后）
    }

    /// 布局结果：每个 id 对应一个矩形
    struct Rect {
        let id: String
        let frame: CGRect
        /// 该块是否小到不值得交互（只能显示色块，点不中）
        var tooSmall: Bool { frame.width < 2 || frame.height < 2 }
    }

    /// 把 items 铺进 bounds。
    ///
    /// - Parameters:
    ///   - items: 已按 weight 降序排列。必须降序，squarify 依赖这个前提。
    ///   - bounds: 可用区域
    ///   - spacing: 块间距（视觉分隔）
    ///   - minFraction: 单个块的最小面积占比。低于此值的块会被并入「其他」，
    ///     避免出现 1000:1 那种悬殊分布下被压成细条、点不中的块。
    static func squarify(
        _ items: [Slice],
        in bounds: CGRect,
        spacing: CGFloat = 1.5,
        minFraction: Double = 0.004
    ) -> (rects: [Rect], hiddenCount: Int, hiddenWeight: Double) {
        let positive = items.filter { $0.weight > 0 }
        guard !positive.isEmpty, bounds.width > 0, bounds.height > 0 else {
            return ([], 0, 0)
        }

        let total = positive.reduce(0.0) { $0 + $1.weight }
        guard total > 0 else { return ([], 0, 0) }

        // 太小的块不单独画 —— 它们的面积不足以承载可读的文字或点击目标。
        // 注意 positive 已按降序，所以一旦低于阈值，后面的都低于阈值。
        var drawable: [Slice] = []
        var hiddenWeight = 0.0
        var hiddenCount = 0
        for s in positive {
            if s.weight / total < minFraction {
                hiddenWeight += s.weight
                hiddenCount += 1
            } else {
                drawable.append(s)
            }
        }

        // 隐藏的那些合成一个「其他」块，保证面积不失真
        if hiddenWeight > 0 {
            drawable.append(Slice(id: "__other__", weight: hiddenWeight))
        }

        guard !drawable.isEmpty else { return ([], 0, 0) }

        // 归一化成面积：总面积 = bounds 面积，再按 weight 比例分配
        let area = Double(bounds.width * bounds.height)
        let scaled = drawable.map { Slice(id: $0.id, weight: $0.weight / total * area) }

        var out: [Rect] = []
        var free = bounds
        var rest = scaled

        while !rest.isEmpty {
            let shortSide = min(free.width, free.height)
            guard shortSide > 0 else { break }

            // 贪心地往当前行里加块，直到加入下一块会让最差长宽比变糟
            var row: [Slice] = [rest[0]]
            rest.removeFirst()
            var bestRatio = worstRatio(row, shortSide: shortSide)

            while !rest.isEmpty {
                let candidate = row + [rest[0]]
                let ratio = worstRatio(candidate, shortSide: shortSide)
                if ratio > bestRatio { break }      // 变糟了，停止
                row = candidate
                rest.removeFirst()
                bestRatio = ratio
            }

            // 摆放这一行
            //
            // 关键：行内块要按 weight **占满整条边**。
            // 早期实现写成 `v / free.height`（竖切）和 `v / free.width`（横切），
            // 量纲错了 —— 实测面积偏差最高达 100%（Google 占了两倍面积）。
            // 正确公式是 `v / rowSum * free.height`（竖切）/ `v / rowSum * free.width`（横切），
            // 保证行内块之和恰好等于该条边的长度。
            let rowSum = row.reduce(0.0) { $0 + $1.weight }
            guard rowSum > 0 else { break }

            if free.width >= free.height {
                // 竖着切一列：列宽由 rowSum 决定，块高按占比填满整列
                let colWidth = CGFloat(rowSum) / Double(free.height)
                var y = free.minY
                for s in row {
                    let h = CGFloat(s.weight) / Double(rowSum) * free.height
                    out.append(Rect(id: s.id, frame: CGRect(x: free.minX, y: y,
                                                           width: max(0, colWidth - spacing),
                                                           height: max(0, h - spacing))))
                    y += h
                }
                free = CGRect(x: free.minX + colWidth, y: free.minY,
                              width: max(0, free.width - colWidth), height: free.height)
            } else {
                // 横着切一行：行高由 rowSum 决定，块宽按占比填满整行
                let rowHeight = CGFloat(rowSum) / Double(free.width)
                var x = free.minX
                for s in row {
                    let w = CGFloat(s.weight) / Double(rowSum) * free.width
                    out.append(Rect(id: s.id, frame: CGRect(x: x, y: free.minY,
                                                           width: max(0, w - spacing),
                                                           height: max(0, rowHeight - spacing))))
                    x += w
                }
                free = CGRect(x: free.minX, y: free.minY + rowHeight,
                              width: free.width, height: max(0, free.height - rowHeight))
            }
        }

        return (out, hiddenCount, hiddenWeight)
    }

    /// 一行里最差的长宽比（squarify 的代价函数）
    private static func worstRatio(_ row: [Slice], shortSide: CGFloat) -> Double {
        guard !row.isEmpty, shortSide > 0 else { return .infinity }
        let sum = row.reduce(0.0) { $0 + $1.weight }
        guard sum > 0 else { return .infinity }

        let side = Double(shortSide)
        let maxW = row.map(\.weight).max() ?? 0
        let minW = row.map(\.weight).min() ?? 0
        if minW <= 0 { return .infinity }

        let s2 = sum * sum
        let side2 = side * side
        // 标准 squarify 代价：max(s²·maxW/(sum²·side²)… 这里用等价形式
        return max(side2 * maxW / s2, s2 / (side2 * minW))
    }
}
