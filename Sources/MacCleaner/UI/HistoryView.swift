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
            Divider()

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
        HStack(spacing: 12) {
            Image(systemName: "chart.bar.xaxis")
                .font(.title2)
                .foregroundStyle(.green)

            VStack(alignment: .leading, spacing: 2) {
                Text("清理历史")
                    .font(.headline)
                Text("累计释放量与趋势，只记录体积不记录文件路径")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if !history.records.isEmpty {
                Button(role: .destructive) {
                    showClearConfirm = true
                } label: {
                    Label("清空历史", systemImage: "trash")
                }
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "chart.bar.xaxis")
                .font(.system(size: 44))
                .foregroundStyle(.tertiary)
            Text("还没有清理记录")
                .font(.title3)
            Text("完成一次清理后，这里会显示累计释放量和趋势")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - 汇总卡片

    private var summaryCards: some View {
        HStack(spacing: 12) {
            summaryCard(
                title: "累计释放",
                value: Fmt.size(history.totalFreed),
                icon: "arrow.down.circle.fill",
                color: .green
            )
            summaryCard(
                title: "清理次数",
                value: "\(history.records.count)",
                icon: "checkmark.circle.fill",
                color: .blue
            )
            summaryCard(
                title: "清理项目",
                value: "\(history.totalItems)",
                icon: "doc.fill",
                color: .orange
            )
            summaryCard(
                title: "最近一次",
                value: history.records.last.map {
                    $0.date.formatted(date: .abbreviated, time: .shortened)
                } ?? "—",
                icon: "clock.fill",
                color: .purple
            )
        }
    }

    private func summaryCard(title: String, value: String, icon: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(title, systemImage: icon)
                .font(.caption)
                .foregroundStyle(color)
            Text(value)
                .font(.title3.weight(.semibold))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - 趋势图

    private var chartCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("每日释放量")
                    .font(.callout.weight(.semibold))
                Spacer()
                Picker("", selection: $rangeDays) {
                    ForEach(rangeOptions, id: \.self) { d in
                        Text("近 \(d) 天").tag(d)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 220)
            }

            let data = history.dailyFreed(days: rangeDays)
            let peak = max(data.map(\.freed).max() ?? 0, 1)

            HStack(alignment: .bottom, spacing: 3) {
                ForEach(Array(data.enumerated()), id: \.offset) { _, point in
                    VStack(spacing: 3) {
                        // 顶部留白，让柱子高度差异可见
                        RoundedRectangle(cornerRadius: 2)
                            .fill(point.freed > 0 ? Color.accentColor : Color.secondary.opacity(0.15))
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
            .font(.caption2)
            .foregroundStyle(.tertiary)
        }
        .padding(16)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - 分类汇总

    @ViewBuilder
    private var categoryCard: some View {
        let cats = history.freedByCategory()
        if !cats.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                Text("按类别累计")
                    .font(.callout.weight(.semibold))

                let maxFreed = max(cats.first?.freed ?? 1, 1)
                ForEach(Array(cats.enumerated()), id: \.offset) { _, entry in
                    HStack(spacing: 10) {
                        Image(systemName: entry.category.symbol)
                            .foregroundStyle(.secondary)
                            .frame(width: 18)

                        Text(entry.category.title)
                            .font(.caption)
                            .frame(width: 90, alignment: .leading)

                        GeometryReader { geo in
                            ZStack(alignment: .leading) {
                                RoundedRectangle(cornerRadius: 3)
                                    .fill(Color.secondary.opacity(0.12))
                                RoundedRectangle(cornerRadius: 3)
                                    .fill(Color.accentColor.opacity(0.7))
                                    .frame(width: max(3, geo.size.width * CGFloat(Double(entry.freed) / Double(maxFreed))))
                            }
                        }
                        .frame(height: 12)

                        Text(Fmt.size(entry.freed))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                            .frame(width: 70, alignment: .trailing)
                    }
                }
            }
            .padding(16)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
        }
    }

    // MARK: - 最近记录

    private var recentCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("最近记录")
                .font(.callout.weight(.semibold))

            VStack(spacing: 0) {
                ForEach(Array(history.records.suffix(20).reversed().enumerated()), id: \.element.id) { idx, rec in
                    HStack(spacing: 12) {
                        Image(systemName: rec.failureCount > 0 ? "exclamationmark.circle" : "checkmark.circle")
                            .foregroundStyle(rec.failureCount > 0 ? .orange : .green)

                        Text(rec.date.formatted(date: .abbreviated, time: .shortened))
                            .font(.caption)
                            .frame(width: 150, alignment: .leading)

                        Text("\(rec.itemCount) 项")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .frame(width: 60, alignment: .leading)

                        if rec.failureCount > 0 {
                            Text("\(rec.failureCount) 项失败")
                                .font(.caption2)
                                .foregroundStyle(.orange)
                        }

                        Spacer()

                        Text(Fmt.size(rec.freed))
                            .font(.callout.weight(.medium))
                            .foregroundStyle(.green)
                            .monospacedDigit()
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)

                    if idx != min(history.records.count, 20) - 1 {
                        Divider().padding(.leading, 36)
                    }
                }
            }
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
        }
    }
}
