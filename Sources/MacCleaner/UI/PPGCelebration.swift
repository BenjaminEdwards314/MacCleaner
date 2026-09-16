import SwiftUI

// MARK: - 清理完成庆祝

/// 清理成功后的全屏庆祝动画。
///
/// 这是整个应用里最重要的一个正反馈 —— 用户点完「清理所选」后，
/// 如果只是弹一个系统 alert 说「已清理 N 项」，成就感很弱。
/// 这里改成：星星从中心炸开 + 彩色纸屑飘落 + 大大的释放量数字。
///
/// 只在**确实清理成功**时出现（`freed > 0`）。全部失败时不出现，
/// 否则等于在庆祝一次失败。
struct CleanCelebrationView: View {
    /// 释放的字节数
    let freed: Int64
    /// 清理项数
    let count: Int
    /// 关闭回调
    let onDismiss: () -> Void

    @State private var starsOut = false
    @State private var cardIn = false
    @State private var confettiFall = false
    @State private var ringPulse = false

    /// 纸屑的颜色与初始位置。用固定种子生成，避免每次重绘都跳位。
    private let confetti: [(x: CGFloat, delay: Double, color: Color, spin: Double)] = {
        var out: [(CGFloat, Double, Color, Double)] = []
        for i in 0..<28 {
            // 用取模运算做伪随机，保证同一进程内稳定
            let x = CGFloat((i * 37) % 100) / 100
            let delay = Double((i * 53) % 60) / 100
            let color = PPG.girl(i)
            let spin = Double((i * 71) % 360)
            out.append((x, delay, color, spin))
        }
        return out
    }()

    var body: some View {
        ZStack {
            // 半透明遮罩。用带蓝调的深色而非纯黑 ——
            // 纯黑叠在米色卡片上会发浑，看起来脏。
            Color(red: 0.16, green: 0.15, blue: 0.26).opacity(0.52)
                .ignoresSafeArea()
                .onTapGesture { onDismiss() }

            // 放射星星
            ZStack {
                ForEach(0..<16, id: \.self) { i in
                    let angle = Double(i) / 16 * 2 * .pi
                    let dist: CGFloat = starsOut ? 340 : 0
                    StarburstShape(points: 4, innerRatio: 0.3)
                        .fill(PPG.girl(i))
                        .overlay {
                            StarburstShape(points: 4, innerRatio: 0.3)
                                .stroke(PPG.ink, lineWidth: 2)
                        }
                        .frame(width: 30, height: 30)
                        .rotationEffect(.degrees(starsOut ? Double(i) * 90 + 180 : 0))
                        .offset(x: CGFloat(cos(angle)) * dist,
                                y: CGFloat(sin(angle)) * dist)
                        .opacity(starsOut ? 0 : 1)
                        .scaleEffect(starsOut ? 1.5 : 0.2)
                }
            }
            .animation(.easeOut(duration: 0.75), value: starsOut)

            // 纸屑
            GeometryReader { geo in
                ForEach(0..<confetti.count, id: \.self) { i in
                    let c = confetti[i]
                    RoundedRectangle(cornerRadius: 2)
                        .fill(c.color)
                        .overlay {
                            RoundedRectangle(cornerRadius: 2)
                                .stroke(PPG.ink, lineWidth: 1)
                        }
                        .frame(width: 11, height: 15)
                        .rotationEffect(.degrees(confettiFall ? c.spin + 540 : c.spin))
                        .position(
                            x: c.x * geo.size.width,
                            y: confettiFall ? geo.size.height + 40 : -50
                        )
                        .animation(
                            .easeIn(duration: 2.4).delay(c.delay),
                            value: confettiFall
                        )
                }
            }
            .allowsHitTesting(false)

            // 中央卡片
            VStack(spacing: 14) {
                ZStack {
                    // 脉冲光环
                    Circle()
                        .stroke(PPG.sunny, lineWidth: 5)
                        .frame(width: ringPulse ? 128 : 92,
                               height: ringPulse ? 128 : 92)
                        .opacity(ringPulse ? 0 : 0.85)

                    StarburstShape(points: 14, innerRatio: 0.7)
                        .fill(PPG.sunny)
                        .overlay {
                            StarburstShape(points: 14, innerRatio: 0.7)
                                .stroke(PPG.ink, lineWidth: 3)
                        }
                        .frame(width: 104, height: 104)
                        .rotationEffect(.degrees(cardIn ? 0 : -30))
                        .scaleEffect(cardIn ? 1 : 0.3)

                    Image(systemName: "sparkles")
                        .font(.system(size: 44, weight: .black))
                        .foregroundStyle(PPG.ink)
                        .scaleEffect(cardIn ? 1 : 0.2)
                }

                Text("清理完成！")
                    .font(.ppg(30, .black))
                    .foregroundStyle(PPG.ink)

                VStack(spacing: 4) {
                    Text("释放了 \(Fmt.size(freed))")
                        .font(.ppg(24, .black))
                        .foregroundStyle(PPG.ink)
                        .monospacedDigit()
                    Text("共 \(count) 项，已移入废纸篓，可随时恢复")
                        .font(.ppgBody)
                        .foregroundStyle(PPG.ink.opacity(0.62))
                }

                Button("太棒了") { onDismiss() }
                    .buttonStyle(ComicButtonStyle(tint: PPG.buttercup, size: .large))
                    .padding(.top, 6)
            }
            .padding(34)
            .background(PPG.cream, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .strokeBorder(PPG.ink, lineWidth: 4)
            }
            .background {
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .fill(PPG.ink.opacity(0.9))
                    .offset(x: 7, y: 7)
            }
            .scaleEffect(cardIn ? 1 : 0.6)
            .opacity(cardIn ? 1 : 0)
            .onTapGesture { onDismiss() }
        }
        .onAppear {
            starsOut = true
            confettiFall = true

            withAnimation(.spring(response: 0.5, dampingFraction: 0.55)) {
                cardIn = true
            }
            withAnimation(.easeOut(duration: 1.1).repeatForever(autoreverses: false)) {
                ringPulse = true
            }

            // 自动关闭。给足时间看数字，又不至于挡路太久。
            DispatchQueue.main.asyncAfter(deadline: .now() + 4.5) {
                onDismiss()
            }
        }
    }
}
