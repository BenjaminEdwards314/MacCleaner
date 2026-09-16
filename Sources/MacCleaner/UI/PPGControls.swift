import SwiftUI

// MARK: - 点击迸发的星星

/// 点击按钮时从中心迸出的星星。
///
/// 实现上只用**一个** `progress` 驱动全部粒子 —— 每颗星的角度是固定的，
/// 位置、缩放、透明度都由 progress 推出来。这样一次点击只产生一趟动画，
/// 不会因为粒子多而掉帧。
///
/// 透明度曲线是这里的关键：粒子不能一出生就是实心的。若在 progress=0 时
/// 就不透明，所有星星会叠在按钮正中、盖住文字，看起来像渲染出错而不是特效。
/// 所以做成「渐入 → 峰值 → 渐隐」，并且起始半径留出按钮文字的宽度。
struct StarBurst: View {
    /// 每次自增即触发一次迸发
    var trigger: Int
    var color: Color = PPG.sunny
    var count: Int = 9
    var radius: CGFloat = 52
    /// 起始半径占 `radius` 的比例。
    ///
    /// 用比例而非绝对值：小圆图标按钮的 radius 只有 30，若起始半径固定 26pt，
    /// 星星几乎不动、看着像原地闪烁。按比例缩放后，大按钮和小按钮的
    /// 迸发幅度才一致，也都从文字外侧冒出来。
    var startRadiusRatio: CGFloat = 0.55
    var duration: Double = 0.5
    var starSize: CGFloat = 13

    @State private var progress: CGFloat = 0
    @State private var visible = false

    var body: some View {
        ZStack {
            ForEach(0..<count, id: \.self) { i in
                // 均匀分布 + 每颗略微错开，避免看起来像个规则齿轮
                let angle = Double(i) / Double(count) * 2 * .pi - .pi / 2
                let jitter = CGFloat((i * 37) % 11) / 11 * 0.35 + 0.85
                let r0 = radius * startRadiusRatio
                let r = (r0 + (radius - r0) * easeOut(progress)) * jitter
                let scale = visible ? bornScale(progress) : 0

                StarburstShape(points: 4, innerRatio: 0.34)
                    .fill(color)
                    .overlay {
                        StarburstShape(points: 4, innerRatio: 0.34)
                            .stroke(PPG.ink, lineWidth: 1.2)
                    }
                    .frame(width: starSize, height: starSize)
                    .scaleEffect(scale)
                    .rotationEffect(.degrees(Double(i) * 24 + Double(progress) * 90))
                    .offset(x: cos(angle) * r, y: sin(angle) * r)
                    .opacity(visible ? fadeCurve(progress) : 0)
            }
        }
        .allowsHitTesting(false)
        .onChange(of: trigger) { _, _ in
            progress = 0
            visible = true
            withAnimation(.easeOut(duration: duration)) { progress = 1 }
            // 动画结束后收起来，避免残留的不可见视图继续参与布局
            DispatchQueue.main.asyncAfter(deadline: .now() + duration + 0.05) {
                visible = false
            }
        }
    }

    /// 先快后慢，比线性更有「迸出去」的冲劲
    private func easeOut(_ t: CGFloat) -> CGFloat {
        1 - pow(1 - min(max(t, 0), 1), 2.4)
    }

    /// 渐入 → 峰值 → 渐隐。
    /// 前 15% 快速亮起，45% 之后开始淡出，到结束刚好消失。
    private func fadeCurve(_ t: CGFloat) -> Double {
        let appear = min(1, max(0, t / 0.15))
        let fade = 1 - min(1, max(0, (t - 0.45) / 0.55))
        return Double(appear * fade)
    }

    /// 由小放大再轻微回缩，像真的「弹」出来
    private func bornScale(_ t: CGFloat) -> CGFloat {
        let grow = min(1, t / 0.22)
        let settle = 1 - min(1, max(0, (t - 0.55) / 0.45)) * 0.35
        return max(0, grow * settle)
    }
}

// MARK: - 卡通按钮

/// 贴纸式按钮：按下时向自己的硬阴影里「陷进去」，松手弹回并迸出星星。
///
/// 尺寸档位刻意做得比系统控件大一圈 —— 系统 `.bordered` 按钮高度约 22pt，
/// 在 1100pt 宽的窗口里偏小、不好点。这里最小档 34pt，常规 42pt。
struct ComicButtonStyle: ButtonStyle {

    enum Size {
        /// 次级操作
        case small
        /// 常规操作
        case regular
        /// 主操作
        case large

        var font: Font {
            switch self {
            case .small:   return .ppg(12.5, .heavy)
            case .regular: return .ppgButton
            case .large:   return .ppg(16.5, .black)
            }
        }

        var hPad: CGFloat {
            switch self {
            case .small:   return 12
            case .regular: return 18
            case .large:   return 24
            }
        }

