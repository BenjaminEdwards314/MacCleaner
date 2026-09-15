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
  ("\(home)/Library/Containers/x", .appUninstall, false),
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

print("\n安全倒退: \(regressions.count)   授权失败: \(bad)   isInsideTrash 失败: \(trashBad)")
exit((regressions.isEmpty && bad == 0 && trashBad == 0) ? 0 : 1)
