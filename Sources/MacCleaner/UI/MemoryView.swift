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
            ComicSectionHeader(
                "内存压力：\(probe.stats.pressure.label)",
                icon: probe.stats.pressure.symbol,
                tint: pressureColor,
                trailing: AnyView(
                    ComicBadge(text: Fmt.percent(probe.stats.usedFraction),
                               tint: pressureColor,
                               icon: "memorychip")
                )
            )

            HStack(alignment: .center, spacing: 20) {
                ring

                // 半宽列里横向放不下「环形图 + 两列数值」，
                // 所以这里改成一列四项，跟着环形图的高度走。
                VStack(alignment: .leading, spacing: 11) {
                    statRow(title: "物理内存", value: Fmt.size(probe.stats.total), color: PPG.grape)
                    statRow(title: "已使用", value: Fmt.size(probe.stats.used), color: PPG.blossom)
                    statRow(title: "可用", value: Fmt.size(probe.stats.available), color: PPG.buttercup)
                    statRow(title: "App 内存", value: Fmt.size(probe.stats.app), color: PPG.bubbles)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .comicCard(tint: pressureColor, padding: 22)
    }

    /// 顶部环形图。抽出来是为了让 header 的排版逻辑更清楚。
    private var ring: some View {
        ZStack {
            // 底环：奶油底 + 粗黑描边，与磁盘总览的环同一套做法
            Circle()
                .stroke(PPG.cream, lineWidth: 18)
                .overlay { Circle().strokeBorder(PPG.ink, lineWidth: 2.4) }

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
                    .font(.ppg(28, .black))
                    .foregroundStyle(PPG.ink)
                    .monospacedDigit()
                Text("已使用")
                    .font(.ppg(10.5, .bold))
                    .foregroundStyle(PPG.ink.opacity(0.5))
            }
        }
        .frame(width: 130, height: 130)
    }

    private var ringColors: [Color] {
        switch probe.stats.pressure {
        case .critical: return [PPG.danger, PPG.blossom]
        case .warning: return [PPG.sunny, PPG.blossom]
        case .normal: return [PPG.bubbles, PPG.buttercup]
        }
    }

    private var pressureColor: Color {
        switch probe.stats.pressure {
        case .normal: return PPG.buttercup
        case .warning: return PPG.sunny
        case .critical: return PPG.danger
        }
    }

    /// 一行统计。宽度交给父容器决定 —— 之前写死 240pt 会让它在窄列里溢出、
    /// 在宽列里又留出空白。
    private func statRow(title: String, value: String, color: Color) -> some View {
        HStack(spacing: 8) {
            Circle()
                .fill(color)
                .overlay { Circle().strokeBorder(PPG.ink, lineWidth: 1.6) }
                .frame(width: 10, height: 10)
            Text(title)
                .font(.ppg(12.5, .bold))
                .foregroundStyle(PPG.ink.opacity(0.72))
                .lineLimit(1)
            Spacer(minLength: 12)
            Text(value)
                .font(.ppg(13, .heavy))
                .foregroundStyle(PPG.ink)
                .monospacedDigit()
                .lineLimit(1)
        }
    }

    // MARK: - 内存构成

    private var breakdownCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            ComicSectionHeader("内存构成", icon: "square.stack.3d.up.fill", tint: PPG.bubbles)

            if probe.stats.total > 0 {
                // 堆叠条必须是**互斥划分**，否则各段之和会超过物理内存、
                // 把条画出卡片外。
                //
                // 注意 `app` 的口径是「匿名页 + 已压缩」（对齐活动监视器的
                // 「内存」列），所以它已经包含了 `compressed`。若照原样再把
                // compressed 当独立一段画上去，就重复计算了一次：本机实测
                // 五项之和 26.93 GB vs 物理 17.18 GB，条会画到 157% 宽。
                //
                // 这里改成真正的划分：App 段扣掉压缩部分，压缩单列，
                // 末段取「总容量 − 其余各段」作为兜底（含空闲与未归类页）。
                // 图例仍显示原始口径 —— 那些是活动监视器意义上的重叠指标，
                // 本来就该重叠，只是不能拿来做堆叠条。
                GeometryReader { geo in
                    let w = geo.size.width
                    let total = Double(probe.stats.total)
                    let appOnly = max(0, probe.stats.app - probe.stats.compressed)
                    let used = Double(appOnly + probe.stats.wired
                                      + probe.stats.compressed + probe.stats.cachedFiles)
                    let rest = max(0, total - used)

                    HStack(spacing: 1) {
                        segment(width: w * Double(appOnly) / total,
                                color: PPG.bubbles, label: "App 内存（不含压缩）")
                        segment(width: w * Double(probe.stats.wired) / total,
                                color: PPG.grape, label: "联动内存")
                        segment(width: w * Double(probe.stats.compressed) / total,
                                color: PPG.blossom, label: "已压缩")
                        segment(width: w * Double(probe.stats.cachedFiles) / total,
                                color: PPG.sunny, label: "缓存文件")
                        segment(width: w * rest / total,
                                color: PPG.buttercup.opacity(0.55),
                                label: "空闲与其他")
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .strokeBorder(PPG.ink, lineWidth: 2.2)
                    }
                }
                .frame(height: 24)
            }

            legendRow("App 内存", value: probe.stats.app, color: PPG.bubbles,
                      note: "应用实际占用（含已压缩）")
            legendRow("联动内存", value: probe.stats.wired, color: PPG.grape,
                      note: "内核占用，不可换出")
            legendRow("已压缩", value: probe.stats.compressed, color: PPG.blossom,
                      note: compressionNote)
            legendRow("缓存文件", value: probe.stats.cachedFiles, color: PPG.sunny,
                      note: "系统可自动回收")
            legendRow("空闲可用", value: probe.stats.available, color: PPG.buttercup,
                      note: "含 inactive 与可清除页")

            if probe.stats.swapTotal > 0 {
                Divider().overlay(PPG.ink.opacity(0.15))
                HStack(spacing: 8) {
                    Image(systemName: "arrow.left.arrow.right")
                        .font(.ppg(12, .black))
                        .foregroundStyle(probe.stats.isSwapping ? PPG.danger : PPG.grape)
                    Text("交换空间")
                        .font(.ppg(12.5, .bold))
                        .foregroundStyle(PPG.ink.opacity(0.72))
                    Spacer(minLength: 8)
                    Text("\(Fmt.size(probe.stats.swapUsed)) / \(Fmt.size(probe.stats.swapTotal))")
                        .font(.ppg(13, .heavy))
                        .monospacedDigit()
                        .foregroundStyle(probe.stats.isSwapping ? PPG.danger : PPG.ink)
                }
            }

            Text("更新于 \(probe.stats.sampledAt.formatted(date: .omitted, time: .standard))")
                .font(.ppgCaption)
                .foregroundStyle(PPG.ink.opacity(0.4))
                .monospacedDigit()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .comicCard(tint: PPG.bubbles, padding: 18)
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
            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .fill(color)
                .overlay {
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .strokeBorder(PPG.ink, lineWidth: 1.6)
                }
                .frame(width: 14, height: 14)
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.ppg(12.5, .heavy))
                    .foregroundStyle(PPG.ink)
                Text(note)
                    .font(.ppgCaption)
                    .foregroundStyle(PPG.ink.opacity(0.45))
            }
            Spacer(minLength: 8)
            Text(Fmt.size(value))
                .font(.ppg(12.5, .heavy))
                .foregroundStyle(PPG.ink)
                .monospacedDigit()
        }
    }

    // MARK: - 进程

    private var processCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            ComicSectionHeader(
                "内存占用最高的进程",
                icon: "list.number",
                tint: PPG.blossom,
                trailing: AnyView(
                    ComicBadge(text: "常驻内存", tint: PPG.cream,
                               icon: "memorychip", outlined: true)
                )
            )

            if probe.topProcesses.isEmpty {
                ComicEmptyState(
                    icon: "hourglass",
                    title: "正在读取进程列表…",
                    message: "进程列表变化较慢，每约 10 秒刷新一次。",
                    tint: PPG.blossom
                )
                .frame(minHeight: 200)
            } else {
                VStack(spacing: 6) {
                    ForEach(Array(probe.topProcesses.enumerated()), id: \.element.id) { idx, p in
                        processRow(idx: idx, name: p.name, rss: p.rss)
                    }
                }
            }

            Text("这只是观察，不会结束任何进程。要释放内存请退出不需要的应用。")
                .font(.ppgCaption)
                .foregroundStyle(PPG.ink.opacity(0.45))
        }
        .comicCard(tint: PPG.grape, padding: 18)
    }

    /// 单个进程行。整行可点（放大命中区），配色按名次循环取三主角色 ——
    /// 不能用 hashValue：Swift 的 hashValue 每进程随机加盐，重启后颜色会错位。
    private func processRow(idx: Int, name: String, rss: Int64) -> some View {
        let tint = PPG.girl(idx)

        return HStack(spacing: 10) {
            ZStack {
                Circle()
                    .fill(tint)
                    .overlay { Circle().strokeBorder(PPG.ink, lineWidth: 1.8) }
                    .frame(width: 26, height: 26)
                Text("\(idx + 1)")
                    .font(.ppg(11.5, .black))
                    .foregroundStyle(PPG.ink)
                    .monospacedDigit()
            }

            // 用「齿轮」而不是 app.dashed：后者是个虚线方框，
            // 紧挨着列表里的勾选框时容易被看成一个未勾选的复选框。
            Image(systemName: "gearshape.fill")
                .font(.ppg(12, .black))
                .foregroundStyle(PPG.ink.opacity(0.45))

            Text(name)
                .font(.ppg(13, .bold))
                .foregroundStyle(PPG.ink)
                .lineLimit(1)
                .truncationMode(.middle)

            Spacer(minLength: 8)

            Text(Fmt.size(rss))
                .font(.ppg(13, .heavy))
                .foregroundStyle(PPG.ink)
                .monospacedDigit()
        }
        .padding(.vertical, 7)
        .padding(.horizontal, 10)
        .background {
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .fill(idx.isMultiple(of: 2) ? PPG.ink.opacity(0.035) : tint.opacity(0.14))
        }
        .contentShape(Rectangle())
    }

    // MARK: - 说明与操作

    private var adviceCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            ComicSectionHeader("关于「内存清理」", icon: "info.circle.fill", tint: PPG.buttercup)

            Text("macOS 会自动管理内存：应用退出后其内存立即释放，缓存文件在需要时由系统回收。"
                 + "因此本工具不提供「一键释放 N GB」的按钮 —— 那个数字通常是假的。")
                .font(.ppgBody)
                .foregroundStyle(PPG.ink.opacity(0.65))
                .fixedSize(horizontal: false, vertical: true)

            if probe.stats.pressure != .normal {
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.ppg(14, .black))
                        .foregroundStyle(PPG.danger)
                    Text(pressureAdvice)
                        .font(.ppg(12.5, .bold))
                        .foregroundStyle(PPG.ink.opacity(0.78))
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(PPG.sunny.opacity(0.28))
                        .overlay {
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .strokeBorder(PPG.ink, lineWidth: 2.2)
                        }
                }
            }

            Divider().overlay(PPG.ink.opacity(0.15))

            HStack(spacing: 14) {
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
                .buttonStyle(ComicButtonStyle(tint: PPG.sunny, size: .regular))
                .help("请求系统释放磁盘缓冲区。需要管理员权限，通常不会成功。")

                Text("仅影响磁盘缓存，不触碰应用内存与任何文件。")
                    .font(.ppgCaption)
                    .foregroundStyle(PPG.ink.opacity(0.45))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .comicCard(tint: PPG.buttercup, padding: 18)
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
