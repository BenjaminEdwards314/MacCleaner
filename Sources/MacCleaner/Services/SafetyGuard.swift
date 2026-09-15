import Foundation

/// 安全护栏。
/// 核心原则：只允许删除「明确承认过的路径模式」，绝不提供任意路径删除能力。
/// 任何不在白名单内的路径，即使被构造出来也会被拒绝。
///
/// ## 受限放行（Grant）
///
/// 有两类清理天然不可能落在缓存白名单里：
///
/// - **重复文件**：内容相同的副本通常位于下载/文档/桌面，而这些目录
///   正是原先明确保护的。
/// - **应用卸载**：应用本体在 `/Applications`，残留散布在 `~/Library` 各处。
///
/// 直接把这些目录加进白名单会让原设计「宁可少删，不可误删」的保证失效。
/// 因此改为**显式授权**：调用方必须传入一个 `Grant`，声明这次删除
/// 经过了额外验证。`Grant` 的取值只由已完成验证的调用方构造：
///
/// - `.verifiedDuplicate` —— 仅由 `DuplicateFinder` 在 SHA256 内容比对
///   确认同组至少还有一份之后产出。
/// - `.appUninstall` —— 仅由 `AppInventory` 在枚举出应用字节包
///   与其已知残留目录之后产出。
///
/// 即便带了授权，黑名单、受保护文件名、路径深度等检查**依然全部生效** ——
/// 授权只是放宽「白名单」这一项，不是关掉护栏。
enum SafetyGuard {

    /// 额外的删除授权。`nil` 表示只能删除缓存/日志白名单内的路径。
    enum Grant {
        /// 内容哈希验证过的重复文件副本
        case verifiedDuplicate
        /// 应用本体或其已知残留
        case appUninstall
    }

    /// 允许被清理的路径前缀（全部位于用户 Home 内的缓存/日志区域）
    private static let allowedPrefixes: [String] = {
        let home = NSHomeDirectory()
        return [
            "\(home)/Library/Caches",
            "\(home)/Library/Logs",
            "\(home)/.Trash",
            "\(home)/.npm/_cacache",
            "\(home)/.npm/_npx",
            "\(home)/.npm/_logs",
            "\(home)/Library/pnpm",
            "\(home)/.cache",
            "\(home)/Library/Application Support/Codex/Crashpad/pending",
            "\(home)/Library/Application Support/Codex/Crashpad/completed",
            "\(home)/Library/Application Support/Codex/Crashpad/new",
            "/private/var/folders",
        ]
    }()

    /// 绝对禁止触碰的路径（即使误入白名单也要拦下）
    private static let forbiddenPrefixes: [String] = {
        let home = NSHomeDirectory()
        return [
            "/System", "/usr", "/bin", "/sbin", "/private/etc", "/Library",
            "\(home)/Documents", "\(home)/Desktop", "\(home)/Pictures",
            "\(home)/Movies", "\(home)/Music", "\(home)/Library/Keychains",
            "\(home)/Library/Application Support/Codex/Default",
            "\(home)/Library/Containers", "\(home)/Library/Group Containers",
        ]
    }()

    /// 禁止删除的关键文件名（哪怕在缓存目录里也要保护）
    private static let forbiddenNames: Set<String> = [
        "Keychains", "keychain-2.db", "login.keychain-db",
        ".ssh", ".gnupg", "Preferences", "Safari", "Mail",
    ]

    /// 系统目录：任何授权都不放宽这些
    private static let neverAllowed: [String] = [
        "/System", "/usr", "/bin", "/sbin", "/private/etc",
        "/Library", "/Applications/Xcode.app", "/private/var/db",
    ]

    /// 授权删除时允许的「用户数据」根目录（重复文件专用）
    private static let userDataRoots: [String] = {
        let home = NSHomeDirectory()
        return [
            "\(home)/Downloads", "\(home)/Documents", "\(home)/Desktop",
            "\(home)/Pictures", "\(home)/Movies", "\(home)/Music",
        ]
    }()

    /// 应用残留允许出现的 `~/Library` 子目录（卸载专用）
    private static let residueRoots: [String] = {
        let home = NSHomeDirectory()
        return [
            "\(home)/Library/Caches",
            "\(home)/Library/Preferences",
            "\(home)/Library/Logs",
            "\(home)/Library/Application Support",
            "\(home)/Library/Saved Application State",
            "\(home)/Library/HTTPStorages",
            "\(home)/Library/WebKit",
            "\(home)/Library/Cookies",
            "\(home)/Library/LaunchAgents",
            "\(home)/Library/Application Scripts",
        ]
    }()

    enum Denial: LocalizedError {
        case notAllowed(String)
        case forbidden(String)
        case protectedName(String)
        case tooShallow(String)
        case isHomeItself
        case grantRequired(String)

