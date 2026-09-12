# 译读（EPUBTranslator）

一个 iOS 上的「读外语书 + 点一下就译成中文」的阅读器。它不调用系统翻译，而是把选中的句子连同上下文一起发给 DeepSeek，让模型按中文的表达习惯重写一遍，所以读起来更像中文小说，而不是机翻。

## 功能

- **导入 EPUB**：App 内选择文件导入，或把 `.epub` 丢进 Files 里的「译读」文件夹自动导入；也支持从其它 App「用译读打开」。
- **点按即译**：阅读时点一下段落 → 整段翻译，译文以卡片形式从底部弹出，边生成边显示。
- **选中即译**：长按选中句子（哪怕只是半句）→ 出现「翻译选中的 N 字」按钮 → 只翻译选中的部分。
- **对照阅读**：卡片上的「插入正文」会把译文插到原文段落下面，形成双语对照，再点一次可移除。
- **上下文感知**：翻译时会把书名、章节名、上一段/下一段、术语表一起发给模型，代词、语气、专有名词的译法会稳定很多。
- **风格可选**：文学流畅 / 忠于原文 / 口语自然 / 学术严谨 / 极简速读，随时在卡片上切换并立即重译。
- **润色**：对初稿不满意可以点「润色」，让模型以中文编辑的视角再改一遍；也可以在设置里打开「高质量模式」，自动做「初稿 + 润色」两遍。
- **流式输出 + 缓存**：SSE 流式显示；同一段文字同一风格只花钱翻译一次，命中缓存会立刻显示。
- **灵动岛 / 锁屏实时译文**：翻译时把进度和译文推到 Live Activity——灵动岛紧凑态滚动显示最新几个字，长按展开能看到原文、风格与完整译文；点一下跳回正在读的那本书。没有灵动岛的机型在锁屏上显示同一张卡片。
- **译文收件箱**：所有译文自动存档，支持搜索、收藏、导出 Markdown。
- **快捷指令 / Siri**：「译读」提供了「翻译文本」「翻译剪贴板」「继续阅读」三个 App Intent，可以接进快捷指令、Spotlight 或 Siri。
- **阅读体验**：章节目录、字号/行距/左右留白、四种主题（米黄/白纸/深灰/纯黑）、宋体/黑体/楷体、首行缩进、阅读进度记忆。

## 环境要求

- 构建：macOS + **Xcode 16 或更新版本**（工程使用 Xcode 16 的文件夹同步格式，`objectVersion = 77`）。
- 运行：**iOS 17.0 或更新版本**的 iPhone / iPad / 模拟器。
- 需要一个 **DeepSeek API Key**（在 <https://platform.deepseek.com> 生成）。Key 只保存在设备的钥匙串里。

## 跑起来

1. 用 Xcode 打开 `EPUBTranslator.xcodeproj`。
2. 选中 `EPUBTranslator` target → Signing & Capabilities → 选上你自己的 Team；顺手把 `PRODUCT_BUNDLE_IDENTIFIER`（默认 `com.epubtranslator.app`）改成你自己的。
3. 选一个 iOS 17+ 的真机或模拟器，⌘R 运行。
4. 打开 App → 设置 → 粘贴 API Key → 「测试连接」，看到「连接正常」就可以去书架导书了。

> 模拟器可以直接跑；真机首次运行需要在 iPhone 上信任开发者证书。

## Windows 上怎么把它装进 iPhone

先说清楚限制：**iOS 模拟器和 `xcodebuild` 都只存在于 macOS**，Windows 上没有任何办法编译 Swift/SwiftUI 工程，也没有 iOS 模拟器。所谓"Windows 版 iOS 模拟器"都跑不了原生 App。所以要在手机上检验，只有下面几条路。

### 路线 A：借/租一台 Mac（出问题时最好排查）

MacinCloud、Scaleway/OVH 的 Apple Silicon 实例、机房 Mac mini、朋友的 Mac 都行。拿到 Mac 后：

1. 把 `D:\epub` 整个目录拷过去，双击 `EPUBTranslator.xcodeproj`。
2. Signing & Capabilities 里选一个 Team（免费 Apple ID 也行）。
3. iPhone 用数据线连上 → 在 Xcode 顶部选你的 iPhone → ⌘R。首次会提示去 iPhone 的「设置 → 隐私与安全性 → 开发者模式」打开，然后在「设置 → 通用 → VPN 与设备管理」里信任证书。
4. 也可以用命令行一键打包：`bash Tools/build-unsigned-ipa.sh`。

免费 Apple ID 签的 App 有 7 天有效期，到期重新 Run 一次即可。

### 路线 B：完全不用 Mac（GitHub Actions 编译 + Windows 侧安装）

我把这条流水线写好了：`.github/workflows/ios-unsigned-ipa.yml`，它会用 GitHub 的 macOS runner 编译出**未签名 IPA**给你下载。

1. 把项目推上 GitHub（当前目录还不是 git 仓库）：
   ```
   git init
   git add .
   git commit -m "译读：DeepSeek 翻译 EPUB 阅读器"
   git branch -M main
   git remote add origin https://github.com/<你的用户名>/<仓库名>.git
   git push -u origin main
   ```
