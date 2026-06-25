<p align="center">
  <img src="assets/app_icon.png" width="150" alt="Mac Sai 图标" />
</p>

<h1 align="center">Mac Sai</h1>

<p align="center">
  <strong>开源的 Mac 清理、优化与恶意软件扫描工具。</strong><br>
  功能完整、免费的 CleanMyMac 替代品，使用 Swift 6 和 SwiftUI 构建。
</p>

<p align="center">
  <a href="README.md">English</a> | <strong>简体中文</strong>
</p>

<!-- TEMPORARY rename notice: remove once the new name has settled (target: 2026-09). -->
> [!IMPORTANT]
> **Mac Clean 现已更名为 Mac Sai。** 还是同一个应用、同一个团队，因商标原因更名。现有的 GitHub 链接会自动重定向，本提示为临时性质。
>
> 之前通过 Homebrew 以旧名安装的？用以下命令切换：
> ```bash
> brew uninstall --cask mac-clean && brew untap iliyami/macclean
> brew tap iliyami/macsai && brew install --cask mac-sai
> ```

<p align="center">
  <a href="https://github.com/iliyami/MacSai/stargazers"><img src="https://img.shields.io/github/stars/iliyami/MacSai?style=flat-square&color=gold" alt="GitHub stars" /></a>
  <img src="https://img.shields.io/badge/platform-macOS%2014%2B-blue?style=flat-square" alt="macOS 14+" />
  <img src="https://img.shields.io/badge/swift-6.0-orange?style=flat-square" alt="Swift 6" />
  <img src="https://img.shields.io/badge/tests-486%20passing-brightgreen?style=flat-square" alt="Tests" />
  <img src="https://img.shields.io/badge/license-BSD--3--Clause-green?style=flat-square" alt="License" />
  <img src="https://img.shields.io/badge/security-audited-purple?style=flat-square" alt="Security" />
  <img src="https://img.shields.io/badge/Apple-notarized-black?style=flat-square&logo=apple" alt="Notarized" />
  <img src="https://img.shields.io/badge/PRs-welcome-ff69b4?style=flat-square" alt="PRs Welcome" />
</p>

<p align="center">
  <img src="assets/demo.png" width="700" alt="Mac Sai 截图" />
</p>

<p align="center">
  <strong>一条命令即可安装：</strong>
</p>

```bash
brew tap iliyami/macsai && brew install --cask mac-sai
```

<p align="center">
  或从 Releases 下载<a href="https://github.com/iliyami/MacSai/releases/latest">最新的 DMG</a>。
</p>

---

## Mac Sai 是什么？

Mac Sai 是一款**免费、开源**的 macOS 应用，可以清理垃圾文件、清除恶意软件、优化性能、彻底卸载应用，并将磁盘占用可视化，全部集成在一个精美统一的界面中。它复刻了 CleanMyMac 的每一项主要功能，同时完全透明、由社区驱动。

**没有订阅。没有遥测。没有广告。只有一台干净的 Mac。**

**支持英文和简体中文。** 可随时在 **设置 → 界面语言** 中切换；默认跟随系统语言。

## Mac Sai 横向对比

|  | Mac Sai | CleanMyMac | Pearcleaner | PureMac | OnyX | Mole |
|---|:---:|:---:|:---:|:---:|:---:|:---:|
| **价格** | 免费 | $39.95/年 | 免费 | 免费 | 免费 | 免费（命令行） |
| **开源** | ✅ BSD-3 | ❌ | ✅ Fair-code | ✅ MIT | ❌ | ✅ MIT |
| **遥测** | ❌ 无 | ⚠️ 有 | ❌ 无 | ❌ 无 | ❌ 无 | ❌ 无 |
| **原生图形应用** | ✅ | ✅ | ✅ | ✅ | ✅ | ❌ 命令行（图形界面另售） |
| **智能扫描（一键）** | ✅ | ✅ | ❌ | ➖ 部分 | ❌ | ➖ 交互式命令行 |
| **系统垃圾（16 个类别）** | ✅ | ✅ | ➖ | ✅ | ➖ 有限 | ✅ |
| **Universal Binary 瘦身** | ✅ | ✅ | ❌ | ❌ | ❌ | ❌ |
| **恶意软件扫描** | ✅ | ✅ | ❌ | ❌ | ❌ | ❌ |
| **浏览器隐私清理** | ✅ | ✅ | ❌ | ❌ | ➖ | ❌ |
| **带残留检测的卸载器** | ✅ 10 级 | ✅ | ✅ 专注 | ❌ | ❌ | ✅ |
| **磁盘树状图可视化** | ✅ | ❌ | ❌ | ❌ | ❌ | ➖ 分析器 |
| **重复文件查找** | ✅ | ✅ | ❌ | ❌ | ❌ | ❌ |
| **菜单栏系统监视器** | ✅ | ✅ 菜单 | ❌ | ❌ | ❌ | ❌ |
| **维护脚本** | ✅ | ✅ | ❌ | ❌ | ✅ 强大 | ➖ |
| **应用内活动日志查看器** | ✅ | ❌ | ❌ | ❌ | ❌ | 不适用（命令行） |
| **经 Apple 公证** | ✅ | ✅ | ✅ | ✅ | ✅ | 不适用 |
| **macOS 版本** | 14+ | 13+ | 13+ | 13+ | 视情况 | 视情况 |

