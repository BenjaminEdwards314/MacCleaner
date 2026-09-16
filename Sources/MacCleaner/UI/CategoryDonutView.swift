import SwiftUI

/// 类别环形图：把各清理类别按体积画成甜甜圈，可点击筛选
struct CategoryDonutView: View {
    let groups: [CleanupGroup]
    @Binding var selected: CleanupCategory?

    private var total: Int64 { groups.reduce(0) { $0 + $1.totalSize } }

    private var segments: [(CleanupCategory, Int64, Double, Double)] {
        guard total > 0 else { return [] }
        var start = 0.0
        var out: [(CleanupCategory, Int64, Double, Double)] = []
        for g in groups where g.totalSize > 0 {
            let frac = Double(g.totalSize) / Double(total)
            out.append((g.category, g.totalSize, start, frac))
            start += frac
        }
        return out
    }

    var body: some View {
        VStack(spacing: 18) {
            ZStack {
                Circle().stroke(PPG.cream, lineWidth: 26)
                Circle().strokeBorder(PPG.ink.opacity(0.9), lineWidth: 2.2)

                ForEach(segments, id: \.0) { seg in
                    Circle()
                        .trim(from: seg.2, to: seg.2 + seg.3 - 0.004)
                        .stroke(
                            color(for: seg.0),
                            style: StrokeStyle(lineWidth: selected == seg.0 ? 34 : 26, lineCap: .butt)
                        )
                        .rotationEffect(.degrees(-90))
                        .animation(.easeInOut(duration: 0.25), value: selected)
                        .onTapGesture {
                            selected = (selected == seg.0) ? nil : seg.0
                        }
                        .help("\(seg.0.title)：\(Fmt.size(seg.1))")
                }

                VStack(spacing: 1) {
                    Text(Fmt.size(total))
                        .font(.ppg(21, .black))
                        .foregroundStyle(PPG.ink)
                        .monospacedDigit()
                    Text("可清理总量")
                        .font(.ppg(10.5, .bold))
                        .foregroundStyle(PPG.ink.opacity(0.5))
                }
            }
            .frame(width: 180, height: 180)

            // 图例
            VStack(alignment: .leading, spacing: 7) {
                ForEach(groups) { g in
                    HStack(spacing: 8) {
                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .fill(color(for: g.category))
                            .overlay {
                                RoundedRectangle(cornerRadius: 4, style: .continuous)
                                    .strokeBorder(PPG.ink, lineWidth: 1.8)
                            }
                            .frame(width: 14, height: 14)
                        Text(g.category.title)
                            .font(.ppg(12.5, selected == g.category ? .black : .semibold))
                            .foregroundStyle(PPG.ink)
                        Spacer()
                        Text(Fmt.size(g.totalSize))
                            .font(.ppg(12.5, .heavy))
                            .monospacedDigit()
                            .foregroundStyle(PPG.ink.opacity(0.6))
                    }
                    .padding(.vertical, 3)
                    .padding(.horizontal, 6)
                    .background {
                        if selected == g.category {
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(color(for: g.category).opacity(0.28))
                        }
                    }
                    .contentShape(Rectangle())
                    .onTapGesture {
                        selected = (selected == g.category) ? nil : g.category
                    }
                    .opacity(selected == nil || selected == g.category ? 1 : 0.4)
                }
            }
            .frame(maxWidth: 230)
        }
        .comicCard(tint: PPG.grape, padding: 20)
    }

    func color(for c: CleanupCategory) -> Color {
        switch c {
        case .userCache: return PPG.bubbles
        case .systemCache: return Color(red: 0.42, green: 0.88, blue: 0.90)
        case .logs: return Color(red: 0.72, green: 0.70, blue: 0.78)
        case .trash: return Color(red: 0.85, green: 0.66, blue: 0.42)
        case .developerCache: return PPG.grape
        case .crashReports: return PPG.danger
        case .crashpad: return PPG.sunny
        case .downloadsOld: return Color(red: 1.00, green: 0.60, blue: 0.32)
        case .appSupport: return Color(red: 0.55, green: 0.62, blue: 0.98)
        case .largeFiles: return .pink
        case .tempFiles: return .teal
        // 这三个类别不出现在清理页的环形图里（它们来自重复文件/卸载视图），
        // 但枚举是共享的，颜色必须给全，否则 switch 不穷尽。
        case .duplicates: return .mint
        case .appResidue: return .purple
        case .appBundle: return .red
        case .orphanResidue: return .orange
        }
    }
}
