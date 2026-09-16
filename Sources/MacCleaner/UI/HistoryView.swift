import SwiftUI

/// 清理历史与趋势视图。
struct HistoryView: View {
    @ObservedObject var history: CleanupHistory

    @State private var rangeDays = 30
    @State private var showClearConfirm = false

    private let rangeOptions = [7, 30, 90]

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider().overlay(PPG.ink.opacity(0.2))

            if history.records.isEmpty {
                emptyState
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        summaryCards
                        chartCard
                        categoryCard
                        recentCard
                    }
                    .padding(18)
                }
            }
        }
        .alert("清空清理历史？", isPresented: $showClearConfirm) {
            Button("取消", role: .cancel) {}
            Button("清空", role: .destructive) { history.clear() }
        } message: {
            Text("只会删除统计数据，不影响任何已清理的文件。")
        }
    }

    // MARK: - 顶部

    private var toolbar: some View {
        VStack(alignment: .leading, spacing: 5) {
            ComicSectionHeader(
                "清理历史",
                icon: "chart.bar.xaxis",
                tint: PPG.buttercup,
                trailing: AnyView(clearHistoryButton)
            )

            Text("累计释放量与趋势，只记录体积不记录文件路径")
                .font(.ppgCaption)
                .foregroundStyle(PPG.ink.opacity(0.6))
                .padding(.leading, 24)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
        .background(PPG.cream.opacity(0.7))
    }

    /// 破坏性操作：红底白字。确认弹窗的文案与 role 均保持不变。
    @ViewBuilder
    private var clearHistoryButton: some View {
        if !history.records.isEmpty {
            Button(role: .destructive) {
                showClearConfirm = true
            } label: {
                Label("清空历史", systemImage: "trash")
            }
            .buttonStyle(ComicButtonStyle(tint: PPG.dangerDeep, size: .regular, textColor: .white))
        }
    }

    private var emptyState: some View {
        ComicEmptyState(
            icon: "chart.bar.xaxis",
            title: "还没有清理记录",
            message: "完成一次清理后，这里会显示累计释放量和趋势",
            tint: PPG.grape
        )
        .comicCard(tint: PPG.grape, padding: 10)
        .padding(18)
    }

    // MARK: - 汇总卡片

    private var summaryCards: some View {
        HStack(spacing: 12) {
            summaryCard(
                title: "累计释放",
                value: Fmt.size(history.totalFreed),
                icon: "arrow.down.circle.fill",
                color: PPG.buttercup
            )
            summaryCard(
                title: "清理次数",
                value: "\(history.records.count)",
                icon: "checkmark.circle.fill",
                color: PPG.bubbles
            )
            summaryCard(
                title: "清理项目",
                value: "\(history.totalItems)",
                icon: "doc.fill",
                color: PPG.sunny
            )
            summaryCard(
                title: "最近一次",
                value: history.records.last.map {
                    $0.date.formatted(date: .abbreviated, time: .shortened)
                } ?? "—",
                icon: "clock.fill",
                color: PPG.grape
            )
        }
    }

    private func summaryCard(title: String, value: String, icon: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 7) {
                ZStack {
                    Circle()
                        .fill(color)
                        .overlay { Circle().strokeBorder(PPG.ink, lineWidth: 1.8) }
                        .frame(width: 24, height: 24)
                    Image(systemName: icon)
                        .font(.ppg(11, .black))
                        .foregroundStyle(PPG.ink)
                }

                Text(title)
                    .font(.ppg(12, .heavy))
                    .foregroundStyle(PPG.ink.opacity(0.7))
            }

            Text(value)
                .font(.ppg(17, .black))
                .foregroundStyle(PPG.ink)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .comicCard(tint: color, padding: 13)
    }

    // MARK: - 趋势图

    private var chartCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            ComicSectionHeader(
                "每日释放量",
                icon: "chart.bar.fill",
                tint: PPG.blossom,
                trailing: AnyView(rangeButtons)
            )

            let data = history.dailyFreed(days: rangeDays)
            let peak = max(data.map(\.freed).max() ?? 0, 1)

            HStack(alignment: .bottom, spacing: 3) {
                ForEach(Array(data.enumerated()), id: \.offset) { idx, point in
                    VStack(spacing: 3) {
                        // 顶部留白，让柱子高度差异可见
                        RoundedRectangle(cornerRadius: 3, style: .continuous)
                            .fill(point.freed > 0 ? PPG.girl(idx) : PPG.ink.opacity(0.08))
                            .overlay {
                                RoundedRectangle(cornerRadius: 3, style: .continuous)
                                    .strokeBorder(
                                        PPG.ink.opacity(point.freed > 0 ? 0.85 : 0.12),
                                        lineWidth: 1
                                    )
                            }
                            .frame(height: max(2, CGFloat(Double(point.freed) / Double(peak)) * 110))
                            .help("\(point.date.formatted(date: .abbreviated, time: .omitted))：\(Fmt.size(point.freed))")
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            .frame(height: 116)

            HStack {
                Text(data.first?.date.formatted(date: .abbreviated, time: .omitted) ?? "")
                Spacer()
                Text("峰值 \(Fmt.size(peak))")
                Spacer()
                Text(data.last?.date.formatted(date: .abbreviated, time: .omitted) ?? "")
            }
            .font(.ppgCaption)
            .foregroundStyle(PPG.ink.opacity(0.5))
            .monospacedDigit()
        }
        .comicCard(tint: PPG.blossom, padding: 16)
    }

    /// 时间范围选择。原来 220pt 宽的分段控件换成三颗卡通按钮，
    /// 命中区从系统控件的 ~22pt 提到 42pt。
    @ViewBuilder
    private var rangeButtons: some View {
        HStack(spacing: 8) {
            ForEach(rangeOptions, id: \.self) { d in
                let isOn = rangeDays == d
                Button("近 \(d) 天") { rangeDays = d }
                    .buttonStyle(ComicButtonStyle(
                        tint: isOn ? PPG.blossom : PPG.cream,
                        size: .regular,
                        burst: false,
                        textColor: isOn ? .white : PPG.ink,
                        outlined: !isOn
                    ))
            }
        }
    }

    // MARK: - 分类汇总

    @ViewBuilder
    private var categoryCard: some View {
        let cats = history.freedByCategory()
        if !cats.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                ComicSectionHeader("按类别累计", icon: "square.grid.2x2.fill", tint: PPG.bubbles)

                let maxFreed = max(cats.first?.freed ?? 1, 1)
                ForEach(Array(cats.enumerated()), id: \.offset) { idx, entry in
                    // 按固定序号循环取主题色，不用 hashValue（每进程加盐，重启后颜色错位）
                    let tint = PPG.girl(idx)

                    HStack(spacing: 10) {
                        ZStack {
                            Circle()
                                .fill(tint)
                                .overlay { Circle().strokeBorder(PPG.ink, lineWidth: 1.8) }
                                .frame(width: 24, height: 24)
                            Image(systemName: entry.category.symbol)
                                .font(.ppg(11, .black))
                                .foregroundStyle(PPG.ink)
                        }

                        Text(entry.category.title)
                            .font(.ppg(12.5, .heavy))
                            .foregroundStyle(PPG.ink)
                            .frame(width: 96, alignment: .leading)

                        ComicProgressBar(
                            value: Double(entry.freed) / Double(maxFreed),
                            tint: tint,
                            height: 12
                        )

                        Text(Fmt.size(entry.freed))
                            .font(.ppg(12.5, .black))
                            .foregroundStyle(PPG.ink)
                            .monospacedDigit()
                            .frame(width: 74, alignment: .trailing)
                    }
                }
            }
            .comicCard(tint: PPG.bubbles, padding: 16)
        }
    }

    // MARK: - 最近记录

    private var recentCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            ComicSectionHeader("最近记录", icon: "clock.arrow.circlepath", tint: PPG.grape)

            VStack(spacing: 4) {
                ForEach(Array(history.records.suffix(20).reversed().enumerated()), id: \.element.id) { idx, rec in
                    HStack(spacing: 12) {
                        ZStack {
                            Circle()
                                .fill(rec.failureCount > 0 ? PPG.danger : PPG.buttercup)
                                .overlay { Circle().strokeBorder(PPG.ink, lineWidth: 1.8) }
                                .frame(width: 26, height: 26)
                            Image(systemName: rec.failureCount > 0 ? "exclamationmark.circle" : "checkmark.circle")
                                .font(.ppg(12, .black))
                                .foregroundStyle(PPG.ink)
                        }

                        Text(rec.date.formatted(date: .abbreviated, time: .shortened))
                            .font(.ppg(12, .heavy))
                            .foregroundStyle(PPG.ink.opacity(0.8))
                            .monospacedDigit()
                            .frame(width: 150, alignment: .leading)

                        Text("\(rec.itemCount) 项")
                            .font(.ppgCaption)
                            .foregroundStyle(PPG.ink.opacity(0.55))
                            .monospacedDigit()
                            .frame(width: 62, alignment: .leading)

                        if rec.failureCount > 0 {
                            ComicBadge(text: "\(rec.failureCount) 项失败",
                                       tint: PPG.danger,
                                       icon: "exclamationmark.triangle.fill")
                        }

                        Spacer()

                        Text(Fmt.size(rec.freed))
                            .font(.ppg(13.5, .black))
                            .foregroundStyle(PPG.ink)
                            .monospacedDigit()
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    // 斑马纹：行内没有可执行操作，所以不做整行点击，
                    // 只靠交替底色帮横向读表
                    .background {
                        RoundedRectangle(cornerRadius: 11, style: .continuous)
                            .fill(idx.isMultiple(of: 2) ? PPG.ink.opacity(0.045) : .clear)
                    }
                }
            }
        }
        .comicCard(tint: PPG.grape, padding: 16)
    }
}