> CleanMyMac 是一款很棒的产品，愿意为打磨精良、有官方支持的体验付费的用户理应让他们获得收入。Mac Sai 则面向所有更希望拥有透明源代码、零订阅的人。

## 功能

### 清理
| 模块 | 说明 |
|--------|------------|
| **智能扫描** | 一键扫描，结合清理、防护和性能分析，横跨 13 个模块实时显示进度 |
| **系统垃圾** | 16 个扫描类别，包括用户/系统缓存、日志、语言文件、损坏的偏好设置、损坏的登录项、文稿版本、iOS 备份、Xcode 垃圾、**Universal Binary 瘦身**（检测同时包含 arm64 和 x86_64 切片的胖 Mach-O 二进制文件，并通过 `lipo` 重写为你的原生架构）、已删除用户等 |
| **邮件附件** | 查找来自 Apple Mail、Outlook 和 Spark 的缓存附件 |
| **废纸篓** | 清空所有位置（包括外置磁盘）的废纸篓 |

### 防护
| 模块 | 说明 |
|--------|------------|
| **恶意软件清除** | 基于特征码的扫描，提供 3 种深度（快速 / 平衡 / 深度），检查启动代理/守护进程、浏览器扩展以及已知恶意软件模式 |
| **隐私** | 清理 Safari、Chrome 和 Firefox 数据，包括历史记录、Cookie、缓存。可按时间过滤清理系统使用痕迹 |

### 性能
| 模块 | 说明 |
|--------|------------|
| **优化** | 管理登录项和启动代理，可逐项启用/停用 |
| **维护** | 10 项系统任务，包括释放内存、运行维护脚本、修复权限、重建启动服务、重建 Spotlight 索引、刷新 DNS、精简 Time Machine 快照。任务按风险等级标记（安全 / 有干扰），“全部运行”需要显式确认；耗时较长的任务可中途取消 |

### 应用
| 模块 | 说明 |
|--------|------------|
| **卸载器** | 10 级应用匹配引擎，可在 17 个以上的 Library 子目录中找出每一个关联文件。支持彻底删除、应用重置、未使用应用检测 |
| **应用更新** | 通过 Sparkle appcast 源检查已安装应用的可用更新 |

### 文件
| 模块 | 说明 |
|--------|------------|
| **空间透视** | 以方形化树状图可视化磁盘占用，可逐层下钻浏览 |
| **大文件与旧文件** | 查找大于 50 MB 的文件，按大小和最后访问日期排序 |
| **重复文件** | 渐进式检测，依次为大小分组 → 部分 SHA-256（4KB）→ 完整哈希 → inode 校验 |
| **文件粉碎** | 安全擦除文件，提供标准、永久和安全覆写模式 |

### 菜单栏小组件

<p align="center">
  <img src="assets/menu_bar.png" width="300" alt="Mac Sai 菜单栏小组件" />
</p>

一个毛玻璃风格的菜单栏小组件，让你的 Mac 关键状态一键可达。它是一个独立进程，登录时启动，可从应用侧边栏开关。无需打开主窗口即可随时查看。

- **实时状态环**：CPU 负载、内存压力、磁盘占用和电池，以 2×2 环形网格呈现（`host_processor_info`、`vm_statistics64`、APFS 容量、IOKit 电源），按绿 → 黄 → 红分级着色
- **网络、运行时间与交换空间**：实时上/下行吞吐、系统运行时间、交换空间使用情况
- **建议**：可操作、可关闭的提示（“用户缓存已增长到 2.52 GB，运行系统垃圾清理”），点击即可执行；关闭后 30 天内不再提示
- **防护状态**：上次恶意软件扫描时间和威胁数量，按时效着色
- **已连接设备**：一眼查看外置卷（含剩余空间）和外接显示器
- **健康提醒**：当磁盘空间严重不足或内存压力持续偏高时，后台通知（已限流、可选启用）
- **一键进入应用**：直接跳转到 Mac Sai

