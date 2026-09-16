import SwiftUI

// MARK: - 调色板

/// 飞天小女警主题。
///
/// 卡通感靠三个统一手法建立，全项目一致使用：
///
/// 1. **粗黑描边** —— 卡片、按钮、徽章一律带 2–3pt 的 `ink` 边框
/// 2. **硬阴影** —— `radius: 0` 的纯黑投影，不模糊，像贴纸浮在纸面上
/// 3. **大圆角 + 圆润字体** —— 抵消系统控件那种冷硬感
///
/// 颜色取自三位主角：花花（粉）、泡泡（蓝）、毛毛（绿）。
enum PPG {

    // MARK: 主角色

    /// 花花 · 粉
    static let blossom   = Color(red: 1.00, green: 0.42, blue: 0.62)
    /// 泡泡 · 蓝
    static let bubbles   = Color(red: 0.33, green: 0.76, blue: 0.98)
    /// 毛毛 · 绿
    static let buttercup = Color(red: 0.52, green: 0.86, blue: 0.32)

    /// 三姐妹色，按序循环
    static let trio: [Color] = [blossom, bubbles, buttercup]

    /// 取第 i 个主角色（自动取模，负数也安全）。
    /// 用来给列表项、分组、图标循环上色，避免整页只有一种颜色。
    static func girl(_ i: Int) -> Color {
        trio[((i % trio.count) + trio.count) % trio.count]
    }

    // MARK: 辅助色

    /// 阳光黄，用于星星、高亮、庆祝
    static let sunny  = Color(red: 1.00, green: 0.84, blue: 0.28)
    /// 描边与主文字的黑。略偏暖，比纯黑柔和一点
    static let ink    = Color(red: 0.11, green: 0.10, blue: 0.15)
    /// 卡片底
    static let cream  = Color(red: 1.00, green: 0.98, blue: 0.96)
    /// 窗口底
    static let sky    = Color(red: 0.93, green: 0.97, blue: 1.00)
    /// 危险 / 警示。用作徽章、图标、卡片的**底色**，上面配 `ink` 深色字
    /// （对比度 5.66:1，达 WCAG AA）。
    static let danger = Color(red: 1.00, green: 0.36, blue: 0.36)

    /// 危险按钮的实心底色，专配白字。
    ///
    /// 不能复用 `danger`：亮红配白字只有 3.03:1，低于 WCAG AA 的 4.5:1。
    /// 但把 `danger` 整体调暗，又会让徽章上的深色字掉到 3.53:1。
    /// 两个用途对明度的要求相反，所以拆成两个常量各司其职。
    static let dangerDeep = Color(red: 0.84, green: 0.19, blue: 0.19)
    /// 紫，用于「其他」类目
    static let grape  = Color(red: 0.62, green: 0.44, blue: 0.95)

    /// 窗口背景：淡蓝 → 淡粉的斜向渐变
    static var backdrop: LinearGradient {
        LinearGradient(
            colors: [sky, Color(red: 1.00, green: 0.95, blue: 0.97)],
            startPoint: .topLeading, endPoint: .bottomTrailing
        )
    }

    /// 侧边栏背景：比主背景略深，形成层次
    static var sidebarBackdrop: LinearGradient {
        LinearGradient(
            colors: [Color(red: 0.90, green: 0.95, blue: 1.00),
                     Color(red: 0.97, green: 0.93, blue: 0.98)],
            startPoint: .top, endPoint: .bottom
        )
    }
}

// MARK: - 字体

extension Font {
    /// 主题字体：圆润 + 粗。卡通感的一半来自这里。
    static func ppg(_ size: CGFloat, _ weight: Font.Weight = .heavy) -> Font {
        .system(size: size, weight: weight, design: .rounded)
    }

    /// 页面大标题
    static var ppgTitle: Font    { .ppg(26, .black) }
    /// 区块标题
    static var ppgSection: Font  { .ppg(17, .heavy) }
    /// 正文
    static var ppgBody: Font     { .ppg(13.5, .medium) }
    /// 次要说明
    static var ppgCaption: Font  { .ppg(11.5, .semibold) }
    /// 按钮
    static var ppgButton: Font   { .ppg(14, .heavy) }
}

// MARK: - 形状

/// 爆炸星形。飞天小女警片头那个「burst」轮廓，用作徽章和装饰底衬。
struct StarburstShape: Shape {
    var points: Int = 12
    /// 内圈半径占比，越小锯齿越尖
    var innerRatio: CGFloat = 0.66

    func path(in rect: CGRect) -> Path {
        var p = Path()
        let c = CGPoint(x: rect.midX, y: rect.midY)
        let rOuter = min(rect.width, rect.height) / 2
        let rInner = rOuter * innerRatio
        let total = max(points, 3) * 2

        for i in 0..<total {
            let angle = Double(i) / Double(total) * 2 * .pi - .pi / 2
            let r = i.isMultiple(of: 2) ? rOuter : rInner
            // 显式转 CGFloat：angle 是 Double，直接和 CGFloat 相乘会让
            // cos/sin 的重载产生歧义
            let pt = CGPoint(x: c.x + CGFloat(cos(angle)) * r,
                             y: c.y + CGFloat(sin(angle)) * r)
            if i == 0 { p.move(to: pt) } else { p.addLine(to: pt) }
        }
        p.closeSubpath()
        return p
    }
}

// MARK: - 卡片

/// 贴纸式卡片：粗描边 + 硬阴影 + 大圆角。
struct ComicCard: ViewModifier {
    var tint: Color = PPG.bubbles
    var padding: CGFloat = 16
    /// 硬阴影偏移量
    var depth: CGFloat = 4
    /// 描边粗细
    var border: CGFloat = 2.5

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .background(PPG.cream, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .strokeBorder(PPG.ink, lineWidth: border)
            }
            .background {
                // 硬阴影：同形状的纯黑块向右下偏移，不加模糊
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(PPG.ink.opacity(0.85))
                    .offset(x: depth, y: depth)
            }
    }
}

extension View {
    /// 套一张贴纸卡片
    func comicCard(tint: Color = PPG.bubbles,
                   padding: CGFloat = 16,
                   depth: CGFloat = 4,
                   border: CGFloat = 2.5) -> some View {
        modifier(ComicCard(tint: tint, padding: padding, depth: depth, border: border))
    }
}

// MARK: - 背景装饰

/// 淡淡的半调网点，模拟漫画印刷质感。
///
/// 只在标题栏等小面积使用 —— 大面积铺会在滚动时拖慢渲染。
struct HalftoneDots: View {
    var color: Color = PPG.ink
    var spacing: CGFloat = 9
    var dot: CGFloat = 2.2
    var opacity: Double = 0.07

    var body: some View {
        Canvas { ctx, size in
            var y: CGFloat = 0
            var row = 0
            while y < size.height {
                // 隔行错位，形成经典网点排布
                var x: CGFloat = row.isMultiple(of: 2) ? 0 : spacing / 2
                while x < size.width {
                    ctx.fill(
                        Path(ellipseIn: CGRect(x: x, y: y, width: dot, height: dot)),
                        with: .color(color.opacity(opacity))
                    )
                    x += spacing
                }
                y += spacing
                row += 1
            }
        }
        .allowsHitTesting(false)
    }
}
