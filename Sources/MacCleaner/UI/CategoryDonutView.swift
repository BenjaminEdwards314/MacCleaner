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
                Circle().stroke(Color.secondary.opacity(0.12), lineWidth: 26)

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

                VStack(spacing: 2) {
                    Text(Fmt.size(total))
                        .font(.system(size: 22, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                    Text("可清理总量")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(width: 180, height: 180)

            // 图例
            VStack(alignment: .leading, spacing: 7) {
                ForEach(groups) { g in
                    HStack(spacing: 8) {
                        RoundedRectangle(cornerRadius: 3)
                            .fill(color(for: g.category))
                            .frame(width: 11, height: 11)
                        Text(g.category.title)
                            .font(.caption)
                            .fontWeight(selected == g.category ? .semibold : .regular)
                        Spacer()
                        Text(Fmt.size(g.totalSize))
                            .font(.caption)
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
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
        .padding(22)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
    }

    func color(for c: CleanupCategory) -> Color {
        switch c {
        case .userCache: return .blue
        case .systemCache: return .cyan
        case .logs: return .gray
        case .trash: return .brown
        case .developerCache: return .purple
        case .crashReports: return .red
        case .crashpad: return .yellow
        case .downloadsOld: return .orange
        case .appSupport: return .indigo
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