2. 打开仓库的 **Actions** 标签页 → 选 `Build unsigned IPA (Windows-friendly)` → **Run workflow**。
3. 跑完后（约 3–8 分钟）在这一次运行的 Artifacts 里下载 `EPUBTranslator-unsigned-ipa`，解压得到 `EPUBTranslator-unsigned.ipa`。**注意：如果这一步失败，说明代码有编译错误**（这个工程还没在任何机器上编译过），把日志里 `error:` 开头的几行发给我，我改完你再推一次。
4. Windows 侧安装未签名 IPA（二选一）：
   - 先装 **Apple Devices**（微软商店）或 iTunes，用数据线连上 iPhone 并「信任此电脑」。
   - 用 **Sideloadly** 或 **AltStore / SideStore** 打开这个 IPA，填你的 Apple ID，它会用你的账号现场签名并装到手机上。
5. iPhone 上首次安装后：设置 → 隐私与安全性 → **开发者模式** 打开（会重启一次）；如果提示"不受信任的开发者"，到 设置 → 通用 → VPN 与设备管理 里信任你的 Apple ID。
6. 免费 Apple ID 的限制：**7 天有效期**、同时最多 3 个自签 App，到期用同样的步骤重签一次；不想每周重签就得花 $99/年买开发者账号（那还能走 TestFlight，一年有效，见路线 C）。

> 注意：因为多了灵动岛扩展，这个 App 里包含 **两个 bundle**（App + `.appex`）。Sideloadly / AltStore 会自动把嵌套的扩展一起签名，但免费账号的 App ID 配额会占用两个（一共 10 个 / 7 天）。

GitHub Actions 的 macOS runner 对公开仓库免费；私有仓库会按 10 倍系数消耗额度（每月 2000 分钟 ≈ 200 分钟 macOS）。

### 路线 C：有付费开发者账号 → 走 TestFlight

买 Apple Developer Program（$99/年）后，可以在 CI 里用 App Store Connect API Key + fastlane 完成签名并直接上传 TestFlight，手机装 TestFlight App 收内测包，完全不需要 Mac。这条路配置比 A/B 麻烦一些，需要的话我再补一个 workflow。

## 怎么用

| 操作 | 结果 |
| --- | --- |
| 书架右上角 `+` | 从 Files 选 EPUB 导入 |
| 把 EPUB 放进 Files 里的「我的 iPhone / 译读」 | App 回到前台或下拉刷新时自动导入 |
| 阅读页点一下段落 | 整段翻译（设置里可关闭） |
| 长按选中一段文字 | 出现「翻译选中的 N 字」按钮，只译选中的部分 |
| 译文卡片「插入正文」 | 译文插到该段落下面，形成对照；再点一次移除 |
| 译文卡片顶部风格 | 切换风格并立即重译 |
| 译文卡片「润色」 | 让模型以中文编辑视角改写初稿 |
| 长按灵动岛 | 展开看原文 + 完整译文；点按跳回这本书 |

## 灵动岛 / 锁屏实时译文

实现方式是 ActivityKit 的 Live Activity，代码分布：

- `Shared/TranslationActivityAttributes.swift`：App 和扩展**共用**的数据结构（这个文件同时编进两个 target，系统靠同名类型把活动交给扩展渲染）。
- `EPUBTranslatorWidgets/TranslationLiveActivity.swift`：四种形态——灵动岛紧凑态（左侧书本图标 + 右侧最新几个字）、最简态、展开态（原文一行 + 译文四行 + 状态）、锁屏卡片。
- `EPUBTranslator/Support/LiveActivityController.swift`：App 侧的驱动，做了约 0.9 秒的节流（系统对 Live Activity 刷新有频率限制），翻译完成后强制推一次最终结果，卡片再多留 15 秒。

几个细节：

- 翻译中紧凑态显示的是**结尾几个字**并带 `…`，所以能看出"在动"；完成后显示译文开头。
- 点按卡片会走 `epubtranslator://book/<uuid>` 回到那本书（Info.plist 里注册了 URL scheme）。
- 关掉设置里的「在灵动岛 / 锁屏显示实时译文」就不会再创建 Live Activity；App 每次启动也会清掉上次遗留的活动。
- 需要系统「设置 → 灵动岛 / 实时活动」允许；灵动岛只在 iPhone 14 Pro 及以后的 Pro 机型上出现，其它机型看锁屏卡片。
- 用的是本地更新（`pushType: nil`），不需要 APNs，也不需要服务器推送。

## 工程结构

