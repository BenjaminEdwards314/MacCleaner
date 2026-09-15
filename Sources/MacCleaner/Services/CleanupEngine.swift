import Foundation
import AppKit

/// 清理执行器。
/// 所有删除都走 NSWorkspace 的「移到废纸篓」，保证可恢复。
/// 唯一例外是 .Trash 自身的内容（那才叫真正清空）。
@MainActor
final class CleanupEngine: ObservableObject {

    struct Outcome {
        var deleted: Int = 0
        var freed: Int64 = 0
        var failures: [(URL, String)] = []
    }

    /// 执行清理
    /// - Parameters:
    ///   - items: 要清理的条目
    ///   - permanent: true 时直接删除（仅用于清空废纸篓），false 时移入废纸篓
    ///   - grant: 额外授权。清理重复文件/应用卸载时传入，普通缓存清理传 nil。
    ///   - progress: 进度回调 (已完成数, 总数, 当前文件名)
    func clean(
        items: [CleanupItem],
        permanent: Bool,
        grant: SafetyGuard.Grant? = nil,
        progress: @escaping (Int, Int, String) -> Void
    ) async -> Outcome {
        var outcome = Outcome()
        let total = items.count

        for (idx, item) in items.enumerated() {
            progress(idx, total, item.name)

            // 二次安全校验：即使 UI 出错，这里也会拦下
            do {
                try SafetyGuard.validate(item.url, grant: grant)
            } catch {
                outcome.failures.append((item.url, error.localizedDescription))
                continue
            }

            guard FileManager.default.fileExists(atPath: item.path) else { continue }

            // 判断是否在废纸篓内部 —— 只有这种情况才允许真删。
            // 用标准化路径前缀比较，而不是 `path.contains("/.Trash/")`：
            // 后者会让 ~/foo/.Trash/bar 这类路径命中，造成绕过废纸篓的永久删除。
            let insideTrash = SafetyGuard.isInsideTrash(item.url)
            let shouldPermanentlyDelete = permanent || insideTrash

            do {
                if shouldPermanentlyDelete {
                    try FileManager.default.removeItem(at: item.url)
                } else {
                    try FileManager.default.trashItem(at: item.url, resultingItemURL: nil)
                }
                outcome.deleted += 1
                outcome.freed += item.size
            } catch {
                outcome.failures.append((item.url, error.localizedDescription))
            }

            // 让出主线程，保持 UI 流畅
            if idx % 8 == 0 { await Task.yield() }
        }

        progress(total, total, "")
        return outcome
    }

    /// 清空废纸篓
    func emptyTrash(progress: @escaping (Int, Int, String) -> Void) async -> Outcome {
        let trash = URL(fileURLWithPath: NSHomeDirectory() + "/.Trash")
        guard let entries = try? FileManager.default.contentsOfDirectory(
            at: trash,
            includingPropertiesForKeys: [.fileSizeKey, .totalFileAllocatedSizeKey, .isDirectoryKey],
            options: []
        ) else {
            return Outcome()
        }

        var items: [CleanupItem] = []
        for e in entries {
            let size = SizeCalculator.size(of: e)
            items.append(CleanupItem(
                url: e, size: size, category: .trash, risk: .safe,
                explanation: "废纸篓中的项目，删除后无法恢复", defaultSelected: true
            ))
        }
        return await clean(items: items, permanent: true, progress: progress)
    }
}
