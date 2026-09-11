import Foundation

/// 安全护栏。
/// 核心原则：只允许删除「明确承认过的路径模式」，绝不提供任意路径删除能力。
/// 任何不在白名单内的路径，即使被构造出来也会被拒绝。
enum SafetyGuard {

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

    enum Denial: LocalizedError {
        case notAllowed(String)
        case forbidden(String)
        case protectedName(String)
        case tooShallow(String)
        case isHomeItself

        var errorDescription: String? {
            switch self {
            case .notAllowed(let p): return "路径不在允许清理的白名单内：\(p)"
            case .forbidden(let p): return "该路径属于受保护区域，禁止删除：\(p)"
            case .protectedName(let n): return "该名称受保护，不可删除：\(n)"
            case .tooShallow(let p): return "路径层级过浅，拒绝删除以防误伤：\(p)"
            case .isHomeItself: return "拒绝删除用户主目录"
            }
        }
    }

    /// 判定一个路径是否允许删除
    static func validate(_ url: URL) throws {
        // 统一解析符号链接与 .. ，防止通过路径穿越绕过白名单
        let path = url.standardizedFileURL.resolvingSymlinksInPath().path
        let home = NSHomeDirectory()

        guard path != home, path != "/" else { throw Denial.isHomeItself }

        // 至少要有 4 层深度，避免 /Users/xxx 这种量级的东西被删
        let depth = path.split(separator: "/").count
        guard depth >= 4 else { throw Denial.tooShallow(path) }

        // 先查禁用，再查允许 —— 禁用优先
        for f in forbiddenPrefixes where path == f || path.hasPrefix(f + "/") {
            throw Denial.forbidden(path)
        }

        let name = url.lastPathComponent
        if forbiddenNames.contains(name) { throw Denial.protectedName(name) }

        let ok = allowedPrefixes.contains { path == $0 || path.hasPrefix($0 + "/") }
        guard ok else { throw Denial.notAllowed(path) }
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
