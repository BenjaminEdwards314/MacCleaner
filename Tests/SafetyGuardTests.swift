import Foundation
let home = NSHomeDirectory()

func origVerdict(_ p: String) -> String {
    do { try SafetyGuardOrig.validate(URL(fileURLWithPath: p)); return "允许" }
    catch { return "拒绝" }
}
func newVerdict(_ p: String, _ g: SafetyGuard.Grant? = nil) -> String {
    do { try SafetyGuard.validate(URL(fileURLWithPath: p), grant: g); return "允许" }
    catch { return "拒绝" }
}

// 覆盖面广的路径集：任何「原版拒绝 → 新版允许」都是安全倒退
let paths: [String] = [
  "\(home)/Library/Caches/Google", "\(home)/Library/Caches", "\(home)/Library/Logs/foo.log",
  "\(home)/Library/Logs", "\(home)/.Trash/x", "\(home)/.Trash",
  "\(home)/.npm/_cacache/x", "\(home)/.npm/_npx/x", "\(home)/.cache/uv/x",
  "\(home)/Library/pnpm/store/x",
  "\(home)/Library/Application Support/Codex/Crashpad/pending",
  "\(home)/Library/Application Support/Codex/Crashpad/completed",
  "\(home)/Library/Application Support/Codex/Crashpad/new",
  "\(home)/Library/Application Support/Codex/Crashpad",
  "\(home)/Library/Application Support/Codex/Default",
  "\(home)/Library/Application Support/Codex/pending",
  "/private/var/folders/xx/yy/T/z", "/private/var/folders",
  "\(home)/Documents", "\(home)/Documents/a/b/c", "\(home)/Desktop/a", "\(home)/Pictures/a",
  "\(home)/Movies/a", "\(home)/Music/a", "\(home)/Downloads/a", "\(home)/Downloads",
  "\(home)/Library/Keychains", "\(home)/Library/Keychains/x",
  "\(home)/Library/Containers/x", "\(home)/Library/Group Containers/x",
  "\(home)/Library/Preferences/x.plist", "\(home)/Library/Application Support/x",
  "\(home)/Library/Saved Application State/x", "\(home)/Library/HTTPStorages/x",
  "\(home)/Library/WebKit/x", "\(home)/Library/Cookies/x", "\(home)/Library/LaunchAgents/x.plist",
  "\(home)/Library/Application Scripts/x", "\(home)/Library/Mail/x", "\(home)/Library/Safari/x",
  "\(home)/Library/Caches/../Documents", "\(home)/Library/Caches/../../etc/passwd",
  "\(home)/Library/Application Support/Codex/Crashpad/pending/../../Default",
  "/System/Library/x", "/usr/lib/x", "/bin/ls", "/sbin/x", "/private/etc/hosts",
  "/Library/Preferences/x", "/Library/Application Support/x", "/Applications/WeChat.app",
  "/Applications", "\(home)/Applications/X.app", "\(home)/.ssh/id_rsa", "\(home)/.gnupg/x",
  "\(home)", "/", "\(home)/Library", "\(home)/Movies", "\(home)/Pictures",
]

var regressions: [String] = []
for p in paths {
    if origVerdict(p) == "拒绝" && newVerdict(p, nil) == "允许" {
        regressions.append(p)
    }
}
print("=== 无授权时的安全倒退检查（原拒绝 → 新允许）===")
if regressions.isEmpty {
    print("✅ 无倒退：\(paths.count) 条路径，默认行为与旧版完全一致")
} else {
    print("❌ 发现 \(regressions.count) 条倒退：")
    for r in regressions { print("   \(r.replacingOccurrences(of: home, with: "~"))") }
}

