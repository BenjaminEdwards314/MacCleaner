import SwiftUI

/// 明细列表：可展开的分组 + 可勾选条目。
///
/// 交互上的两个改动，都是冲着「按钮太小、不好点」去的：
///   - 勾选框从 13pt 的系统 checkbox 换成 26pt 的 `ComicCheckbox`，
///     并且整行都可点（原来只有那个小方块本身能点）
///   - 「在访达中显示」从 11pt 的裸图标换成 34pt 圆形按钮
struct DetailListView: View {
    let groups: [CleanupGroup]
    @Binding var selectedCategory: CleanupCategory?
    @Binding var selection: Set<UUID>
    @State private var expanded: Set<UUID> = []

    private var visibleGroups: [CleanupGroup] {
        guard let sel = selectedCategory else { return groups }
        return groups.filter { $0.category == sel }
    }

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 10, pinnedViews: []) {
                ForEach(visibleGroups) { group in
                    groupSection(group)
                }
            }
            .padding(12)
        }
        .comicCard(tint: PPG.buttercup, padding: 0)
    }

    @ViewBuilder
    private func groupSection(_ group: CleanupGroup) -> some View {
        let isOpen = expanded.contains(group.id)
        // 用类别在枚举里的固定序号上色，不能用 hashValue ——
        // Swift 的 hashValue 每个进程随机加盐，同一次运行内稳定，
        // 但重启后颜色会全部错位。
        let tint = PPG.girl(CleanupCategory.allCases.firstIndex(of: group.category) ?? 0)

        VStack(spacing: 0) {
            // 分组头：整行可点，命中区高度 46pt
            HStack(spacing: 10) {
                Image(systemName: isOpen ? "chevron.down" : "chevron.right")
                    .font(.ppg(11, .black))
                    .foregroundStyle(PPG.ink)
                    .frame(width: 14)

                ZStack {
                    Circle().fill(tint)
                        .overlay { Circle().strokeBorder(PPG.ink, lineWidth: 1.8) }
                        .frame(width: 26, height: 26)
                    Image(systemName: group.category.symbol)
                        .font(.ppg(12, .black))
                        .foregroundStyle(PPG.ink)
                }

                Text(group.category.title)
                    .font(.ppg(14, .heavy))
                    .foregroundStyle(PPG.ink)

                RiskBadge(risk: group.maxRisk)

                Text("\(group.items.count) 项")
                    .font(.ppg(11.5, .bold))
                    .foregroundStyle(PPG.ink.opacity(0.5))

                Spacer()

                Text(Fmt.size(group.totalSize))
                    .font(.ppg(14, .black))
                    .monospacedDigit()
                    .foregroundStyle(PPG.ink)
            }
            .padding(.horizontal, 12)
            .frame(minHeight: 46)
            .background {
                RoundedRectangle(cornerRadius: 13, style: .continuous)
                    .fill(tint.opacity(isOpen ? 0.32 : 0.16))
                    .overlay {
                        RoundedRectangle(cornerRadius: 13, style: .continuous)
                            .strokeBorder(PPG.ink.opacity(isOpen ? 0.9 : 0.3),
                                          lineWidth: isOpen ? 2.2 : 1.6)
                    }
            }
            .contentShape(Rectangle())
            .onTapGesture {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) {
                    if isOpen { expanded.remove(group.id) } else { expanded.insert(group.id) }
                }
            }

            if isOpen {
                VStack(spacing: 4) {
                    ForEach(group.items) { item in
                        itemRow(item, tint: tint)
                    }
                }
                .padding(.top, 6)
                .padding(.leading, 8)
            }
        }
    }

    @ViewBuilder
    private func itemRow(_ item: CleanupItem, tint: Color) -> some View {
        let isSelected = selection.contains(item.id)

        HStack(spacing: 11) {
            ComicCheckbox(isOn: isSelected, tint: tint) {
                guard item.risk != .dangerous else { return }
                withAnimation(.spring(response: 0.2, dampingFraction: 0.6)) {
                    if isSelected { selection.remove(item.id) } else { selection.insert(item.id) }
                }
            }
            .opacity(item.risk == .dangerous ? 0.4 : 1)
            .help(item.risk == .dangerous ? "风险过高，不可勾选" : "")

            VStack(alignment: .leading, spacing: 2) {
                Text(item.name)
                    .font(.ppg(13, .bold))
                    .foregroundStyle(PPG.ink)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(item.path)
                    .font(.ppg(10.5, .medium))
                    .foregroundStyle(PPG.ink.opacity(0.42))
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Spacer(minLength: 6)

            RiskBadge(risk: item.risk)

            Text(Fmt.size(item.size))
                .font(.ppg(13, .heavy))
                .monospacedDigit()
                .foregroundStyle(PPG.ink)
                .frame(width: 78, alignment: .trailing)

            Button {
                NSWorkspace.shared.activateFileViewerSelecting([item.url])
            } label: {
                Image(systemName: "folder.fill")
            }
            .buttonStyle(ComicIconButtonStyle(tint: PPG.sunny, diameter: 32))
            .help("在访达中显示")
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background {
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .fill(isSelected ? tint.opacity(0.22) : PPG.ink.opacity(0.035))
        }
        // 整行可点：命中区从 26pt 的勾选框扩大到整行
        .contentShape(Rectangle())
        .onTapGesture {
            guard item.risk != .dangerous else { return }
            withAnimation(.spring(response: 0.2, dampingFraction: 0.6)) {
                if isSelected { selection.remove(item.id) } else { selection.insert(item.id) }
            }
        }
        .help(item.explanation)
    }
}

/// 风险徽章。换成主题色 + 描边的胶囊，比原来的浅底小字更醒目。
struct RiskBadge: View {
    let risk: RiskLevel

    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: icon)
                .font(.ppg(9, .black))
            Text(risk.label)
                .font(.ppg(10, .black))
        }
        .foregroundStyle(PPG.ink)
        .padding(.horizontal, 7)
        .padding(.vertical, 3)
        .background {
            Capsule()
                .fill(color)
                .overlay { Capsule().strokeBorder(PPG.ink, lineWidth: 1.6) }
        }
    }

    private var icon: String {
        switch risk {
        case .safe: return "checkmark"
        case .caution: return "exclamationmark"
        case .dangerous: return "xmark"
        }
    }

    private var color: Color {
        switch risk {
        case .safe: return PPG.buttercup
        case .caution: return PPG.sunny
        case .dangerous: return PPG.danger
        }
    }
}
