import SwiftUI

/// 磁盘总览：大的环形进度 + 容量数字
struct DiskOverviewView: View {
    let volume: VolumeInfo
    let reclaimable: Int64

    var body: some View {
        HStack(spacing: 28) {
            ZStack {
                Circle()
                    .stroke(Color.secondary.opacity(0.15), lineWidth: 18)
                Circle()
                    .trim(from: 0, to: min(volume.usedFraction, 1))
                    .stroke(
                        AngularGradient(
                            gradient: Gradient(colors: ringColors),
                            center: .center,
                            startAngle: .degrees(0),
                            endAngle: .degrees(360 * max(volume.usedFraction, 0.001))
                        ),
                        style: StrokeStyle(lineWidth: 18, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))
                    .animation(.easeInOut(duration: 0.8), value: volume.usedFraction)

                VStack(spacing: 2) {
                    Text(Fmt.percent(volume.usedFraction))
                        .font(.system(size: 30, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                    Text("已使用")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(width: 150, height: 150)

            VStack(alignment: .leading, spacing: 14) {
                statRow(title: "总容量", value: Fmt.size(volume.total), color: .secondary)
                statRow(title: "已使用", value: Fmt.size(volume.used), color: .orange)
                statRow(title: "可用", value: Fmt.size(volume.free), color: .green)
                Divider().frame(width: 220)
                statRow(title: "可清理", value: Fmt.size(reclaimable), color: .blue)
            }
            Spacer()
        }
        .padding(22)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
    }

    private var ringColors: [Color] {
        if volume.usedFraction > 0.9 { return [.red, .orange] }
        if volume.usedFraction > 0.75 { return [.orange, .yellow] }
        return [.blue, .cyan]
    }

    private func statRow(title: String, value: String, color: Color) -> some View {
        HStack {
            Circle().fill(color).frame(width: 8, height: 8)
            Text(title).font(.callout).foregroundStyle(.secondary)
            Spacer()
            Text(value).font(.callout).monospacedDigit().fontWeight(.medium)
        }
        .frame(width: 220)
    }
}
