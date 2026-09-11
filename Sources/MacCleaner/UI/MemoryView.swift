import SwiftUI

/// 内存视图：实时显示内存分布、压力等级，以及占用最高的进程。
///
/// 设计取向与「清理」页一致 —— 只读展示 + 明确指引，
/// 不提供会把用户带到危险境地的操作。
struct MemoryView: View {
    @ObservedObject var probe: MemoryProbe

    @State private var cacheDropMessage: String?
    @State private var cacheDropOK = false
    @State private var showCacheDropAlert = false

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                // 一行两块：左边「压力 + 数值」，右边「内存构成」。
                // 两块并排后高度接近，不再是左列竖着堆两卡、
                // 右侧留一大片空白。
                HStack(alignment: .top, spacing: 18) {
                    header
                        .frame(maxWidth: .infinity)

                    breakdownCard
                        .frame(maxWidth: .infinity)
                }

                processCard

                adviceCard
            }
            .padding(20)
        }
        .onAppear { probe.start() }
        .onDisappear { probe.stop() }
        .alert(cacheDropOK ? "已执行" : "执行失败", isPresented: $showCacheDropAlert) {
            Button("好") {}
        } message: {
            Text(cacheDropMessage ?? "")
        }
    }

    // MARK: - 顶部：压力 + 大环

    private var header: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 8) {
                Image(systemName: probe.stats.pressure.symbol)
                    .foregroundStyle(pressureColor)
                Text("内存压力：\(probe.stats.pressure.label)")
                    .font(.headline)
                    .foregroundStyle(pressureColor)
                Spacer()
            }

            HStack(alignment: .center, spacing: 20) {
                ring

                // 半宽列里横向放不下「环形图 + 两列数值」，
                // 所以这里改成一列四项，跟着环形图的高度走。
                VStack(alignment: .leading, spacing: 11) {
                    statRow(title: "物理内存", value: Fmt.size(probe.stats.total), color: .secondary)
                    statRow(title: "已使用", value: Fmt.size(probe.stats.used), color: .orange)
                    statRow(title: "可用", value: Fmt.size(probe.stats.available), color: .green)
                    statRow(title: "App 内存", value: Fmt.size(probe.stats.app), color: .blue)
                }
            }
        }
        .padding(22)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
    }

    /// 顶部环形图。抽出来是为了让 header 的排版逻辑更清楚。
    private var ring: some View {
        ZStack {
            Circle()
                .stroke(Color.secondary.opacity(0.15), lineWidth: 18)
            Circle()
                .trim(from: 0, to: min(probe.stats.usedFraction, 1))
                .stroke(
                    AngularGradient(
                        gradient: Gradient(colors: ringColors),
                        center: .center,
                        startAngle: .degrees(0),
                        endAngle: .degrees(360 * max(probe.stats.usedFraction, 0.001))
                    ),
                    style: StrokeStyle(lineWidth: 18, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
                .animation(.easeInOut(duration: 0.6), value: probe.stats.usedFraction)

            VStack(spacing: 2) {
                Text(Fmt.percent(probe.stats.usedFraction))
                    .font(.system(size: 28, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                Text("已使用")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: 130, height: 130)
    }

    private var ringColors: [Color] {
        switch probe.stats.pressure {
        case .critical: return [.red, .orange]
        case .warning: return [.orange, .yellow]
        case .normal: return [.blue, .cyan]
        }
    }

    private var pressureColor: Color {
        switch probe.stats.pressure {
        case .normal: return .green
        case .warning: return .orange
        case .critical: return .red
        }
    }

    /// 一行统计。宽度交给父容器决定 —— 之前写死 240pt 会让它在窄列里溢出、
    /// 在宽列里又留出空白。
    private func statRow(title: String, value: String, color: Color) -> some View {
        HStack(spacing: 8) {
            Circle().fill(color).frame(width: 8, height: 8)
            Text(title)
                .font(.callout)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Spacer(minLength: 12)
            Text(value)
                .font(.callout)
                .monospacedDigit()
                .fontWeight(.medium)
                .lineLimit(1)
        }
    }

    // MARK: - 内存构成

    private var breakdownCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("内存构成")
                .font(.headline)

            if probe.stats.total > 0 {
                // 堆叠条：直观展示各部分的相对占比
                GeometryReader { geo in
                    let w = geo.size.width
                    let total = Double(probe.stats.total)
                    HStack(spacing: 1) {
                        segment(width: w * Double(probe.stats.app) / total,
                                color: .blue, label: "App")
                        segment(width: w * Double(probe.stats.wired) / total,
                                color: .purple, label: "联动")
                        segment(width: w * Double(probe.stats.compressed) / total,
                                color: .teal, label: "压缩")
                        segment(width: w * Double(probe.stats.cachedFiles) / total,
                                color: .gray, label: "缓存")
                        segment(width: w * Double(probe.stats.available) / total,
                                color: .green.opacity(0.55), label: "空闲")
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 5))
                }
                .frame(height: 22)
            }

            legendRow("App 内存", value: probe.stats.app, color: .blue,
                      note: "应用实际占用")
            legendRow("联动内存", value: probe.stats.wired, color: .purple,
                      note: "内核占用，不可换出")
            legendRow("已压缩", value: probe.stats.compressed, color: .teal,
                      note: compressionNote)
            legendRow("缓存文件", value: probe.stats.cachedFiles, color: .gray,
                      note: "系统可自动回收")
            legendRow("空闲可用", value: probe.stats.available, color: .green,
                      note: "含 inactive 与可清除页")

            if probe.stats.swapTotal > 0 {
                Divider()
                HStack {
                    Label("交换空间", systemImage: "arrow.left.arrow.right")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text("\(Fmt.size(probe.stats.swapUsed)) / \(Fmt.size(probe.stats.swapTotal))")
                        .font(.callout)
                        .monospacedDigit()
                        .foregroundStyle(probe.stats.isSwapping ? .orange : .secondary)
                }
            }

            Text("更新于 \(probe.stats.sampledAt.formatted(date: .omitted, time: .standard))")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
    }

    private var compressionNote: String {
        let ratio = probe.stats.compressionRatio
        if probe.stats.compressed <= 0 { return "未被压缩" }
        return String(format: "压缩率 %.1fx", ratio)
    }

    private func segment(width: Double, color: Color, label: String) -> some View {
        Rectangle()
            .fill(color)
            .frame(width: max(width, 0))
            .help(label)
    }

    private func legendRow(_ title: String, value: Int64, color: Color, note: String) -> some View {
        HStack(spacing: 8) {
            RoundedRectangle(cornerRadius: 2)
                .fill(color)
                .frame(width: 10, height: 10)
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.callout)
                Text(note).font(.caption2).foregroundStyle(.tertiary)
            }
            Spacer()
            Text(Fmt.size(value))
                .font(.callout)
                .monospacedDigit()
        }
    }

    // MARK: - 进程

    private var processCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("内存占用最高的进程")
                    .font(.headline)
                Spacer()
                Text("常驻内存")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }

            if probe.topProcesses.isEmpty {
                Text("正在读取进程列表…")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 160)
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(probe.topProcesses.enumerated()), id: \.element.id) { idx, p in
                        HStack(spacing: 10) {
                            Text("\(idx + 1)")
                                .font(.caption)
                                .monospacedDigit()
                                .foregroundStyle(.tertiary)
                                .frame(width: 16, alignment: .trailing)
                            Image(systemName: "app.dashed")
                                .foregroundStyle(.tertiary)
                                .font(.caption)
                            Text(p.name)
                                .font(.callout)
                                .lineLimit(1)
                                .truncationMode(.middle)
                            Spacer()
                            Text(Fmt.size(p.rss))
                                .font(.callout)
                                .monospacedDigit()
                                .foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 7)
                        .padding(.horizontal, 8)
                        .background(idx % 2 == 0 ? Color.clear : Color.secondary.opacity(0.05))

                        if idx < probe.topProcesses.count - 1 {
                            Divider().opacity(0.4)
                        }
                    }
                }
            }

            Text("这只是观察，不会结束任何进程。要释放内存请退出不需要的应用。")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .padding(18)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
    }

    // MARK: - 说明与操作

    private var adviceCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("关于「内存清理」", systemImage: "info.circle")
                .font(.headline)

            Text("macOS 会自动管理内存：应用退出后其内存立即释放，缓存文件在需要时由系统回收。"
                 + "因此本工具不提供「一键释放 N GB」的按钮 —— 那个数字通常是假的。")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if probe.stats.pressure != .normal {
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                    Text(pressureAdvice)
                        .font(.callout)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(10)
                .background(Color.orange.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))
            }

            Divider()

            HStack(spacing: 12) {
                Button {
                    Task {
                        let r = await probe.dropFileCaches()
                        cacheDropOK = r.ok
                        cacheDropMessage = r.message
                        showCacheDropAlert = true
                        probe.sample()
                    }
                } label: {
                    Label("回收文件缓存", systemImage: "arrow.clockwise")
                }
                .help("请求系统释放磁盘缓冲区。需要管理员权限，通常不会成功。")

                Text("仅影响磁盘缓存，不触碰应用内存与任何文件。")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(18)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
    }

    private var pressureAdvice: String {
        var parts: [String] = []
        if probe.stats.isSwapping {
            parts.append("系统正在使用交换空间，说明物理内存已经不够用。")
        }
        parts.append("建议退出列表中占用最高的应用，尤其是浏览器标签页和未使用的重型程序。")
        if probe.stats.compressionRatio > 2.5 && probe.stats.compressed > 0 {
            parts.append("压缩率偏高，说明系统正花力气把内存压小。")
        }
        return parts.joined(separator: "")
    }
}