// 授权下的边界：只允许预期目录，且 neverAllowed 永不放开
let grantCases: [(String, SafetyGuard.Grant, Bool)] = [
  ("\(home)/Downloads/a", .verifiedDuplicate, true),
  ("\(home)/Documents/a", .verifiedDuplicate, true),
  ("\(home)/Desktop/a", .verifiedDuplicate, true),
  ("\(home)/Library/Keychains/x", .verifiedDuplicate, false),
  ("\(home)/Library/Containers/x", .verifiedDuplicate, false),
  ("\(home)/Library/Caches/Google", .verifiedDuplicate, true),
  ("/System/Library/x", .verifiedDuplicate, false),
  ("/usr/lib/x", .verifiedDuplicate, false),
  ("\(home)/.ssh/x", .verifiedDuplicate, false),
  ("/Applications/WeChat.app", .appUninstall, true),
  ("/Applications/WeChat.app/Contents/x", .appUninstall, true),
  ("\(home)/Library/Preferences/a.plist", .appUninstall, true),
  ("\(home)/Library/Keychains/x", .appUninstall, false),
  // 沙盒容器内部的条目放行（AppInventory 按 bundle-id 精确匹配后产出）；
  // 但容器目录本身仍拒绝 —— 见下方的 tooShallow 用例。
  ("\(home)/Library/Containers/x", .appUninstall, true),
  ("\(home)/Library/Group Containers/x", .appUninstall, true),
  ("\(home)/Library/Containers", .appUninstall, false),
  ("\(home)/Library/Group Containers", .appUninstall, false),
  // 重复文件授权不得深入沙盒容器：那个授权只保证「内容有副本」，
  // 不保证「这个容器属于已卸载的应用」。
  ("\(home)/Library/Containers/x", .verifiedDuplicate, false),
  ("/Library/x", .appUninstall, false),
  ("/System/Applications/Chess.app", .appUninstall, false),
  ("\(home)/Documents/x", .appUninstall, false),
  ("\(home)/.ssh/x", .appUninstall, false),
]
print("\n=== 授权边界检查 ===")
var bad = 0
for (p, g, expectAllow) in grantCases {
    let got = newVerdict(p, g) == "允许"
    let ok = got == expectAllow
    if !ok { bad += 1 }
    let gname = g == .verifiedDuplicate ? "dup" : "uninst"
    print("\(ok ? "✅" : "❌") [\(gname)] 期望\(expectAllow ? "允许" : "拒绝") 实际\(got ? "允许" : "拒绝")  \(p.replacingOccurrences(of: home, with: "~"))")
}
print("\n授权用例失败: \(bad)")

// 下载残留：扫描器会列出 ~/Downloads 顶层的安装包，
// 但白名单里没有 Downloads，导致这些条目永远删不掉。
// 用户点「清理所选」只看到失败，却不知道是护栏拦的。
// 这里把放行边界钉死：只允许顶层安装包，子目录与其他类型一律拒绝。
let dlCases: [(String, Bool)] = [
  ("\(home)/Downloads/Hermes-Setup.dmg", true),
  ("\(home)/Downloads/X.pkg",            true),
  ("\(home)/Downloads/a.iso",            true),
  ("\(home)/Downloads/b.mpkg",           true),
  ("\(home)/Downloads/UPPER.DMG",        true),
  // 子目录必须拒绝 —— 不能把整个下载目录变成可删区域
  ("\(home)/Downloads/sub/x.dmg",        false),
  ("\(home)/Downloads/2024/a.pkg",       false),
  ("\(home)/Downloads/a/b/c/d.iso",      false),
  // 非安装包必须拒绝
  ("\(home)/Downloads/photo.jpg",        false),
  ("\(home)/Downloads/report.pdf",       false),
  ("\(home)/Downloads/data.zip",         false),
  ("\(home)/Downloads/script.sh",        false),
  ("\(home)/Downloads/noext",            false),
  // 目录本身必须拒绝
  ("\(home)/Downloads",                  false),
]
print("\n=== 下载残留放行边界 ===")
var dlBad = 0
for (p, expectAllow) in dlCases {
    let got = newVerdict(p, nil) == "允许"
    let ok = got == expectAllow
    if !ok { dlBad += 1 }
    print("\(ok ? "✅" : "❌") 期望\(expectAllow ? "允许" : "拒绝") 实际\(got ? "允许" : "拒绝")  \(p.replacingOccurrences(of: home, with: "~"))")
}
print("\n下载边界失败: \(dlBad)")

