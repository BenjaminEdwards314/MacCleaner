import SwiftUI

/// 磁盘健康视图。
///
/// 原则：**读不到的字段显示「不可读」，不猜、不补默认值**。
/// Apple Silicon 内置盘的多数 SMART 细项本就不可读，这是常态而非故障。
struct DiskHealthView: View {
    @ObservedObject var probe: DiskHealthProbe

    /// 仅用于列表项悬停高亮，不影响任何业务状态
    @State private var hoveredContainer: Int?

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider().overlay(PPG.ink.opacity(0.2))

            if probe.lastUpdated == nil && !probe.isLoading {
                emptyState
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        volumeCard
                        if !probe.containers.isEmpty { containerCard }
                        snapshotCard
                        smartCard
                    }
                    .padding(18)
                }
            }
        }
        .onAppear {
            if probe.lastUpdated == nil { probe.refresh() }
        }
    }

    private var toolbar: some View {
        VStack(alignment: .leading, spacing: 5) {
            ComicSectionHeader(
                "磁盘健康",
                icon: "internaldrive",
                tint: PPG.bubbles,
                trailing: AnyView(refreshButton)
            )

            HStack(spacing: 8) {
                Text("文件系统、APFS 容器、快照与 SMART 状态")
                    .font(.ppgCaption)
                    .foregroundStyle(PPG.ink.opacity(0.6))

                if let t = probe.lastUpdated {
                    ComicBadge(
                        text: "更新于 \(t.formatted(date: .omitted, time: .standard))",
                        tint: PPG.cream,
                        icon: "clock.fill",
                        outlined: true
                    )
                }
            }
            .padding(.leading, 24)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
        .background(PPG.cream.opacity(0.7))
    }

    private var refreshButton: some View {
        Button {
            probe.refresh()
        } label: {
            Label("刷新", systemImage: "arrow.clockwise")
        }
        .buttonStyle(ComicButtonStyle(tint: PPG.bubbles, size: .regular))
        .disabled(probe.isLoading)
    }

    /// 首帧占位：数据还没回来。
    private var emptyState: some View {
        ComicEmptyState(
            icon: "internaldrive",
            title: "正在读取磁盘信息…",
            message: "读取文件系统、APFS 容器、本地快照与 SMART 状态。",
            tint: PPG.bubbles
        )
        .comicCard(tint: PPG.bubbles, padding: 10)
        .padding(18)
    }

    // MARK: - 卷信息

    private var volumeCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            ComicSectionHeader("启动卷", icon: "internaldrive.fill", tint: PPG.buttercup)

            let v = probe.volume

            HStack(alignment: .top, spacing: 24) {
                VStack(alignment: .leading, spacing: 8) {
                    infoRow("卷名", v.name)
                    infoRow("文件系统", v.fileSystem)
                    infoRow("挂载点", v.mountPoint)
                    infoRow("设备节点", v.deviceNode)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                VStack(alignment: .leading, spacing: 8) {
                    infoRow("介质类型", v.isSolidState.map { $0 ? "固态硬盘 (SSD)" : "机械硬盘 (HDD)" } ?? "不可读")
                    infoRow("加密", v.isEncrypted.map { $0 ? "已加密" : "未加密" } ?? "不可读")
                    infoRow("只读挂载", v.isReadOnly.map { $0 ? "是" : "否" } ?? "不可读")
                    infoRow("总容量", Fmt.size(v.totalBytes))
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            if v.totalBytes > 0 {
                VStack(alignment: .leading, spacing: 7) {
                    let used = max(0, v.totalBytes - v.freeBytes)
                    let frac = Double(used) / Double(v.totalBytes)

                    ComicProgressBar(
                        value: min(frac, 1),
                        tint: usageTint(frac),
                        height: 14
                    )

                    HStack {
                        Text("已用 \(Fmt.size(used))（\(Fmt.percent(frac))）")
                            .font(.ppg(12, .heavy))
                            .foregroundStyle(PPG.ink.opacity(0.75))
                        Spacer()
                        Text("可用 \(Fmt.size(v.freeBytes))")
                            .font(.ppg(12, .black))
                            .foregroundStyle(PPG.ink)
                    }
                    .monospacedDigit()
                }
            }
        }
        .comicCard(tint: PPG.buttercup, padding: 16)
    }

    /// 占用越高越红。用主题色而非系统色，与总览环保持一致。
    private func usageTint(_ frac: Double) -> Color {
        if frac > 0.9 { return PPG.danger }
        if frac > 0.75 { return PPG.sunny }
        return PPG.buttercup
    }

    // MARK: - APFS 容器

    private var containerCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            ComicSectionHeader(
                "APFS 容器",
                icon: "square.stack.3d.up.fill",
                tint: PPG.grape,
                trailing: AnyView(
                    ComicBadge(text: "共 \(probe.containers.count) 个", tint: PPG.grape, icon: "square.stack.3d.up.fill")
                )
            )

            VStack(spacing: 8) {
                ForEach(Array(probe.containers.enumerated()), id: \.offset) { idx, c in
                    containerRow(c, idx: idx)
                }
            }
        }
        .comicCard(tint: PPG.grape, padding: 16)
    }

    private func containerRow(_ c: DiskHealthProbe.Container, idx: Int) -> some View {
        let tint = PPG.girl(idx)
        let isHover = hoveredContainer == idx

        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Text(c.reference)
                    .font(.ppg(13, .black))
                    .foregroundStyle(PPG.ink)
                    .monospacedDigit()

                if c.volumeCount > 0 {
                    ComicBadge(text: "\(c.volumeCount) 个卷", tint: tint, icon: "square.split.2x1.fill")
                }
                if c.snapshotCount > 0 {
                    ComicBadge(text: "\(c.snapshotCount) 个快照",
                               tint: PPG.sunny,
                               icon: "clock.arrow.circlepath")
                }

                Spacer()

                Text("总 \(Fmt.size(c.totalBytes))")
                    .font(.ppg(12.5, .heavy))
                    .foregroundStyle(PPG.ink.opacity(0.7))
                    .monospacedDigit()
            }

            if c.totalBytes > 0 {
                let frac = Double(c.usedBytes) / Double(c.totalBytes)

                ComicProgressBar(value: min(frac, 1), tint: usageTint(frac), height: 10)

                HStack {
                    Text("已用 \(Fmt.size(c.usedBytes))（\(Fmt.percent(frac))）")
                        .font(.ppg(11.5, .bold))
                        .foregroundStyle(PPG.ink.opacity(0.65))
                    Spacer()
                    Text("未分配 \(Fmt.size(c.freeBytes))")
                        .font(.ppg(11.5, .heavy))
                        .foregroundStyle(PPG.ink.opacity(0.8))
                }
                .monospacedDigit()
            }
        }
        .padding(12)
        .background {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(tint.opacity(isHover ? 0.26 : 0.13))
                .overlay {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(PPG.ink.opacity(isHover ? 0.95 : 0.35),
                                      lineWidth: isHover ? 2.2 : 1.6)
                }
        }
        // 整块都是命中区，悬停高亮不会只在小字上响应
        .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.15)) {
                hoveredContainer = hovering ? idx : (hoveredContainer == idx ? nil : hoveredContainer)
            }
        }
    }

    // MARK: - 快照

    private var snapshotCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            ComicSectionHeader(
                "本地快照",
                icon: "clock.arrow.circlepath",
                tint: PPG.sunny,
                trailing: probe.localSnapshots.isEmpty
                    ? nil
                    : AnyView(ComicBadge(text: "\(probe.localSnapshots.count) 个",
                                         tint: PPG.sunny,
                                         icon: "camera.fill"))
            )

            if probe.localSnapshots.isEmpty {
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.ppg(16, .black))
                        .foregroundStyle(PPG.buttercup)

                    Text("当前没有 Time Machine 本地快照。\n快照会占用「可清除空间」，但系统会在需要时自动回收。")
                        .font(.ppgBody)
                        .foregroundStyle(PPG.ink.opacity(0.6))
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12)
                .background {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(PPG.buttercup.opacity(0.16))
                        .overlay {
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .strokeBorder(PPG.ink.opacity(0.3), lineWidth: 1.6)
                        }
                }
            } else {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(probe.localSnapshots, id: \.self) { s in
                        HStack(spacing: 8) {
                            Image(systemName: "camera.fill")
                                .font(.ppg(10, .black))
                                .foregroundStyle(PPG.ink.opacity(0.55))
                            Text(s)
                                .font(.ppg(11.5, .bold))
                                .foregroundStyle(PPG.ink)
                                .monospacedDigit()
                                .textSelection(.enabled)
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background {
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(PPG.ink.opacity(0.05))
                        }
                    }
                }

                Text("这些快照占用空间，但在磁盘紧张时会被系统自动清理。")
                    .font(.ppgCaption)
                    .foregroundStyle(PPG.ink.opacity(0.5))
            }
        }
        .comicCard(tint: PPG.sunny, padding: 16)
    }

    // MARK: - SMART

    private var smartCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            ComicSectionHeader("SMART 状态", icon: "heart.text.square", tint: PPG.blossom)

            let status = probe.volume.smartStatus
            let tint = smartColor(status)

            HStack(alignment: .top, spacing: 14) {
                ZStack {
                    Circle()
                        .fill(tint)
                        .overlay { Circle().strokeBorder(PPG.ink, lineWidth: 2.5) }
                        .frame(width: 54, height: 54)
                    Image(systemName: smartIcon(status))
                        .font(.system(size: 24, weight: .black))
                        .foregroundStyle(PPG.ink)
                }

                VStack(alignment: .leading, spacing: 5) {
                    HStack(spacing: 8) {
                        Text(status ?? "不可读")
                            .font(.ppg(17, .black))
                            .foregroundStyle(PPG.ink)

                        ComicBadge(text: smartVerdict(status), tint: tint, icon: smartIcon(status))
                    }

                    Text(smartExplanation(status))
                        .font(.ppgBody)
                        .foregroundStyle(PPG.ink.opacity(0.6))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .comicCard(tint: smartColor(probe.volume.smartStatus), padding: 16)
    }

    private func smartIcon(_ s: String?) -> String {
        guard let s else { return "questionmark.circle" }
        return s.lowercased().contains("verified") ? "checkmark.seal.fill" : "exclamationmark.triangle.fill"
    }

    /// 正常 / 警告 / 故障 分别用绿、黄、红。
    /// 「不可读」不是故障，但也不等于正常，归到警告档。
    private func smartColor(_ s: String?) -> Color {
        guard let s else { return PPG.sunny }
        return s.lowercased().contains("verified") ? PPG.buttercup : PPG.danger
    }

    private func smartVerdict(_ s: String?) -> String {
        guard let s else { return "不可读" }
        return s.lowercased().contains("verified") ? "正常" : "故障"
    }

    private func smartExplanation(_ s: String?) -> String {
        guard let s else {
            return "这台机器的磁盘未提供 SMART 状态。外接硬盘和部分内置盘不报告该信息，属正常情况。"
        }
        if s.lowercased().contains("verified") {
            return "磁盘自检状态正常。Apple Silicon 内置盘只提供总体状态，不提供通电时间、写入量等细项。"
        }
        return "磁盘报告了非正常状态，建议尽快备份重要数据。"
    }

    // MARK: - 辅助

    private func infoRow(_ label: String, _ value: String) -> some View {
        HStack(spacing: 8) {
            Text(label)
                .font(.ppg(11.5, .bold))
                .foregroundStyle(PPG.ink.opacity(0.55))
                .frame(width: 76, alignment: .leading)
            Text(value)
                .font(.ppg(12.5, .heavy))
                .foregroundStyle(PPG.ink)
                .monospacedDigit()
                .textSelection(.enabled)
                .lineLimit(1)
                .truncationMode(.middle)
        }
    }
}