## 架构

```
Mac Sai
├── MacClean          - 主 SwiftUI 应用（14 个模块，15 个视图）
├── MacCleanKit       - 共享框架（模型、常量、协议）
├── MacCleanHelper    - XPC 特权助手（用于 root 操作的 LaunchDaemon）
└── MacCleanMenu      - 菜单栏监视器（独立进程）
```

### 技术栈

| 层 | 技术 |
|-------|-----------|
| 语言 | Swift 6，严格并发 |
| UI | SwiftUI + AppKit 混合 |
| 并发 | Actor、TaskGroup、async/await、@Sendable |
| 数据库 | GRDB.swift（SQLite），启用 WAL 模式 |
| 文件扫描 | 基于 APFS 的 URLResourceKey 预取 |
| 增量更新 | FSEvents，支持历史回放 |
| 特权操作 | SMAppService + NSXPCConnection |
| 系统统计 | Mach API（host_processor_info、vm_statistics64、proc_pidinfo） |

### 安全模型

Mac Sai 的设计目标是**绝不造成数据丢失**：

- **受保护路径黑名单**：`/System`、`/usr`、`/bin`、`/sbin` 以及 Apple 系统应用不可触碰
- **macOS firmlink 规范化**：`/var`↔`/private/var`、`/tmp`↔`/private/tmp`、`/etc`↔`/private/etc` 解析为单一规范形式，使符号链接重定向检测不会误判合法系统路径
- **扫描前的可清理性过滤**：当前进程无法移入废纸篓的项目（系统缓存中 root 拥有的子项、`~/Library/Caches/com.apple.*` 下被 macOS 数据保险库保护的目录）在扫描时即被剔除，绝不会作为“可清理”出现在界面中
- **优先移入废纸篓**：所有删除默认进入废纸篓
- **预演模式**：在不触碰任何文件的前提下预览将被删除的内容
- **TOCTOU 防护**：删除前立即重新解析符号链接
- **分块清理**：大批量选择（5 万项以上）会弹出确认框；引擎将工作拆分为每批 5000 项，在批次之间遵循 `Task.isCancelled`，因此取消响应迅速
- **递归字节统计**：目录大小通过遍历计算而非 stat，因此完成界面上的“已释放 X”数字反映真实情况
- **孤立文件安全策略**：孤立文件清理仅限于缓存/日志
- **应用内活动日志查看器**：清理过程中的每个错误都会记录完整路径；清理后界面提供“查看日志”按钮，打开一个仅显示错误、可复制到剪贴板的应用内浮层，便于你逐字粘贴问题报告。日志在 30 天后自动清理
- **内核强制的 XPC 权限闸门**：特权助手使用 `NSXPCListener.setCodeSigningRequirement`（macOS 13+），由内核本身拒绝任何代码签名与主应用标识符和团队不匹配的进程连接

## 安装

### Homebrew（推荐，一条命令，无任何警告）

```bash
brew tap iliyami/macsai && brew install --cask mac-sai
```

Mac Sai 已经过 Apple 公证，可从聚焦或“应用程序”直接启动，没有警告、无需右键、也无需命令行。

### 一行安装脚本

```bash
curl -fsSL https://raw.githubusercontent.com/iliyami/MacSai/main/scripts/install.sh | bash
```

该脚本会下载最新的 DMG 并将应用安装到 `/Applications`。

### 下载 DMG

