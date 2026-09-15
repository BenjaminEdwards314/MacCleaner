import SwiftUI

/// 磁盘健康视图。
///
/// 原则：**读不到的字段显示「不可读」，不猜、不补默认值**。
/// Apple Silicon 内置盘的多数 SMART 细项本就不可读，这是常态而非故障。
struct DiskHealthView: View {
    @ObservedObject var probe: DiskHealthProbe

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider()

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
        HStack(spacing: 12) {
            Image(systemName: "internaldrive")
                .font(.title2)
                .foregroundStyle(.teal)

            VStack(alignment: .leading, spacing: 2) {
                Text("磁盘健康")
                    .font(.headline)
                Text("文件系统、APFS 容器、快照与 SMART 状态")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if let t = probe.lastUpdated {
                Text("更新于 \(t.formatted(date: .omitted, time: .standard))")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .monospacedDigit()
            }

            Button {
                probe.refresh()
            } label: {
                Label("刷新", systemImage: "arrow.clockwise")
            }
            .disabled(probe.isLoading)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
    }

    private var emptyState: some View {
        VStack(spacing: 14) {
            ProgressView().controlSize(.large)
            Text("正在读取磁盘信息…")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - 卷信息

    private var volumeCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            cardTitle("启动卷", icon: "internaldrive.fill")

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
                VStack(alignment: .leading, spacing: 6) {
                    let used = max(0, v.totalBytes - v.freeBytes)
                    let frac = Double(used) / Double(v.totalBytes)

                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            RoundedRectangle(cornerRadius: 5)
                                .fill(Color.secondary.opacity(0.15))
                            RoundedRectangle(cornerRadius: 5)
                                .fill(frac > 0.9 ? Color.red : (frac > 0.75 ? Color.orange : Color.accentColor))
                                .frame(width: max(3, geo.size.width * CGFloat(min(frac, 1))))
                        }
                    }
                    .frame(height: 12)

                    HStack {
                        Text("已用 \(Fmt.size(used))（\(Fmt.percent(frac))）")
                        Spacer()
                        Text("可用 \(Fmt.size(v.freeBytes))")
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                }
            }
        }
        .padding(16)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - APFS 容器

    private var containerCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                cardTitle("APFS 容器", icon: "square.stack.3d.up.fill")
                Spacer()
                Text("共 \(probe.containers.count) 个")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            VStack(spacing: 0) {
                ForEach(Array(probe.containers.enumerated()), id: \.offset) { idx, c in
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text(c.reference)
                                .font(.callout.weight(.medium))
                                .monospacedDigit()
                            if c.volumeCount > 0 {
                                Text("\(c.volumeCount) 个卷")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                            if c.snapshotCount > 0 {
                                Text("\(c.snapshotCount) 个快照")
                                    .font(.caption2)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 1)
                                    .background(Color.orange.opacity(0.15), in: Capsule())
                                    .foregroundStyle(.orange)
                            }
                            Spacer()
                            Text("总 \(Fmt.size(c.totalBytes))")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .monospacedDigit()
                        }

                        if c.totalBytes > 0 {
                            let frac = Double(c.usedBytes) / Double(c.totalBytes)
                            GeometryReader { geo in
                                ZStack(alignment: .leading) {
                                    RoundedRectangle(cornerRadius: 4)
                                        .fill(Color.secondary.opacity(0.15))
                                    RoundedRectangle(cornerRadius: 4)
                                        .fill(frac > 0.9 ? Color.red : Color.accentColor)
                                        .frame(width: max(3, geo.size.width * CGFloat(min(frac, 1))))
                                }
                            }
                            .frame(height: 8)

                            HStack {
                                Text("已用 \(Fmt.size(c.usedBytes))（\(Fmt.percent(frac))）")
                                Spacer()
                                Text("未分配 \(Fmt.size(c.freeBytes))")
                            }
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                        }
                    }
                    .padding(12)

                    if idx != probe.containers.count - 1 {
                        Divider()
                    }
                }
            }
            .background(Color.secondary.opacity(0.05), in: RoundedRectangle(cornerRadius: 10))
        }
        .padding(16)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - 快照

    private var snapshotCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            cardTitle("本地快照", icon: "clock.arrow.circlepath")

            if probe.localSnapshots.isEmpty {
                Text("当前没有 Time Machine 本地快照。\n快照会占用「可清除空间」，但系统会在需要时自动回收。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(probe.localSnapshots, id: \.self) { s in
                        Text(s)
                            .font(.caption)
                            .monospacedDigit()
                            .textSelection(.enabled)
                    }
                }
                Text("这些快照占用空间，但在磁盘紧张时会被系统自动清理。")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(16)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - SMART

    private var smartCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            cardTitle("SMART 状态", icon: "heart.text.square")

            let status = probe.volume.smartStatus
            HStack(spacing: 10) {
                Image(systemName: smartIcon(status))
                    .font(.title2)
                    .foregroundStyle(smartColor(status))
                VStack(alignment: .leading, spacing: 2) {
                    Text(status ?? "不可读")
                        .font(.callout.weight(.medium))
                    Text(smartExplanation(status))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding(16)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
    }

    private func smartIcon(_ s: String?) -> String {
        guard let s else { return "questionmark.circle" }
        return s.lowercased().contains("verified") ? "checkmark.seal.fill" : "exclamationmark.triangle.fill"
    }

    private func smartColor(_ s: String?) -> Color {
        guard let s else { return .secondary }
        return s.lowercased().contains("verified") ? .green : .orange
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

    private func cardTitle(_ text: String, icon: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .foregroundStyle(.secondary)
            Text(text)
                .font(.callout.weight(.semibold))
        }
    }

    private func infoRow(_ label: String, _ value: String) -> some View {
        HStack(spacing: 8) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 70, alignment: .leading)
            Text(value)
                .font(.caption)
                .textSelection(.enabled)
        }
    }
}