        var vPad: CGFloat {
            switch self {
            case .small:   return 7
            case .regular: return 10
            case .large:   return 13
            }
        }

        /// 最小命中高度。regular 取 42pt，接近 Apple 建议的 44pt 触达尺寸。
        var minHeight: CGFloat {
            switch self {
            case .small:   return 30
            case .regular: return 42
            case .large:   return 50
            }
        }

        var depth: CGFloat {
            switch self {
            case .small:   return 2.5
            case .regular: return 3.5
            case .large:   return 4.5
            }
        }

        var corner: CGFloat {
            switch self {
            case .small:   return 11
            case .regular: return 14
            case .large:   return 17
            }
        }
    }

    var tint: Color = PPG.bubbles
    var size: Size = .regular
    /// 是否在点击时迸出星星
    var burst: Bool = true
    /// 文字颜色。亮色底配深色字（默认 `ink`）；
    /// 传 `.white` 时必须配深色底 —— 例如 `PPG.dangerDeep` 而非 `PPG.danger`，
    /// 后者配白字只有 3.03:1，不达 WCAG AA。
    var textColor: Color = PPG.ink
    /// 次要按钮用描边款式（透明底）
    var outlined: Bool = false

    func makeBody(configuration: Configuration) -> some View {
        ComicButtonBody(
            configuration: configuration,
            tint: tint, size: size, burst: burst,
            textColor: textColor, outlined: outlined
        )
    }
}

private struct ComicButtonBody: View {
    let configuration: ButtonStyle.Configuration
    let tint: Color
    let size: ComicButtonStyle.Size
    let burst: Bool
    let textColor: Color
    let outlined: Bool

    @State private var burstTrigger = 0
    @Environment(\.isEnabled) private var isEnabled

    private var pressed: Bool { configuration.isPressed && isEnabled }
    /// 按下时位移量：正好等于阴影深度，视觉上就是「坐进影子里」
    private var sink: CGFloat { pressed ? size.depth : 0 }
    private var depth: CGFloat { pressed ? 0 : size.depth }

    var body: some View {
        configuration.label
            .font(size.font)
            .foregroundStyle(isEnabled ? textColor : PPG.ink.opacity(0.35))
            .padding(.horizontal, size.hPad)
            .padding(.vertical, size.vPad)
            .frame(minHeight: size.minHeight)
            .background {
                RoundedRectangle(cornerRadius: size.corner, style: .continuous)
                    .fill(outlined ? PPG.cream : tint)
                    .overlay {
                        RoundedRectangle(cornerRadius: size.corner, style: .continuous)
                            .strokeBorder(
                                isEnabled ? PPG.ink : PPG.ink.opacity(0.25),
                                lineWidth: outlined ? 2.2 : 2.5
                            )
                    }
            }
            .background {
                RoundedRectangle(cornerRadius: size.corner, style: .continuous)
                    .fill(PPG.ink.opacity(isEnabled ? 0.9 : 0.2))
                    .offset(x: depth, y: depth)
            }
            .offset(x: sink, y: sink)
            .opacity(isEnabled ? 1 : 0.55)
            .overlay {
                if burst {
                    StarBurst(trigger: burstTrigger, color: burstColor, radius: 44, starSize: 11)
                }
            }
            .contentShape(RoundedRectangle(cornerRadius: size.corner, style: .continuous))
            .animation(.spring(response: 0.18, dampingFraction: 0.55), value: pressed)
            .onChange(of: configuration.isPressed) { _, now in
                // 松手才迸发 —— 按住不放时星星乱飞会很吵
                if !now && burst && isEnabled { burstTrigger += 1 }
            }
    }

    /// 描边款用底色本身迸发，实心款用阳光黄，保证在两种底上都看得见
    private var burstColor: Color {
        outlined ? tint : PPG.sunny
    }
}

// MARK: - 圆图标按钮

/// 圆形图标按钮。给「在访达中显示」这类只有图标的操作提供足够大的命中区。
struct ComicIconButtonStyle: ButtonStyle {
    var tint: Color = PPG.bubbles
    var diameter: CGFloat = 34

    func makeBody(configuration: Configuration) -> some View {
        ComicIconBody(configuration: configuration, tint: tint, diameter: diameter)
    }
}

private struct ComicIconBody: View {
    let configuration: ButtonStyle.Configuration
    let tint: Color
    let diameter: CGFloat

    @State private var burstTrigger = 0
    @Environment(\.isEnabled) private var isEnabled
    private var pressed: Bool { configuration.isPressed && isEnabled }