```
EPUBTranslator.xcodeproj/           Xcode 工程（含共享 scheme）
Configuration/Info.plist            文档类型、Files 共享、Live Activity、URL scheme、ATS
Configuration/WidgetInfo.plist      灵动岛 / 锁屏扩展的 Info.plist
Shared/                             App 与扩展共用的数据结构（Live Activity Attributes）
EPUBTranslatorWidgets/              灵动岛 / 锁屏 Live Activity 扩展
EPUBTranslator/
  App/                              入口、依赖容器、Tab 壳
  Library/                          书架、EPUB 解析、ZIP/Deflate 解压、HTML 排版
  Reader/                           阅读器、WKWebView 桥、译文卡片、目录/阅读设置
  Translate/                        提示词、风格、会话、缓存、历史、翻译编排（含灵动岛驱动）
  DeepSeek/                         Chat Completions 客户端（含 SSE 流式解析）
  History/                          译文列表
  Settings/                         设置页
  Intents/                          App Intents + App Shortcuts
  Support/                          设置存储、钥匙串、阅读外观
  Assets.xcassets/                  资源目录
Tools/                              开发用脚本（不参与 App 构建）
```

### 几个设计取舍

- **零第三方依赖**：EPUB 就是一个 ZIP，里面是 DEFLATE 压缩。为了不引第三方库，`EPUBTranslator/Library/Inflate.swift` 用纯 Swift 实现了一个 RFC 1951 解压器，`ZipArchive.swift` 负责中央目录解析和按需解压。图片会转成 data URL 内联进 HTML，所以离线也能正常显示插图。
- **正文用 WKWebView 渲染**：EPUB 是 XHTML，用 Web 渲染最省事，也方便做「选中文字 → 回传原生」和「把译文插进原文下面」。JS 与 Swift 之间只用一个 `reader` 消息通道，方向明确、好维护。
- **API Key 进钥匙串**，翻译缓存、译文历史、书架索引都在 `Application Support`，Files 里看到的 Documents 只是导入用的收件箱。
- **提示词是产品核心**：`PromptBuilder.swift` 里写了明确的反翻译腔规则（不要逐词对应、不要滥用的/被/进行、对白要有口气、不要补戏……），并把上下文包在 `<<< >>>` 之外，告诉模型「只翻译这一部分」。风格、术语表、额外要求都会拼进提示词。
- **温度默认 1.3**：DeepSeek 官方文档给翻译任务的推荐值，实测比 0.7 更少翻译腔。

## 这次的验证情况（重要）

开发这台机器是 Windows，没有 Xcode 和 iOS 模拟器，所以**这个工程没有在这里编译和跑过模拟器**。为了让交付物尽量可靠，做了这些检查：

1. **解压算法做了等价移植验证**：`Tools/inflate-port.mjs`、`Tools/zip-port.mjs` 是 `Inflate.swift` / `ZipArchive.swift` 的等价 JS 实现，`Tools/validate.mjs` 用 300+ 组用例验证过：
   - 压缩级别 0–9、`Z_FILTERED` / `Z_HUFFMAN_ONLY` / `Z_RLE` / `Z_FIXED` 各种块类型；
   - 空数据、2 字节、64KB 文本、200KB 随机数据、128KB 重复数据；
   - 手工构造的 ZIP（stored + deflate 混合）与 PowerShell 生成的真实 EPUB（逐条目与磁盘原文比对一致）。
   - 运行方式：`node Tools/validate.mjs`
2. **源码静态自检**：`node Tools/check-swift.mjs` 会检查 35 个 Swift 文件——括号配平、重复类型声明、`变量.成员` 是否真的存在于对应类型上、以及 `Foo(...)` 构造调用能否找到对应类型（当前只剩 4 条已知误报：嵌套 `CodingKeys` 和可选绑定）。
3. **工程文件自检**：`node Tools/check-project.mjs` 核对 17 个对象的 ID 长度、引用闭合、scheme 指向的 target；`Configuration/Info.plist` 与 `.xcscheme` 也用 XML 解析器验证过。

第一次在 Xcode 里打开时，仍然建议留意编译告警；如果某个 SwiftUI API 在你的 Xcode 版本上有差异，按提示改一下即可。

## 已知限制 / 后续可以做的

- **没有 App 图标**：`Assets.xcassets` 里只有强调色。想上架或想要好看的图标，加一个 `AppIcon.appiconset` 并在 target 里设置 `ASSETCATALOG_COMPILER_APPICON_NAME` 即可。
- **没有 Share Extension**：现在只能从 Files 导入或「用译读打开」。如果希望在任何 App 里选中文字后直接调用，需要再加一个 Share Extension target（复用 `DeepSeekClient` 和 `PromptBuilder` 即可）。
- **封面**：优先取 EPUB 的 `cover-image`，没有封面时用书名生成占位封面。
- **脚注/内部链接**：章内锚点暂不跳转，章与章之间的链接可以跳转。
- **术语自动抽取**：目前术语表是手填；可以再加一次「人物表抽取」调用，让模型先读几章生成译名表。
- **不适合长期放着不管的 Key**：如果要把 App 分享给别人用，建议改成自己的中转服务，别把 Key 塞进客户端。

## 付费与隐私提醒

- 每次翻译都会消耗 DeepSeek 的 token；开了「高质量模式」会翻倍。
- 只把**你要翻译的那段文字 + 少量上下文**发送到 DeepSeek，书籍文件本身不会上传。
- `Info.plist` 里开了 `NSAllowsArbitraryLoads`，是为了让你能填自己的中转地址（比如内网的 `http://`）。如果只走官方 HTTPS 地址，可以把它删掉，更符合审核要求。
