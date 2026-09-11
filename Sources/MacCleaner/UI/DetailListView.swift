import SwiftUI

/// 明细列表：可展开的分组 + 可勾选条目
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
            LazyVStack(spacing: 0, pinnedViews: []) {
                ForEach(visibleGroups) { group in
                    groupSection(group)
                }
            }
        }
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
    }

    @ViewBuilder
    private func groupSection(_ group: CleanupGroup) -> some View {
        let isOpen = expanded.contains(group.id)

        // 分组头
        HStack(spacing: 10) {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    if isOpen { expanded.remove(group.id) } else { expanded.insert(group.id) }
                }
            } label: {
                Image(systemName: isOpen ? "chevron.down" : "chevron.right")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .frame(width: 12)
            }
            .buttonStyle(.plain)

            Image(systemName: group.category.symbol)
                .foregroundStyle(.secondary)
                .frame(width: 18)

            Text(group.category.title).font(.callout).fontWeight(.medium)

            RiskBadge(risk: group.maxRisk)

            Text("\(group.items.count) 项")
                .font(.caption)
                .foregroundStyle(.secondary)

            Spacer()

            Text(Fmt.size(group.totalSize))
                .font(.callout)
                .monospacedDigit()
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .contentShape(Rectangle())
        .onTapGesture {
            withAnimation(.easeInOut(duration: 0.2)) {
                if isOpen { expanded.remove(group.id) } else { expanded.insert(group.id) }
            }
        }

        if isOpen {
            ForEach(group.items) { item in
                itemRow(item)
            }
            Divider().padding(.leading, 14)
        }
    }

    @ViewBuilder
    private func itemRow(_ item: CleanupItem) -> some View {
        HStack(spacing: 10) {
            Toggle("", isOn: Binding(
                get: { selection.contains(item.id) },
                set: { on in
                    if on { selection.insert(item.id) } else { selection.remove(item.id) }
                }
            ))
            .labelsHidden()
            .toggleStyle(.checkbox)
            .disabled(item.risk == .dangerous)

            VStack(alignment: .leading, spacing: 2) {
                Text(item.name)
                    .font(.callout)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(item.path)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Spacer()

            RiskBadge(risk: item.risk)

            Text(Fmt.size(item.size))
                .font(.callout)
                .monospacedDigit()
                .frame(width: 74, alignment: .trailing)

            Button {
                NSWorkspace.shared.activateFileViewerSelecting([item.url])
            } label: {
                Image(systemName: "folder")
                    .font(.caption)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .help("在 Finder 中显示")
        }
        .padding(.leading, 36)
        .padding(.trailing, 14)
        .padding(.vertical, 6)
        .contentShape(Rectangle())
        .help(item.explanation)
    }
}

struct RiskBadge: View {
    let risk: RiskLevel

    var body: some View {
        Text(risk.label)
            .font(.system(size: 9, weight: .medium))
            .padding(.horizontal, 5)
            .padding(.vertical, 1.5)
            .background(color.opacity(0.16), in: Capsule())
            .foregroundStyle(color)
    }

    private var color: Color {
        switch risk {
        case .safe: return .green
        case .caution: return .orange
        case .dangerous: return .red
        }
    }
}
