# MacCleaner — macOS 存储查看与清理工具

原生 SwiftUI 应用。可视化展示磁盘占用，安全清理缓存与垃圾文件。

![平台](https://img.shields.io/badge/macOS-15%2B-blue) ![Swift](https://img.shields.io/badge/Swift-6.1-orange)

## 快速开始

```bash
cd ~/Documents/software/MacCleaner
./build.sh
open build/MacCleaner.app
```

构建产物：`build/MacCleaner.app`（约 1.8 MB，无外部依赖）

需要可分发的安装包时用 `./package.sh` —— 它会编译 arm64 + x86_64
并合并为通用二进制，再打成 `build/MacCleaner-1.0.dmg`。

## 界面

窗口分三块，顶栏用分段控件切换：

### 清理

1. **磁盘总览** — 环形图显示已用比例，旁边列出总容量 / 已用 / 可用 / 可清理
2. **类别环形图** — 按体积把各清理类别画成甜甜圈，**点击扇区或图例可筛选**
3. **明细列表** — 可展开的分组，逐项勾选，带风险标签和「在 Finder 中显示」

### 空间

只读地展示「空间去哪了」，可逐层钻取：

1. **矩形树图** — 面积正比于体积，悬停高亮、单击钻取、双击在 Finder 中显示
2. **列表视图** — 与树图可切换
3. **面包屑** — 随时返回上层

两阶段加载：先毫秒级列出目录骨架，再逐个回填体积。实测
`~/Library/Application Support` 完整统计要 24 秒，但 0.9 秒内就能看到前 20 项的真实体积。

### 内存

实时内存观测面板：

1. **顶部环形图** — 已用比例 + 压力等级（正常 / 偏高 / 紧张）
2. **内存构成** — App 内存、联动内存、已压缩、缓存文件、空闲可用，含堆叠占比条
3. **内存占用最高的进程** — 降序排列，每 10 秒刷新
4. **交换空间** — 使用量（如有）

顶栏两个扫描按钮：

| 按钮 | 扫描内容 | 耗时 |
|---|---|---|
| 快速扫描 | 缓存、日志、崩溃报告、开发缓存、废纸篓、下载残留、临时文件 | 数秒 |
| 深度扫描 | 以上 + 应用支持数据 + 大文件（>500MB） | 较慢 |

## 为什么「内存清理」没有一键释放按钮

这是刻意的设计，不是没做完。

市面上不少内存清理工具会提供一个大按钮，点击后宣称「释放了 N GB」。
在本机实测后，这个做法**不成立**：

- **`purge` 需要 root。** 无免密 sudo 时它直接返回
  `Unable to purge disk buffers: Operation not permitted`。
- **即便拿到 root，`purge` 也不释放应用内存。** 它自己的 man page 写明：
  *"It does not affect anonymous memory that has been allocated through
  malloc, vm_allocate, etc."* —— 它清的是磁盘缓冲区。
- **主动回收其它进程的内存需要 `task_for_pid` 权限**，普通应用拿不到。
- **系统本来就足够主动。** inactive / purgeable 页在需要时由内核回收；
  第三方工具能「释放」的部分，系统早就释放了。

所以 MacCleaner 提供的是**诚实的观测面板**：准确显示内存去哪了、压力如何，
并引导你去关闭真正的大户。界面上唯一的写操作是「回收文件缓存」，
它只是建议系统回收缓存页，**不触碰任何用户数据**，而且失败时会
把系统原话（通常是权限不足）如实显示出来，不粉饰。

内存数据的口径与「活动监视器」对齐：

| 指标 | 来源 |
|---|---|
| App 内存 | anonymous + 已压缩 |
| 联动内存 | `Pages wired down` |
| 已压缩 | `Pages occupied by compressor` |
| 缓存文件 | `File-backed pages` |
| 空闲可用 | free + inactive + speculative + purgeable |

可用内存**不只看 `Pages free`** —— macOS 会主动把空闲内存用作缓存，
free 常年很低是正常现象。只统计 free 会严重低估可用量。

## 安全设计

这是本工具最核心的部分。清理软件最大的风险是**误删用户数据**，因此做了四层防护：

### 1. 白名单路径（`SafetyGuard.swift`）

只有明确列出的路径才允许删除，全部位于缓存/日志区域：

```
~/Library/Caches          ~/Library/Logs           ~/.Trash
~/.npm/_cacache           ~/.npm/_npx              ~/.npm/_logs
~/Library/pnpm            ~/.cache
~/Library/Application Support/Codex/Crashpad/{pending,completed,new}
/private/var/folders
```

### 2. 黑名单优先（即使误入白名单也会拦下）

```
/System  /usr  /bin  /sbin  /private/etc  /Library
~/Documents  ~/Desktop  ~/Pictures  ~/Movies  ~/Music
~/Library/Keychains  ~/Library/Containers  ~/Library/Group Containers
~/Library/Application Support/Codex/Default
```

另有受保护文件名：`Keychains`、`login.keychain-db`、`.ssh`、`.gnupg`、`Preferences`、`Safari`、`Mail`

### 3. 路径穿越防护

删除前统一执行 `standardizedFileURL.resolvingSymlinksInPath()`，所以
`~/Library/Caches/../Documents` 会被解析成 `~/Documents` 并被黑名单拦截。

同时要求路径至少 4 层深度，`/System/Library` 这类太浅的路径直接拒绝。

### 4. 移废纸篓而非直接删除

所有清理都通过 `NSWorkspace` 的 `trashItem` 移入废纸篓，**可随时恢复**。
唯一的例外是废纸篓自身的内容（那才叫真正清空）。

### 已验证

安全护栏经过 14 个用例测试，全部通过：

```
✅ 允许      ~/Library/Caches/Google
✅ 拒绝:受保护 ~/Documents/存档
✅ 拒绝:受保护 ~/Desktop/产品文档
✅ 拒绝:受保护 ~/Library/Keychains/login.keychain-db
✅ 拒绝:受保护 ~/Library/Containers/com.tencent.xinWeChat
✅ 允许      ~/Library/Application Support/Codex/Crashpad/pending
✅ 拒绝:受保护 ~/Library/Application Support/Codex/Default
✅ 拒绝:主目录 ~
✅ 拒绝:白名单外 ~/Library/Caches/../Documents    ← 路径穿越
```

## 风险分级

每个条目都带风险标签，决定默认是否勾选：

| 等级 | 含义 | 默认勾选 | 例子 |
|---|---|---|---|
| 🟢 安全 | 删了会自动重建 | 是 | 应用缓存、npm 缓存 |
| 🟡 谨慎 | 可能影响体验 | 否 | 30 天前的安装包、Xcode Archives |
| 🔴 高危 | 默认禁用勾选 | 否 | 应用支持数据、大文件 |

高危项在界面上**复选框是禁用的**，只能手动去 Finder 处理 —— 避免误操作。

## 项目结构

```
MacCleaner/
├── build.sh                              # 构建脚本 → build/MacCleaner.app
├── package.sh                            # 打包脚本 → build/MacCleaner-1.0.dmg（通用二进制）
├── make_icon.py                          # 生成图标（Pillow 手绘，非必需）
├── demo.html                             # 界面演示网页，独立于应用本体
├── Resources/
│   ├── MacCleaner.icns                   # 构建时被打包进 .app 的图标
│   └── icon-preview.png                  # 仅供预览，不参与构建
├── Sources/MacCleaner/
│   ├── Models/
│   │   ├── Models.swift                  # 数据结构、风险分级、格式化
│   │   └── MemoryStats.swift             # 内存采样模型、压力等级
│   ├── Scanner/
│   │   ├── StorageScanner.swift          # 清理视图扫描引擎（垃圾位置知识库）
│   │   ├── DiskScanner.swift             # 空间视图节点模型（按需加载一层）
│   │   └── DiskNavigator.swift           # 空间视图状态机（两阶段加载）
│   ├── Services/
│   │   ├── SafetyGuard.swift             # 安全护栏（白/黑名单、路径穿越防护）
│   │   ├── CleanupEngine.swift           # 清理执行（移废纸篓）
│   │   ├── SizeCalculator.swift          # 目录体积计算（流式 + 并行）
│   │   └── MemoryProbe.swift             # 内存采集（vm_stat / ps / swap）
│   └── UI/
│       ├── ContentView.swift             # 程序入口 + 主窗口 + 三个 tab
│       ├── DiskOverviewView.swift        # 磁盘环形图
│       ├── CategoryDonutView.swift       # 类别甜甜圈
│       ├── DetailListView.swift          # 明细列表
│       ├── DiskSpaceView.swift           # 空间视图（面包屑 + 列表/树图切换）
│       ├── TreemapView.swift             # 矩形树图
│       ├── TreemapLayout.swift           # 树图布局算法
│       └── MemoryView.swift              # 内存视图
└── build/                                # 构建产物（可随时删除）
```

## 技术说明

### 为什么 build.sh 要指定 SDK

这台机器的默认 SDK 是 `MacOSX26.2.sdk`，但编译器是 Swift 6.1.2，
两者不兼容 —— SwiftUI 的 `.swiftinterface` 会报
`cannot suppress '~Copyable' on generic parameter`。

因此脚本显式指定 `MacOSX15.sdk`：

```bash
SDK="/Library/Developer/CommandLineTools/SDKs/MacOSX15.sdk"
swiftc -sdk "$SDK" -target arm64-apple-macosx15.0 ...
```

### 为什么不用 SwiftPM

`swift package` 在这台机器上因 llbuild 框架版本不匹配而崩溃：

```
Symbol not found: _$s7llbuild15ExternalCommandPAAE19depedencyDataFormat...
```

所以 `build.sh` 直接调用 `swiftc` 编译所有源文件，再用 `codesign -` 临时签名。

### 大数据量处理

`SizeCalculator` 用 `FileManager.enumerator` 流式遍历，不预先收集 URL 数组。
实测可处理 26 万文件 / 22.9 GB 的 Codex Crashpad 目录，耗时约 8 秒，
内存稳定。`errorHandler` 返回 `true` 跳过无权限目录，不会因个别目录中断整次扫描。

## 已知限制

- **崩溃转储清理前需先退出对应应用**。Crashpad handler 持有目录时删除可能出错。
  界面上该项默认不勾选，说明文字里也标注了。
- **部分系统目录需要完全磁盘访问权限**（如 `~/Library/Containers`）。
  未授权时会静默跳过，不会报错。可在「系统设置 → 隐私与安全性 → 完全磁盘访问权限」中授权。
- **Ad-hoc 签名**。首次打开如提示「无法验证开发者」，右键 → 打开 即可。

## 许可

[MIT License](LICENSE)。本地自用工具，无外部依赖。