    var body: some View {
        configuration.label
            .font(.ppg(14, .bold))
            .foregroundStyle(PPG.ink)
            .frame(width: diameter, height: diameter)
            .background {
                Circle()
                    .fill(tint)
                    .overlay { Circle().strokeBorder(PPG.ink, lineWidth: 2.2) }
            }
            .background {
                Circle()
                    .fill(PPG.ink.opacity(0.9))
                    .offset(x: pressed ? 0 : 2.5, y: pressed ? 0 : 2.5)
            }
            .offset(x: pressed ? 2.5 : 0, y: pressed ? 2.5 : 0)
            .overlay {
                StarBurst(trigger: burstTrigger, color: PPG.sunny,
                          count: 6, radius: 30, starSize: 8)
            }
            .contentShape(Circle())
            .animation(.spring(response: 0.18, dampingFraction: 0.55), value: pressed)
            .onChange(of: configuration.isPressed) { _, now in
                if !now && isEnabled { burstTrigger += 1 }
            }
    }
}

// MARK: - 卡通勾选框

/// 大号方形勾选框。原来列表里用的是 13pt 的系统 `Toggle`，点起来很局促。
struct ComicCheckbox: View {
    let isOn: Bool
    var tint: Color = PPG.bubbles
    /// 点击回调。留空则只作为展示（外层自己处理点击）
    var action: (() -> Void)?

    @State private var bounce = false

    var body: some View {
        Button {
            guard let action else { return }
            action()
            bounce = true
            withAnimation(.spring(response: 0.22, dampingFraction: 0.4)) { bounce = false }
        } label: {
            ZStack {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(isOn ? tint : PPG.cream)
                    .overlay {
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .strokeBorder(PPG.ink, lineWidth: 2.4)
                    }

                if isOn {
                    Image(systemName: "checkmark")
                        .font(.ppg(15, .black))
                        .foregroundStyle(PPG.ink)
                        .transition(.scale.combined(with: .opacity))
                }
            }
            .frame(width: 26, height: 26)
            .scaleEffect(bounce ? 1.22 : 1)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(action == nil)
        .animation(.spring(response: 0.25, dampingFraction: 0.6), value: isOn)
    }
}

// MARK: - 徽章与标签

/// 小圆角标签，带描边。
struct ComicBadge: View {
    let text: String
    var tint: Color = PPG.sunny
    var icon: String?
    /// 用描边款而非实心
    var outlined: Bool = false

    var body: some View {
        HStack(spacing: 4) {
            if let icon {
                Image(systemName: icon).font(.ppg(10, .black))
            }
            Text(text).font(.ppg(11.5, .heavy))
        }
        .foregroundStyle(PPG.ink)
        .padding(.horizontal, 9)
        .padding(.vertical, 4)
        .background {
            Capsule()
                .fill(outlined ? PPG.cream : tint)
                .overlay { Capsule().strokeBorder(PPG.ink, lineWidth: 2) }
        }
    }
}

// MARK: - 区块标题

/// 带星星装饰的区块标题，用来替代系统 `headline`。
struct ComicSectionHeader: View {
    let title: String
    var icon: String?
    var tint: Color = PPG.blossom
    var trailing: AnyView?

    init(_ title: String, icon: String? = nil,
         tint: Color = PPG.blossom, trailing: AnyView? = nil) {
        self.title = title; self.icon = icon
        self.tint = tint; self.trailing = trailing
    }

    var body: some View {
        HStack(spacing: 9) {
            // 小星星当项目符号，比圆点更有卡通味
            StarburstShape(points: 5, innerRatio: 0.45)
                .fill(tint)
                .overlay {
                    StarburstShape(points: 5, innerRatio: 0.45)
                        .stroke(PPG.ink, lineWidth: 1.4)
                }
                .frame(width: 15, height: 15)

            if let icon {
                Image(systemName: icon)
                    .font(.ppg(13, .black))
                    .foregroundStyle(PPG.ink)
            }

            Text(title)
                .font(.ppgSection)
                .foregroundStyle(PPG.ink)

            Spacer(minLength: 0)

            if let trailing { trailing }
        }
    }
}

// MARK: - 空状态

/// 卡通空状态：一个大星形底衬 + 图标 + 标题 + 说明。
struct ComicEmptyState: View {
    let icon: String
    let title: String
    let message: String
    var tint: Color = PPG.bubbles
    /// 可选的行动按钮
    var action: (title: String, handler: () -> Void)?

    @State private var float = false