        var errorDescription: String? {
            switch self {
            case .notAllowed(let p): return "路径不在允许清理的白名单内：\(p)"
            case .forbidden(let p): return "该路径属于受保护区域，禁止删除：\(p)"
            case .protectedName(let n): return "该名称受保护，不可删除：\(n)"
            case .tooShallow(let p): return "路径层级过浅，拒绝删除以防误伤：\(p)"
            case .isHomeItself: return "拒绝删除用户主目录"
            case .grantRequired(let p): return "该路径位于用户数据区，需要显式授权才能删除：\(p)"
            }
        }
    }

    /// 判定一个路径是否允许删除。
    ///
    /// 深度校验采用**相对**语义：路径必须严格位于某个允许根目录的**内部**，
    /// 根目录本身不可删。早期版本用的是绝对层数 `depth >= 4`，
    /// 那样 `/Applications/WeChat.app`（仅 2 层）永远无法通过，
    /// 卸载功能会完全失效。
    ///
    /// - Parameter grant: 额外授权。不传时行为与早期版本一致（只允许缓存白名单）。
    static func validate(_ url: URL, grant: Grant? = nil) throws {
        // 统一解析符号链接与 .. ，防止通过路径穿越绕过白名单
        let path = url.standardizedFileURL.resolvingSymlinksInPath().path
        let home = NSHomeDirectory()

        guard path != home, path != "/" else { throw Denial.isHomeItself }

        // 深度校验沿用原有的绝对层数语义，且只作用于**无授权**路径 ——
        // 它拦的是 `~/.Trash`、`~/Library/Caches` 这类容器目录本身。
        // 授权路径不能用绝对层数：`/Applications/WeChat.app` 只有 2 层，
        // 那样卸载功能会完全失效。授权路径改由各自的「必须位于允许根目录内部」保证。
        if grant == nil {
            let depth = path.split(separator: "/").count
            guard depth >= 4 else { throw Denial.tooShallow(path) }
        }

        // 系统目录：任何授权都不放行，优先级最高
        for f in neverAllowed where path == f || path.hasPrefix(f + "/") {
            throw Denial.forbidden(path)
        }

        // 受保护文件名：授权也不放行（密钥、.ssh 之类）
        let name = url.lastPathComponent
        if forbiddenNames.contains(name) { throw Denial.protectedName(name) }

        // ---------- 1. 缓存/日志白名单：始终允许（默认行为） ----------
        // 注意这里保留了「等于白名单条目本身」也允许的语义：
        // 像 `.../Codex/Crashpad/pending` 这类条目，它本身就是要删的目标，
        // 而不是需要往里钻的容器。改成只允许子路径会静默破坏既有清理项。
        for f in allowedPrefixes where path == f || path.hasPrefix(f + "/") { return }

        // ---------- 2. 未命中白名单：必须携带授权 ----------
        switch grant {
        case .none:
            // 原黑名单给出更准确的错误信息
            for f in forbiddenPrefixes where path == f || path.hasPrefix(f + "/") {
                throw Denial.forbidden(path)
            }
            throw Denial.notAllowed(path)

        case .verifiedDuplicate:
            // 仅允许用户数据根目录内部的内容。
            // forbiddenPrefixes 里的 Documents/Desktop 在这里被**有意绕过** ——
            // 这正是「受限放行」的含义；但 neverAllowed 与受保护文件名仍然生效。
            for root in userDataRoots where path.hasPrefix(root + "/") { return }
            if userDataRoots.contains(path) { throw Denial.tooShallow(path) }
            throw Denial.notAllowed(path)

        case .appUninstall:
            if isAppBundle(path, home: home) { return }
            for root in residueRoots where path.hasPrefix(root + "/") { return }
            if residueRoots.contains(path) { throw Denial.tooShallow(path) }
            throw Denial.notAllowed(path)
        }
    }

    /// 路径是否为 `/Applications` 或 `~/Applications` 下某个 `.app` 字节包的内部。
    ///
    /// 要求 `.app` 是应用程序目录的**直接子项**，避免
    /// `/Applications/Foo.app/../Bar` 之类的构造绕过判断。
    private static func isAppBundle(_ path: String, home: String) -> Bool {
        for dir in ["/Applications/", "\(home)/Applications/"] where path.hasPrefix(dir) {
            let rest = path.dropFirst(dir.count)
            guard let first = rest.split(separator: "/").first else { continue }
            if first.hasSuffix(".app") { return true }
        }
        return false
    }

    static func isAllowed(_ url: URL) -> Bool {
        (try? validate(url)) != nil
    }

    /// 该路径是否位于用户废纸篓内部。
    ///
    /// 用途：只有废纸篓内的内容才允许「真正删除」而非移入废纸篓。
    /// 这里必须用标准化后的路径做前缀比较 —— 早期实现用的是
    /// `path.contains("/.Trash/")`，`~/foo/.Trash/bar` 之类的路径也会命中，
    /// 导致本应移入废纸篓的文件被永久删除。
    static func isInsideTrash(_ url: URL) -> Bool {
        let path = url.standardizedFileURL.resolvingSymlinksInPath().path
        let trash = "\(NSHomeDirectory())/.Trash"
        return path == trash || path.hasPrefix(trash + "/")
    }
}