// 卸载残余授权：只允许删 ~/Library 各残留目录**内部**的条目，
// 目录本身必须拒绝（否则会出现「把整个 Caches 删掉」这种事），
// 且不得触碰应用本体、系统目录、Keychains。
let orphanCases: [(String, Bool)] = [
  ("\(home)/Library/Caches/com.foo.bar",            true),
  ("\(home)/Library/Preferences/com.foo.bar.plist", true),
  ("\(home)/Library/Application Support/com.foo.bar", true),
  ("\(home)/Library/Containers/com.foo.bar",        true),
  ("\(home)/Library/Group Containers/2DC432GLL2.group.com.foo", true),
  ("\(home)/Library/HTTPStorages/com.foo.bar",      true),
  ("\(home)/Library/Saved Application State/com.foo.bar.savedState", true),
  ("\(home)/Library/LaunchAgents/com.foo.bar.plist", true),
  ("\(home)/Library/WebKit/com.foo.bar",            true),
  // 目录本身一律拒绝 —— 只允许删条目。
  // 注意 Caches / Logs 不在此列：它们本来就在 allowedPrefixes 里
  // （那条规则要允许 `.../Codex/Crashpad/pending` 这类「白名单条目本身即删除目标」
  // 的情况），属于既有行为，与本授权无关。
  ("\(home)/Library/Containers",                    false),
  ("\(home)/Library/Group Containers",              false),
  ("\(home)/Library/Preferences",                   false),
  ("\(home)/Library/Application Support",           false),
  ("\(home)/Library/HTTPStorages",                  false),
  ("\(home)/Library/WebKit",                        false),
  // 不得越界
  ("/Applications/WeChat.app",                      false),
  ("/System/Library/x",                             false),
  ("/usr/lib/x",                                    false),
  ("/Library/x",                                    false),
  ("\(home)/Library/Keychains/x",                   false),
  ("\(home)/Documents/x",                           false),
  ("\(home)/Desktop/x",                             false),
  ("\(home)/.ssh/x",                                false),
  // 穿越尝试：标准化后落到 Containers 内，因此**应当放行**。
  // 护栏按标准化后的真实路径判断，这个用例验证它没有被绕过到别处。
  ("\(home)/Library/Containers/x/../y",             true),
]
print("\n=== 卸载残余授权边界 ===")
var orphanBad = 0
for (p, expectAllow) in orphanCases {
    let got = newVerdict(p, .orphanResidue) == "允许"
    let ok = got == expectAllow
    if !ok { orphanBad += 1 }
    print("\(ok ? "✅" : "❌") 期望\(expectAllow ? "允许" : "拒绝") 实际\(got ? "允许" : "拒绝")  \(p.replacingOccurrences(of: home, with: "~"))")
}
print("\n卸载残余边界失败: \(orphanBad)")

print("\n── isInsideTrash：决定「永久删除」还是「移入废纸篓」──")
var trashBad = 0
func trashCheck(_ expect: Bool, _ path: String, _ note: String = "") {
    let got = SafetyGuard.isInsideTrash(URL(fileURLWithPath: path))
    let ok = got == expect
    if !ok { trashBad += 1 }
    print("\(ok ? "✅" : "❌") 期望\(expect ? "true " : "false") 实际\(got ? "true " : "false")  \(path.replacingOccurrences(of: home, with: "~")) \(note)")
}
trashCheck(true,  "\(home)/.Trash/a.txt")
trashCheck(true,  "\(home)/.Trash/sub/deep/b.txt")
trashCheck(true,  "\(home)/.Trash")
trashCheck(false, "\(home)/Documents/a.txt")
trashCheck(false, "\(home)/foo/.Trash/bar.txt", "★伪装路径")
trashCheck(false, "\(home)/Library/Caches/.Trash/x")
trashCheck(false, "/tmp/.Trash/x")
trashCheck(false, "\(home)/.Trashcan/x", "★前缀相近")
trashCheck(false, "\(home)/.Trash/../Documents/a", "★穿越逃逸")

print("\n安全倒退: \(regressions.count)   授权失败: \(bad)   下载边界失败: \(dlBad)   卸载残余失败: \(orphanBad)   isInsideTrash 失败: \(trashBad)")
exit((regressions.isEmpty && bad == 0 && trashBad == 0 && dlBad == 0 && orphanBad == 0) ? 0 : 1)
