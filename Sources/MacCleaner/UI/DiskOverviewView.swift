import SwiftUI

/// 磁盘总览：卡通环形进度 + 容量明细。
///
/// 环本身加粗并描黑边，数字换成圆润粗体，整体套贴纸卡片 ——
/// 与系统那种细线灰环拉开距离。
struct DiskOverviewView: View {
    let volume: VolumeInfo
    let reclaimable: Int64

    /// 环的脉冲动画（仅在高占用时出现，作为警示）
    @State private var pulse = false

    private var frac: Double { min(max(volume.usedFraction, 0), 1) }

    var body: some View {
        HStack(alignment: .center, spacing: 26) {
            ring
            VStack(alignment: .leading, spacing: 12) {
                Text("磁盘使用情况")
                    .font(.ppgSection)
                    .foregroundStyle(PPG.ink)

                ComicStatBar(label: "已使用", value: Fmt.size(volume.used),
                             fraction: frac, tint: ringTint, icon: "chart.pie.fill")

                HStack(spacing: 8) {
                    ComicBadge(text: "总容量 \(Fmt.size(volume.total))",
                               tint: PPG.cream, icon: "internaldrive.fill", outlined: true)
                    ComicBadge(text: "可用 \(Fmt.size(volume.free))",
                               tint: PPG.buttercup, icon: "checkmark.circle.fill")
                }

                Divider().overlay(PPG.ink.opacity(0.15))

                HStack(spacing: 8) {
                    Image(systemName: "sparkles")
                        .font(.ppg(13, .black))
                        .foregroundStyle(PPG.blossom)
                    Text("可清理")
                        .font(.ppg(12.5, .bold))
                        .foregroundStyle(PPG.ink.opacity(0.75))
                    Spacer(minLength: 10)
                    Text(Fmt.size(reclaimable))
                        .font(.ppg(15, .black))
                        .foregroundStyle(PPG.ink)
                        .monospacedDigit()
                }
            }
            Spacer(minLength: 0)
        }
        .comicCard(tint: ringTint, padding: 20)
        .onAppear {
            guard frac > 0.9 else { return }
            withAnimation(.easeInOut(duration: 1.1).repeatForever(autoreverses: true)) {
                pulse = true
            }
        }
    }

    private var ring: some View {
        ZStack {
            // 底环
            Circle()
                .stroke(PPG.cream, lineWidth: 22)
                .overlay { Circle().strokeBorder(PPG.ink, lineWidth: 2.5) }

            // 进度弧
            Circle()
                .trim(from: 0, to: max(frac, 0.001))
                .stroke(ringTint,
                        style: StrokeStyle(lineWidth: 22, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(.easeInOut(duration: 0.9), value: frac)

            // 中心小圆盘
            Circle()
                .fill(PPG.cream)
                .overlay { Circle().strokeBorder(PPG.ink, lineWidth: 2.5) }
                .padding(28)

            VStack(spacing: 1) {
                Text(Fmt.percent(volume.usedFraction))
                    .font(.ppg(27, .black))
                    .foregroundStyle(PPG.ink)
                    .monospacedDigit()
                Text("已使用")
                    .font(.ppg(10.5, .bold))
                    .foregroundStyle(PPG.ink.opacity(0.5))
            }
        }
        .frame(width: 152, height: 152)
        .scaleEffect(pulse ? 1.025 : 1)
        // 占用过高时在环外冒个警示星
        .overlay(alignment: .topTrailing) {
            if frac > 0.9 {
                ComicBadge(text: "空间紧张", tint: PPG.danger, icon: "exclamationmark.triangle.fill")
                    .offset(x: 18, y: -4)
            }
        }
    }

    /// 占用越高越红。用主题色而非系统色，保证与整体一致。
    private var ringTint: Color {
        if frac > 0.9 { return PPG.danger }
        if frac > 0.75 { return PPG.sunny }
        return PPG.buttercup
    }
}
