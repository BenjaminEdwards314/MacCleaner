# MacCleaner — macOS 存储查看与清理工具

原生 SwiftUI 应用。可视化展示磁盘占用，安全清理缓存与垃圾文件。

**八个功能**：清理 · 空间 · 重复文件 · 内存 · 应用卸载 · 卸载残余 · 清理历史 · 磁盘健康

![平台](https://img.shields.io/badge/macOS-15%2B-blue) ![Swift](https://img.shields.io/badge/Swift-6.1-orange)

## 快速开始

```bash
cd ~/Documents/software/MacCleaner
./build.sh
open build/MacCleaner.app
```

构建产物：`build/MacCleaner.app`（约 3.1 MB，无外部依赖）

需要可分发的安装包时用 `./package.sh` —— 它会编译 arm64 + x86_64
并合并为通用二进制，再打成 `build/MacCleaner-1.1.dmg`。

跑测试：`./run_tests.sh`（6 个测试文件，覆盖安全护栏、重复文件哈希、
应用残留匹配、卸载残余判定、历史持久化、磁盘信息解析）。

## 界面

窗口是**侧边栏导航**，8 个功能分三组：

| 分组 | 功能 | 说明 |
|---|---|---|
| 存储 | 清理 | 扫描缓存、日志、开发残留 |
| 存储 | 空间 | 矩形树图 + 目录钻取 |
| 存储 | 重复文件 | 内容哈希查找重复副本 |
| 系统 | 内存 | 实时内存观测 |
| 工具 | 应用卸载 | 应用本体 + 残留清理 |
| 工具 | 卸载残余 | 已删除应用留下的无主文件 |
| 工具 | 清理历史 | 累计释放量与趋势 |
| 工具 | 磁盘健康 | 文件系统 / APFS / SMART |

侧边栏底部常驻显示当前磁盘占用，随时有个全局参照。

### 视觉主题

整体是「飞天小女警」卡通风格，集中在主题层三个文件里，其余视图只引用：

- `PPGTheme.swift` — 调色板、字体、卡片、星形形状
- `PPGControls.swift` — 按钮、勾选框、进度条、徽章、菜单等控件
- `PPGCelebration.swift` — 清理完成的全屏庆祝动画

设计上靠三个统一手法建立卡通感，全项目一致：**粗黑描边**（2–3pt）、
**硬阴影**（`radius: 0` 的纯黑投影，像贴纸浮在纸面上）、**大圆角 + 圆润粗体**。
配色取自三位主角：花花粉 / 泡泡蓝 / 毛毛绿，按列表序号循环取用。

交互反馈：

| 位置 | 效果 |
|---|---|
| 任意按钮 | 按下时「坐进」自己的硬阴影，松手弹回并迸出星星 |
| 列表行 | 鼠标悬浮轻微抬起；整行可点，命中区不再只有勾选框 |
| 侧边栏 | 选中项主角色填充 + 黑描边 + 硬阴影，按下回弹 |
| 清理成功 | 全屏星星炸开 + 彩纸飘落 + 释放量大字 |

两处刻意的取舍：

- **按钮最小高度 42pt**（主操作 50pt）。系统 `.bordered` 按钮约 22pt，
  在 1100pt 宽的窗口里偏小、不好点。为此把两处 20pt 左右的
  `.pickerStyle(.segmented)`（重复文件的扫描范围、清理历史的时间范围）
  都换成了独立按钮。
- **危险按钮用 `PPG.dangerDeep` 而非 `PPG.danger`**。亮红配白字只有
  3.03:1，低于 WCAG AA 的 4.5:1；但把 `danger` 整体调暗，又会让徽章上的
  深色字掉到 3.53:1。两个用途对明度的要求相反，所以拆成两个常量。

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

### 重复文件

按**内容**而非文件名判断重复。三阶段筛选，代价从低到高逐层淘汰：

1. **按体积分组** — 只读元数据，体积唯一的文件（占绝大多数）直接排除
2. **头部指纹** — 只读前 4 KB 做 SHA256，淘汰同尺寸但内容不同的
3. **完整哈希** — 只有前两阶段都相同的才做整文件 SHA256（分块流式，不占内存）

实际需要完整哈希的文件通常只占极小比例，所以扫描很快。

**跳过**：小于 1 MB 的文件、符号链接、以及**硬链接**
（硬链接指向同一份数据，把它算成「重复」会诱导用户删掉「一个副本」，实际删哪个都一样）。

扫描范围可自由勾选（默认下载 + 文档 + 桌面）。清理规则是显式的：

- **默认一个都不勾选** —— 「重复」是内容判断，但你可能刻意在不同位置保留同一份文件
- **每组必留一份** —— 批量勾选按钮只勾选「除保留项之外的副本」，不存在把一组删空的路径
- 批量策略可选「保留最早 / 保留最新 / 保留路径最短」

### 内存

实时内存观测面板：

1. **顶部环形图** — 已用比例 + 压力等级（正常 / 偏高 / 紧张）
2. **内存构成** — App 内存、联动内存、已压缩、缓存文件、空闲可用，含堆叠占比条
3. **内存占用最高的进程** — 降序排列，每 10 秒刷新
4. **交换空间** — 使用量（如有）

### 应用卸载

把 `.app` 拖进废纸篓只会删掉程序本体，缓存在 `~/Library` 里的数据会永久留下。
这一页按 bundle identifier 找出残留：

1. **左侧应用列表** — 显示每个应用的本体体积与残留体积
2. **右侧明细** — 应用本体单独一块，残留按 `~/Library` 子目录分组，逐项可勾选
3. 三个动作：「清理勾选的残留」（保留应用）、「仅卸载本体」、「彻底卸载」

只做**目录列举 + 名称匹配**（残留命名约定很固定：等于 bundle id 或以 `<bundle id>.` 开头），
不递归遍历，所以很快。系统自带应用（`com.apple.*`）不列出。

### 卸载残余

上一节处理「应用还在」，这一节处理「应用已经删了，只留下一堆无主文件」。

判定一个文件是否无主，比看上去难。一共用了三个信号，按可靠性排序：

**1. 应用内部的全量标识（递归 Info.plist）**

| 做法 | 本机读到的标识数 |
|---|---|
| 只读 `/Applications/*.app` 的顶层 `Info.plist` | 29 |
| 递归每个 `.app` 内部的**所有** `Info.plist` | 937 |

实测例子：`Docker.app` 的标识是 `com.docker.docker`，但它内部嵌套的 Helper
用的是 `com.electron.dockerdesktop`。只比对顶层标识，就会把
`~/Library/Preferences/com.electron.dockerdesktop.plist` 当成孤儿推荐删除 ——
而它属于一个正在使用的应用。

**2. entitlements 里声明的 group container（权威来源）**

有些容器名**根本不在任何 Info.plist 里**，只能从 entitlements 拿：

| 应用 | 声明的容器 |
|---|---|
| Shortcuts | `group.is.workflow.my.app`、`group.is.workflow.shortcuts` |
| Docker | `group.com.docker` |

靠 id 猜会误报（早期版本就把系统快捷指令的两个容器当成了孤儿），
靠「90 天未访问」兜底则会漏。用 `codesign -d --entitlements` 直接读，
全量耗时 < 1 秒。

**3. 覆盖非标准安装位置**

macFUSE 把 fsmodule 装在
`/Library/Filesystems/macfuse.fs/Contents/Resources/...appex`，
不扫 `/Library` 就会把它的 Application Scripts 误判成孤儿。
`/Library` 只有 ~125 个 `Info.plist`，代价可接受。

最终本机已知标识 **1389 个**（`/Applications` + `~/Applications` +
`/System/Applications` + `/System/Library/CoreServices` + `/Library`）。

另加两条保守规则：

- **沙盒 team-id 前缀要剥离**：`5ZSL2CJU2T.com.dingtalk.mac` 要能匹配上 `com.dingtalk.mac`
- **30 天内被访问过的一律跳过**：最后一道兜底。窗口从 90 天收紧到 30 天，
  因为 entitlements 已经承担了主要判定责任 —— 90 天会漏掉
  `com.tencent.mac.marvis` 那 2.31 GB（卡在 61 天）

Apple 系统组件（任何位置含 `com.apple.`）永不列出。结果按厂商聚类，
每项都标出所属 `~/Library` 子目录、体积和最后修改时间。

删除只走废纸篓，**不提供永久删除**。

### 清理历史

每次清理后记录一条：时间、项数、释放量、类别明细、失败数。

1. **汇总卡片** — 累计释放 / 清理次数 / 清理项目 / 最近一次
2. **每日柱状图** — 近 7 / 30 / 90 天可切换
3. **按类别累计** — 横向条形，看出哪类最占空间
4. **最近记录** — 最近 20 条明细

历史存在 `~/Library/Application Support/MacCleaner/history.json`，
**只记录体积，不记录任何文件路径** —— 路径对趋势没有价值，却会让一个本地历史文件变成隐私存档。
上限 500 条，可在界面上一键清空。

### 磁盘健康

1. **启动卷** — 卷名、文件系统、挂载点、设备节点、介质类型、加密、只读、容量占比
2. **APFS 容器** — 每个容器的容量 / 已用 / 未分配，卷数与快照数
3. **本地快照** — Time Machine 本地快照列表
4. **SMART 状态** — 磁盘自检结果

数据来自 `diskutil` 与 `tmutil`，全部只读。

> **关于缺失字段**：Apple Silicon 内置盘的多数 SMART 细项（通电时间、写入量、坏块）
> **不可读**，`diskutil` 只返回一个总体状态；外接 USB 盘通常连总体状态也读不到。
> 所以这些字段全部可选，读不到时界面显示「不可读」而**不会编造数值**。

### 清理页的扫描按钮

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

无授权路径还要求至少 4 层深度，`~/.Trash`、`~/Library/Caches` 这类容器目录本身会被拒绝。

### 4. 受限放行（`Grant`）

有两个功能天然不可能落在缓存白名单里：**重复文件**的副本在下载/文档/桌面，
**应用卸载**的本体在 `/Applications`。把这些目录直接加进白名单会让上面所有保证失效。

所以改为**显式授权**：调用方必须传入一个 `Grant`，它的取值只由已完成验证的地方构造：

| Grant | 由谁产出 | 额外要求 |
|---|---|---|
| `.verifiedDuplicate` | `DuplicateFinder` | SHA256 确认同组至少还有一份，且路径在 `~/Downloads`、`~/Documents`、`~/Desktop`、`~/Pictures`、`~/Movies`、`~/Music` 内部 |
| `.appUninstall` | `AppInventory` | 路径是 `/Applications` 或 `~/Applications` 下某 `.app` 的直接子项，或位于已登记的 10 个 `~/Library` 残留目录内部 |

**授权只放宽「白名单」这一项**，其余检查全部照旧生效：
系统目录（`/System`、`/usr`、`/Library` …）任何授权都不放行，
受保护文件名（`.ssh`、`Keychains` …）优先级高于授权，
`~/Library/Containers` 与 `Group Containers` 在 **`.orphanResidue` 与 `.appUninstall`** 两个授权下开放**内部条目**的删除（目录本身仍拒绝）。这两个授权都要求 bundle id 精确匹配，且 `.orphanResidue` 还额外要求 90 天内未被访问。`.verifiedDuplicate` 下仍不开放 —— 那个授权只保证「内容有副本」，不保证「容器属于已卸载的应用」。

删除时仍会二次校验，即使界面出错也拦得住。

### 5. 移废纸篓而非直接删除

所有清理都通过 `NSWorkspace` 的 `trashItem` 移入废纸篓，**可随时恢复**。
唯一的例外是废纸篓自身的内容（那才叫真正清空）。

判断「是否在废纸篓内」用标准化后的路径前缀比较，而不是
`path.contains("/.Trash/")` —— 后者会让 `~/foo/.Trash/bar` 这类伪装路径命中，
造成绕过废纸篓的永久删除。

### 测试

测试是**独立可执行文件**，不是 XCTest 套件（项目用 `swiftc` 手工编译，没有 SwiftPM）。
每个测试自带最小依赖桩，单独编译运行：

```bash
./run_tests.sh              # 跑全部
./run_tests.sh SafetyGuard  # 只跑名字匹配的
```

6 个测试文件，覆盖：

| 测试 | 覆盖内容 |
|---|---|
| `SafetyGuardTests` | **安全倒退检查**：60 条路径对比新旧实现，确认无授权时行为完全一致；25 条授权边界；14 条下载边界；23 条卸载残余边界；9 条 `isInsideTrash` 用例 |
| `DuplicateFinderTests` | 真实文件验证：同内容检出、同尺寸不同内容排除、前 4 KB 相同整体不同排除、硬链接排除、小于 1 MB 跳过、选择策略 |
| `AppInventoryTests` | 真实环境验证：枚举应用、排除系统应用、残留命名与 bundle id 匹配、本体/残留的风险等级与类别 |
| `CleanupHistoryTests` | 持久化往返、0 释放量不记录、500 条上限截断、每日补零、按类别汇总 |
| `DiskHealthProbeTests` | 真实 `diskutil` 输出解析：卷信息、APFS 容器、SMART 可读性 |
| `OrphanScannerTests` | 标识形态识别（正例/反例）、后缀剥离、team-id 前缀剥离、Apple 组件排除、双向前缀匹配、**entitlements group container 提取**、非标准安装位置、真实扫描 + 真实删除 |

`SafetyGuardTests` 里最关键的断言是**「安全倒退检查」**：它把当前实现与
`git HEAD` 里的旧实现逐条对比，任何「旧版拒绝、新版允许」的路径都会被列出并判失败。
这次改造过程中它抓到过 3 个真实缺陷：

1. `/Applications/WeChat.app` 只有 2 层路径，被旧的 `depth >= 4` 规则误拒 —— 卸载功能会完全失效
2. `.../Codex/Crashpad/pending` 这类白名单条目本身是要删的目标，改成「只允许子路径」后会被静默拒绝
3. `~/.Trash` 容器目录本身变成了可删 —— 深度校验被改写后的安全倒退

### 已验证的实测结果

```
应用卸载    27 个应用、89 项残留，残留命名与 bundle id 100% 匹配
重复文件    同内容检出、硬链接/同尺寸异内容/前4KB同但整体不同 —— 均正确排除
清理历史    持久化往返、上限截断、补零  —— 全部通过
磁盘健康    APFS 卷/容器/SMART 均解析成功（SMART = Verified）
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
├── package.sh                            # 打包脚本 → build/MacCleaner-1.1.dmg（通用二进制）
├── run_tests.sh                          # 测试运行器（独立可执行测试，非 XCTest）
├── make_icon.py                          # 生成图标（Pillow 手绘，非必需）
├── demo.html                             # 界面演示网页，独立于应用本体
├── Resources/
│   ├── MacCleaner.icns                   # 构建时被打包进 .app 的图标
│   └── icon-preview.png                  # 仅供预览，不参与构建
├── Tests/                                # 6 个独立测试（各自带最小依赖桩）
│   ├── SafetyGuardTests.swift            # 安全倒退检查 + 授权边界 + isInsideTrash
│   ├── DuplicateFinderTests.swift        # 真实文件验证三阶段哈希
│   ├── AppInventoryTests.swift           # 真实环境验证应用枚举与残留匹配
│   ├── CleanupHistoryTests.swift         # 持久化往返、上限截断
│   ├── DiskHealthProbeTests.swift        # diskutil 输出解析
│   └── OrphanScannerTests.swift          # 卸载残余判定 + 真实删除
├── Sources/MacCleaner/
│   ├── Models/
│   │   ├── Models.swift                  # 数据结构、风险分级、格式化
│   │   ├── MemoryStats.swift             # 内存采样模型、压力等级
│   │   └── CleanupHistory.swift          # 清理历史记录与持久化
│   ├── Scanner/
│   │   ├── StorageScanner.swift          # 清理视图扫描引擎（垃圾位置知识库）
│   │   ├── DiskScanner.swift             # 空间视图节点模型（按需加载一层）
│   │   ├── DiskNavigator.swift           # 空间视图状态机（两阶段加载）
│   │   ├── DuplicateFinder.swift         # 重复文件三阶段哈希引擎
│   │   ├── AppInventory.swift            # 应用枚举与残留匹配
│   │   └── OrphanScanner.swift           # 卸载残余扫描（已装应用全部标识比对）
│   ├── Services/
│   │   ├── SafetyGuard.swift             # 安全护栏（白/黑名单、受限放行、路径穿越防护）
│   │   ├── CleanupEngine.swift           # 清理执行（移废纸篓，支持 Grant）
│   │   ├── SizeCalculator.swift          # 目录体积计算（流式 + 并行）
│   │   ├── MemoryProbe.swift             # 内存采集（vm_stat / ps / swap）
│   │   └── DiskHealthProbe.swift         # 磁盘健康采集（diskutil / tmutil）
│   └── UI/
│       ├── PPGTheme.swift                # 主题层：调色板、字体、卡片、星形形状
│       ├── PPGControls.swift             # 主题层：按钮、勾选框、进度条、徽章、菜单
│       ├── PPGCelebration.swift          # 清理完成的全屏庆祝动画
│       ├── ContentView.swift             # 程序入口 + 侧边栏导航
│       ├── DiskOverviewView.swift        # 磁盘环形图
│       ├── CategoryDonutView.swift       # 类别甜甜圈
│       ├── DetailListView.swift          # 明细列表
│       ├── DiskSpaceView.swift           # 空间视图（面包屑 + 列表/树图切换）
│       ├── TreemapView.swift             # 矩形树图
│       ├── TreemapLayout.swift           # 树图布局算法
│       ├── MemoryView.swift              # 内存视图
│       ├── DuplicateView.swift           # 重复文件视图
│       ├── UninstallerView.swift         # 应用卸载视图（左列表 + 右明细）
│       ├── OrphanResidueView.swift       # 卸载残余视图（按厂商聚类）
│       ├── HistoryView.swift             # 清理历史与趋势图
│       └── DiskHealthView.swift          # 磁盘健康视图
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

### 调试与截图入口

macOS 在未授予辅助功能权限时会**静默拦截合成点击事件**，无法用脚本操作界面。
因此留了三个启动参数，用于无人值守地逐页截图核对：

| 参数 | 作用 |
|---|---|
| `--section=<名称>` | 直接打开指定页面（`clean`/`space`/`memory`/`duplicates`/`uninstall`/`orphans`/`history`/`health`） |
| `--autoscan` | 启动后自动触发当前页面的扫描，便于截到「有数据」的状态 |
| `--demo-celebration` | 直接展示清理完成的庆祝动画 |

庆祝动画只在真实清理成功（`freed > 0`）后出现，而合成点击被拦截时无法触发清理，
所以需要最后这个入口才能核对动画效果。三者都不影响正常启动。

## 已知限制

- **崩溃转储清理前需先退出对应应用**。Crashpad handler 持有目录时删除可能出错。
  界面上该项默认不勾选，说明文字里也标注了。
- **部分系统目录需要完全磁盘访问权限**（如 `~/Library/Containers`）。
  未授权时会静默跳过，不会报错。可在「系统设置 → 隐私与安全性 → 完全磁盘访问权限」中授权。
- **Ad-hoc 签名**。首次打开如提示「无法验证开发者」，右键 → 打开 即可。
- **应用卸载不覆盖沙盒数据**。`~/Library/Containers` 与 `Group Containers`
  未开放清理 —— 该目录同时存放系统组件数据，误删风险高于收益。界面已明确标注这一限制。
- **重复文件只做精确匹配**。SHA256 相同才算重复，所以「同一张图的不同压缩质量」
  或「同一文档的不同版本」不会被识别 —— 这是刻意取舍，模糊匹配的误报代价太高。
- **不清理系统级位置**。`/Library`、`/System`、`/usr` 等一律不碰，所以本工具
  只能回收用户空间。这与「不动系统文件」的设计目标一致，但意味着清理量有上限。
- **磁盘健康的 SMART 细项多数不可读**。Apple Silicon 内置盘只提供总体状态；
  外接盘可能连总体状态也没有。界面显示「不可读」而非编造数值。

## 许可

[MIT License](LICENSE)。本地自用工具，无外部依赖。