    var body: some View {
        VStack(spacing: 16) {
            ZStack {
                StarburstShape(points: 14, innerRatio: 0.72)
                    .fill(tint.opacity(0.28))
                    .frame(width: 132, height: 132)
                    .rotationEffect(.degrees(float ? 8 : -8))

                Circle()
                    .fill(PPG.cream)
                    .overlay { Circle().strokeBorder(PPG.ink, lineWidth: 3) }
                    .frame(width: 84, height: 84)

                Image(systemName: icon)
                    .font(.system(size: 36, weight: .black))
                    .foregroundStyle(tint)
            }
            .offset(y: float ? -5 : 5)

            Text(title)
                .font(.ppg(19, .black))
                .foregroundStyle(PPG.ink)

            Text(message)
                .font(.ppgBody)
                .foregroundStyle(PPG.ink.opacity(0.6))
                .multilineTextAlignment(.center)
                .frame(maxWidth: 420)

            if let action {
                Button(action.title, action: action.handler)
                    .buttonStyle(ComicButtonStyle(tint: tint, size: .large))
                    .padding(.top, 4)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            withAnimation(.easeInOut(duration: 2.2).repeatForever(autoreverses: true)) {
                float = true
            }
        }
    }
}

// MARK: - 进度条

/// 粗描边进度条。比系统 `ProgressView` 更有存在感。
struct ComicProgressBar: View {
    /// 0…1
    let value: Double
    var tint: Color = PPG.bubbles
    var height: CGFloat = 16
    /// 显示条纹（表示「进行中」）
    var striped: Bool = false

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(PPG.cream)

                Capsule()
                    .fill(tint)
                    .frame(width: max(height, geo.size.width * min(max(value, 0), 1)))
                    .overlay(alignment: .leading) {
                        if striped {
                            // 斜条纹，示意还在跑
                            Stripes()
                                .fill(PPG.cream.opacity(0.45))
                                .clipShape(Capsule())
                        }
                    }

                Capsule()
                    .strokeBorder(PPG.ink, lineWidth: 2.4)
            }
        }
        .frame(height: height)
    }
}

/// 45° 斜条纹
private struct Stripes: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        let w: CGFloat = 9
        var x = -rect.height
        while x < rect.width + rect.height {
            p.move(to: CGPoint(x: x, y: rect.maxY))
            p.addLine(to: CGPoint(x: x + rect.height, y: rect.minY))
            p.addLine(to: CGPoint(x: x + rect.height + w / 2, y: rect.minY))
            p.addLine(to: CGPoint(x: x + w / 2, y: rect.maxY))
            p.closeSubpath()
            x += w * 2
        }
        return p
    }
}

// MARK: - 数值条

/// 带标签的横条，用于「已用/可用」这类占比展示。
struct ComicStatBar: View {
    let label: String
    let value: String
    /// 0…1
    let fraction: Double
    var tint: Color = PPG.bubbles
    var icon: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 6) {
                if let icon {
                    Image(systemName: icon)
                        .font(.ppg(11, .black))
                        .foregroundStyle(tint)
                }
                Text(label)
                    .font(.ppg(12.5, .bold))
                    .foregroundStyle(PPG.ink.opacity(0.75))
                Spacer(minLength: 8)
                Text(value)
                    .font(.ppg(12.5, .heavy))
                    .foregroundStyle(PPG.ink)
                    .monospacedDigit()
            }
            ComicProgressBar(value: fraction, tint: tint, height: 11)
        }
    }
}


// MARK: - 侧边栏行

/// 侧边栏导航项的按压反馈：轻微右移 + 按压缩放，松开回弹。
struct SidebarRowStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.97 : 1, anchor: .leading)
            .offset(x: configuration.isPressed ? 2 : 0)
            .animation(.spring(response: 0.2, dampingFraction: 0.6),
                       value: configuration.isPressed)
    }
}

// MARK: - 卡通菜单

/// 菜单按钮的贴纸样式。
///
/// **必须用这个而不是给 `Menu` 套 `ButtonStyle`。** macOS 上 `Menu` 只消费
/// `MenuStyle`，`.buttonStyle(ComicButtonStyle(...))` 会被直接忽略 ——
/// 实测结果是渲染成一个没有底色、没有描边的裸系统控件，比旁边的普通按钮
/// 小一大圈，看起来像坏掉了。套上本样式后外观才与 `ComicButtonStyle` 一致。
struct ComicMenuStyle: MenuStyle {
    var tint: Color = PPG.bubbles
    var size: ComicButtonStyle.Size = .regular

    func makeBody(configuration: Configuration) -> some View {
        Menu(configuration)
            .menuStyle(.borderlessButton)
            .fixedSize()
            .font(size.font)
            .foregroundStyle(PPG.ink)
            .padding(.horizontal, size.hPad)
            .padding(.vertical, size.vPad)
            .frame(minHeight: size.minHeight)
            .background {
                RoundedRectangle(cornerRadius: size.corner, style: .continuous)
                    .fill(tint)
                    .overlay {
                        RoundedRectangle(cornerRadius: size.corner, style: .continuous)
                            .strokeBorder(PPG.ink, lineWidth: 2.5)
                    }
            }
            .background {
                RoundedRectangle(cornerRadius: size.corner, style: .continuous)
                    .fill(PPG.ink.opacity(0.9))
                    .offset(x: size.depth, y: size.depth)
            }
    }
}