从 [Releases](https://github.com/iliyami/MacSai/releases/latest) 下载最新的 DMG，将 Mac Sai 拖入“应用程序”文件夹。Mac Sai 已经过 Apple 公证，可正常启动，没有 Gatekeeper 警告，也不需要任何额外命令。

### 从源码构建

```bash
git clone https://github.com/iliyami/MacSai.git
cd MacClean
swift build
swift test                     # 运行 486 个测试
bash scripts/build-dmg.sh      # 构建本地 DMG（未签名）
```

### 授予完全磁盘访问权限

部分模块（邮件附件、隐私、恶意软件）需要完全磁盘访问权限才能扫描受保护区域：

1. 打开 **系统设置 → 隐私与安全性 → 完全磁盘访问权限**
2. 点击 **+**，从“应用程序”中添加 **Mac Sai.app**
3. 重新启动 Mac Sai

### 卸载

如果你是通过 Homebrew 安装的，一条命令即可删除应用及其所有支持文件：

```bash
brew uninstall --zap --cask mac-sai
```

如果是 DMG 或手动安装，运行卸载脚本（它同样能处理 Homebrew 安装）：

```bash
curl -fsSL https://raw.githubusercontent.com/iliyami/MacSai/main/scripts/uninstall.sh | bash
```

两种方式都会删除 Mac Sai 以及它在 `~/Library` 下的偏好设置、缓存、日志和数据库。如果 **系统设置 → 通用 → 登录项** 中仍有残留条目，请在那里手动删除；应用删除后 macOS 会自动清理它。

## 已签名并公证：为什么你可以信任它

Mac Sai 使用 Apple **Developer ID** 进行代码签名，并经 **Apple 公证**。对于一款清理类应用而言，这一点比几乎任何其他你安装的软件都更重要，因为你即将赋予它对文件的深度访问权限。你理应确信，运行在你 Mac 上的东西确实出自我们之手，且未被篡改。

下面是它带来的保障，由你自己的 Mac 强制执行，而不仅仅是我们的口头承诺：

- **Apple 已经扫描过它。** 每个版本都会提交给 Apple，在发布前检查是否含有恶意软件。公证就是 Apple 担保这一确切构建版本检查通过、清白无虞。
- **它无法被篡改。** 签名是对应用中每个文件的加密封印。一旦签名之后有任何一个字节发生变化，无论是下载损坏、网络攻击者，还是试图借我们之名搭车的恶意软件，macOS 都会拒绝打开它。
- **它确实出自我们。** 签名与我们的 Apple 开发者身份绑定，因此任何其他人都无法发布一个能被你的 Mac 当作 Mac Sai 接受的东西。
- **开箱即用。** 没有 Gatekeeper 警告、无需右键打开、也不用终端命令。像任何你信任的应用一样安装并启动它。

再加上整个源代码都开放供你查阅这一事实，这是一条你无需凭空相信的信任链：代码是公开的，我们为每个版本签名，Apple 进行验证，而你的 Mac 在每次打开应用时都会重新核验那道封印。

维护者请参阅 [`docs/RELEASING.md`](docs/RELEASING.md)，了解版本是如何构建、签名和公证的。

## 系统要求

- macOS 14（Sonoma）或更高版本
- 从源码构建需要：Swift 6 工具链（Xcode 16+）

## 项目结构

```
Sources/
├── MacClean/
│   ├── App/                    # 应用入口、状态、内容视图
│   ├── Core/
│   │   ├── Scanner/            # FileTreeScanner、TargetedScanner、ScanCoordinator
│   │   ├── Cleaner/            # CleaningEngine、SafetyGuard
│   │   ├── Cache/              # GRDB 数据库层
│   │   └── FSMonitor/          # FSEvents 增量监视器
│   ├── Modules/                # 13 个扫描模块
│   │   ├── SystemJunk/         # 16 个垃圾类别
│   │   ├── Malware/            # 特征码扫描器 + 实时监视器
│   │   ├── Uninstaller/        # 10 级应用匹配引擎
│   │   ├── SpaceLens/          # 方形化树状图算法
│   │   ├── Duplicates/         # 渐进式哈希流水线
│   │   └── ...
│   ├── Views/                  # SwiftUI 视图（14 个模块视图 + 共享组件）
│   ├── ViewModels/             # @Observable 视图模型
│   ├── Services/               # PermissionManager、XPCClient
│   └── Utilities/              # SuperEllipse 形状、扩展
├── MacCleanKit/                # 共享模型、常量、协议
├── MacCleanHelper/             # XPC 特权助手（root 操作）
└── MacCleanMenu/               # 菜单栏系统监视器

Tests/                          # XCTest 测试套件，486 个测试
├── MacCleanTests/              # 应用 target 测试
├── MacCleanKitTests/           # 框架测试
└── MacCleanTestSupport/        # 固件（withTempHome、withFakeApp 等）
```

## 测试

```bash
swift test
```

基于 XCTest 的测试套件，覆盖：

- **`SafetyGuard`**：24 个对抗性测试（符号链接、路径遍历、NULL 字节、SIP、受保护应用、文件数量上限、幂等性）
- **`CleaningEngine`**：9 个集成测试（预演、废纸篓、永久删除、错误处理、操作日志）
- **`PlistJunkFilter`**：9 个测试，包括 Apple 系统域安全契约
- **`ScanCoordinator`** 状态机：扫描/取消/类别过滤/包含大文件
- **`TargetedScanner`** 集成：针对合成临时目录固件运行
- **全部 16 个系统垃圾类别**：纯目标声明，以及程序化类别（`BrokenPreferences`、`BrokenLoginItems`、`UniversalBinaries`、`DeletedUsers`）的过滤逻辑
- **`SquarifiedTreemap`**：空、单节点、多节点、面积守恒、纵横比性质
- **`AppMatching`**：卸载器模式引擎的全部 10 级
- **`DuplicateDetection`**：大小分组、部分/完整哈希分组、inode 去重
- **`MalwareSignatures`**：名称模式 + 可疑启动代理载荷
- **`MaintenanceTask`**：全部 10 项任务均有说明、图标、可执行路径
- **`FileGroup`**：按大小 / 按类型 / 按时间分组
- **`AppcastParser`**：Sparkle XML 解析
- **`VolumeInfo`**：使用量计算、相等性
- **`AppDatabase`**：GRDB 缓存增删改查、迁移、失效
- **`FSEventMonitor`**：失效路径计算
- **`AppDiscovery`**、**`AppPathFinder`**：冒烟测试
- **端到端**：合成固件 → 扫描 → 结果 → 清理流程

测试基础设施（`Tests/MacCleanTestSupport/`）提供 `withTempHome`、`withFakeApp`、`withFakePlist` 等固件辅助函数，使测试保持确定性，绝不触碰用户真实的主目录。

覆盖率目标：**整体 85%+**，**`SafetyGuard` 和 `CleaningEngine` 达到 100%**（生死攸关的文件）。完整路线图见 [`docs/TESTING.md`](docs/TESTING.md)。

## 安全

Mac Sai 认真对待安全：

- **无遥测、无分析。** 唯一的网络请求是可选的更新检查（一次对 GitHub Releases API 的请求），可在设置中关闭
- **默认不提升权限**：XPC 助手仅在维护任务时激活
- **代码签名校验**：XPC 助手验证调用方身份
- **受保护路径**：27 个以上 Apple 系统应用和所有受 SIP 保护的路径均被列入黑名单
- **开源**：每一行代码都可审计

### 安全审计清单

- [x] 无命令注入向量（所有 Process 参数都是硬编码常量）
- [x] 无任意文件删除（SafetyGuard 校验每一条路径）
- [x] 防 TOCTOU 竞态条件（删除前重新解析符号链接）
- [x] 文件操作上限（每次操作限 10000 个文件）
- [x] XPC 调用方校验（代码签名检查）
- [x] 源码中无任何密钥或凭据
- [x] 优先移入废纸篓策略（默认可恢复）
- [x] 操作审计日志（每个动作都有记录）

## 参与贡献

我们欢迎贡献！提交 PR 前请阅读我们的[贡献指南](CONTRIBUTING.md)。

### 快速开始

1. Fork 本仓库
2. 创建功能分支（`git checkout -b feature/amazing-feature`）
3. 进行修改
4. 运行测试（`swift test`）
5. 提交（`git commit -m 'Add amazing feature'`）
6. 推送（`git push origin feature/amazing-feature`）
7. 发起 Pull Request

## 许可证

本项目采用 **BSD 3-Clause 许可证**，详见 [LICENSE](LICENSE) 文件。

这意味着你可以使用、修改并再分发本代码，但你**必须**：
- 保留原始版权声明
- 包含许可证文本
- 未经许可，**不得**使用 “Mac Sai” 名称或贡献者姓名为衍生产品背书

## 致谢

灵感来自开源 Mac 工具社区：
- [Pearcleaner](https://github.com/alienator88/Pearcleaner)：应用卸载器模式
- [Mole](https://github.com/tw93/Mole)：清理类别
- [Tencent Lemon Cleaner](https://github.com/Tencent/lemon-cleaner)：模块化架构
- 方形化树状图算法，作者 Bruls、Huizing 和 van Wijk（2000）

## Star 历史

<p align="center">
  <a href="https://www.star-history.com/?type=date&repos=iliyami%2FMacSai">
    <picture>
      <source media="(prefers-color-scheme: dark)" srcset="https://api.star-history.com/chart?repos=iliyami/MacSai&type=date&theme=dark&legend=top-left" />
      <source media="(prefers-color-scheme: light)" srcset="https://api.star-history.com/chart?repos=iliyami/MacSai&type=date&legend=top-left" />
      <img alt="Star History Chart" src="https://api.star-history.com/chart?repos=iliyami/MacSai&type=date&legend=top-left" />
    </picture>
  </a>
</p>

<p align="center">
  <em>如果 Mac Sai 帮你省下了一笔订阅费，点个 ⭐ 能帮助更多人发现它。</em>
</p>

---

<p align="center">
  <strong>Mac Sai 是由社区、为社区打造的自由软件。</strong><br>
  如果你觉得它有用，请为仓库点亮 star 并分享给更多人。
</p>
