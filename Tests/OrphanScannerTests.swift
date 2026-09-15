import Foundation

// 使用真实的 Models.swift（已由 run_tests.sh 一并编译），
// 不再自己造 stub —— CleanupEngine 需要 CleanupItem.name/path 等成员，
// 手写 stub 会随之漂移，之前就因此编译失败过。

@MainActor func run() async {
    var fail = 0
    func expect(_ c: Bool, _ m: String) { print("\(c ? "✅" : "❌") \(m)"); if !c { fail += 1 } }

    print("=== 1. bundle id 形态识别 ===")
    // 应当被识别为 bundle id
    for s in ["com.tencent.yuanbao", "group.com.docker", "io.github.skylot.jadx",
              "com.bot.pc.doubao.browser", "com.microsoft.VSCode"] {
        expect(OrphanScanner.extractBundleID(from: s) == s.lowercased(), "识别 \(s)")
    }
    // 不应被识别为 bundle id —— 这些是普通文件夹名，误判会导致乱删
    for s in ["Google", "Microsoft", "Crashpad", "com", "a.b", "我的文档",
              "com.foo.bar/../etc", "com.foo bar.baz", "...", "node_modules"] {
        expect(OrphanScanner.extractBundleID(from: s) == nil, "拒绝 \(s)")
    }

    print("\n=== 2. 后缀剥离 ===")
    expect(OrphanScanner.extractBundleID(from: "com.foo.bar.plist") == "com.foo.bar", "剥离 .plist")
    expect(OrphanScanner.extractBundleID(from: "com.foo.bar.savedState") == "com.foo.bar", "剥离 .savedState")
    expect(OrphanScanner.extractBundleID(from: "com.foo.bar.binarycookies") == "com.foo.bar", "剥离 .binarycookies")

    print("\n=== 3. 沙盒 team-id 前缀必须剥离 ===")
    // 不剥离会导致「钉钉的容器被当成孤儿」这类误判
    expect(OrphanScanner.extractBundleID(from: "2DC432GLL2.com.openai.sky.CUAService")
           == "com.openai.sky.cuaservice", "剥离 2DC432GLL2 前缀")
    expect(OrphanScanner.extractBundleID(from: "5ZSL2CJU2T.com.dingtalk.mac")
           == "com.dingtalk.mac", "剥离 5ZSL2CJU2T 前缀")
    // 不该误剥：首段不是 10 位团队标识
    expect(OrphanScanner.stripTeamPrefix("com.tencent.yuanbao") == "com.tencent.yuanbao",
           "正常 id 不被误剥")

    print("\n=== 4. Apple 系统组件必须排除 ===")
    for s in ["com.apple.safari", "groups.com.apple.podcasts",
              "group.com.apple.replayd", "com.apple.siri.gmsselfingestor"] {
        expect(OrphanScanner.isAppleSystemID(s), "排除 \(s)")
    }
    expect(!OrphanScanner.isAppleSystemID("com.tencent.yuanbao"), "不误伤第三方 id")

    print("\n=== 5. 已知 id 匹配（双向前缀）===")
    let known: Set<String> = ["com.docker.docker", "com.electron.dockerdesktop", "com.foo.app"]
    expect(OrphanScanner.isKnown("com.electron.dockerdesktop", in: known), "★Docker 内部 helper 被识别")
    expect(OrphanScanner.isKnown("com.docker.docker", in: known), "顶层 id 被识别")
    expect(OrphanScanner.isKnown("com.foo.app.helper", in: known), "★子模块不被当成孤儿")
    expect(!OrphanScanner.isKnown("com.tencent.yuanbao", in: known), "真孤儿不匹配")

    print("\n=== 5b. entitlements 声明的 group container（修误报的关键）===")
    // 这些 group container 的名字不在任何 Info.plist 里，只能从 entitlements 拿到。
    // 早期版本靠「90 天未访问」兜底，会漏；靠 id 猜，会误报。
    let shortcuts = URL(fileURLWithPath: "/System/Applications/Shortcuts.app")
    let scGroups = OrphanScanner.declaredGroupContainers(shortcuts)
    expect(scGroups.contains("group.is.workflow.shortcuts"),
           "★Shortcuts 声明了 group.is.workflow.shortcuts（否则会误报成孤儿）")
    expect(scGroups.contains("group.is.workflow.my.app"),
           "★Shortcuts 声明了 group.is.workflow.my.app")
    let docker = URL(fileURLWithPath: "/Applications/Docker.app")
    if FileManager.default.fileExists(atPath: docker.path) {
        expect(OrphanScanner.declaredGroupContainers(docker).contains("group.com.docker"),
               "★Docker 声明了 group.com.docker（否则会误报成孤儿）")
    }

    print("\n=== 5c. 非 /Applications 位置的应用也要扫到 ===")
    // macFUSE 把 fsmodule 装在 /Library/Filesystems/.../Resources 下，
    // 不扫 /Library 就会把它的 Application Scripts 误判成孤儿。
    let macfuse = URL(fileURLWithPath:
        "/Library/Filesystems/macfuse.fs/Contents/Resources/macfuse.app"
        + "/Contents/Extensions/io.macfuse.app.fsmodule.macfuse-local.appex")
    if FileManager.default.fileExists(atPath: macfuse.path) {
        expect(OrphanScanner.bundleIDs(insideApp: macfuse)
                .contains("io.macfuse.app.fsmodule.macfuse-local"),
               "★macFUSE 组件标识被读到（否则 Application Scripts 会误报）")
    } else {
        print("⏭  本机未装 macFUSE，跳过")
    }

    print("\n=== 6. 端到端：真实扫描 → 真实删除 ===")
    let fake = URL(fileURLWithPath: NSHomeDirectory()
        + "/Library/Caches/com.maccleaner.orphantest.\(UUID().uuidString.prefix(8))")
    try? FileManager.default.createDirectory(at: fake, withIntermediateDirectories: true)
    try? String(repeating: "x", count: 20000)
        .write(to: fake.appendingPathComponent("data.bin"), atomically: true, encoding: .utf8)
    // 时间调旧，绕过「90 天内访问过就跳过」的保守规则
    let old = Date().addingTimeInterval(-200 * 24 * 3600)
    try? FileManager.default.setAttributes([.modificationDate: old, .creationDate: old],
                                            ofItemAtPath: fake.path)
    defer { try? FileManager.default.removeItem(at: fake) }

    let s = OrphanScanner()
    s.startScan()
    var w = 0.0
    while s.isScanning && w < 300 { try? await Task.sleep(nanoseconds: 300_000_000); w += 0.3 }

    expect(s.knownIDCount > 100, "★读到足够多的已安装应用标识（实际 \(s.knownIDCount)）")
    let hit = s.groups.flatMap(\.items).first { $0.url.path == fake.path }
    expect(hit != nil, "★扫描器列出了这个残留")

    let item = CleanupItem(url: fake, size: 20000, category: .orphanResidue, risk: .caution,
                           explanation: "测试", defaultSelected: false, isSelected: true)
    let out = await CleanupEngine().clean(items: [item], permanent: false, grant: .orphanResidue) { _,_,_ in }
    expect(out.deleted == 1, "★真实删除成功（删除 \(out.deleted)，失败 \(out.failures.count)）")
    for (_, e) in out.failures { print("    失败: \(e)") }
    expect(!FileManager.default.fileExists(atPath: fake.path), "★原路径已消失")

    // 清掉废纸篓里的测试残留
    let trash = NSHomeDirectory() + "/.Trash"
    if let items = try? FileManager.default.contentsOfDirectory(atPath: trash) {
        for i in items where i.contains("orphantest") {
            try? FileManager.default.removeItem(atPath: "\(trash)/\(i)")
        }
    }

    print(fail == 0 ? "\n✅ 全部通过" : "\n❌ \(fail) 项失败")
    exit(fail == 0 ? 0 : 1)
}
await run()
