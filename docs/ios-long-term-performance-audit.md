# 吃吃喝喝 iOS 多年使用性能审计

2026-11-18 · 审计版本 `main@89e7b86` · 含测量与改动顺序复核

## 结论

**已证实的瓶颈是「历史」反复解码全库，以及「摄入」反复汇总同一批记录。** 在无照片、未配置备份的模拟器里，「今日」只解码当天记录。首页仍持有供备份使用的全库查询。配置备份后的启动、回前台和保存路径也有随资料库增长的工作，其对真机可操作时间的影响尚待测量。

按每天 6 条估算，5 年约 **11,000 条**，10 年约 **22,000 条**。在这个量级，先处理查询范围、重复计算、原图 I/O 和备份调度，现有 SwiftData 记录模型可以作为改进起点。文字与营养数据的空间占用通常比原图小得多。真实用量取决于记录内容与拍照频率。

## 后续实施进度（2026-11-18）

本审计的代码数据和计时是实施前基线。之后已将 iOS 记录主库切换为结构化 SQLite，历史默认不限日期并按 50 条分页，日期范围为可选，备份改为 SQLite 单文件且仍可导入旧 JSON。Swift 核心测试 72/72 通过，含临时 SwiftData 旧库端到端迁移与 22,000 条/440 页无重复遍历；iOS 模拟器目标构建通过。当前代码尚未用真实用户旧库、大样本设备性能、真机照片滚动或实际 iCloud 文件做复测，不能据此宣称旧实测数字已经改善到特定比例；这些值保留为改动前基线。

## 实测

在 Apple M4 / 24 GB Mac 上以 Xcode 27.2 构建 Release，使用隔离的 iPhone 18 Pro / iOS 27.2 模拟器。测试库由 SwiftData 和产品编解码器生成，包含每天 6 条、有营养值的一半饮品与一半三菜用餐记录。四档保留相同的当天记录量，均无照片、无备份目录。用启动参数直接进入被测页面，每档重复 4 次。计时从 App 的 Swift 初始化开始，`onAppear` 早于部分可见行的构建，适合作为本次插桩的生命周期指标。累计耗时统计各次目标函数的用时，采样任务在 `onAppear` 后等待 700 ms，再等主线程可执行时采集。主线程忙碌会延长实际采样窗口，累计值和调用次数用于定位重复工作。真机首个可操作画面、暖切和掉帧需按各自的交互起止点另测。

每档 4 次的中位数。历史单轮先取每次运行中各次结果计算的中位数，再汇总四次。累计耗时只统计相应计算函数，包含视图出现后继续执行的计算。

| 全库记录 | 今日 `onAppear` | 历史单轮结果计算 | 历史累计结果计算 | 摄入 90 天累计汇总 |
| ---: | ---: | ---: | ---: | ---: |
| 150 | 321 ms | 5 ms | 0.43 s | 0.29 s |
| 5,500 | 180 ms | 97 ms | 5.96 s | 0.86 s |
| 11,000 | 178 ms | 189 ms | 11.34 s | 1.12 s |
| 22,000 | 181 ms | 375 ms | 22.54 s | 1.68 s |

合成样本的近 30 天最多有 180 条，但历史页的 `visibleItems` 每次执行都会尝试解码全库。SwiftUI `List` 的行按需构建，仍在行闭包中重复执行整库工作。「摄入」只解码所选范围，日期说明、指标检测、图表和部分交互会分别访问同一个重新计算的属性。

- **今日。** 11,000 和 22,000 条的各次运行都只解码一次当天记录，读取 6 条，解码耗时约 2–3 ms。两档的同步 `ModelContainer` 初始化约 29–31 ms，视图分别约在 178 和 181 ms 触发 `onAppear`。启动期间未配置备份，宿主缓存会随批次变化。
- **历史。** 11,000 和 22,000 条样本的各次运行在采样窗口内调用了 60 次结果计算，另有 4 次损坏记录检查。视图 `onAppear` 中位数分别约为 1.13 秒和 2.03 秒。启动时预设 4,000 天范围并搜索“茉莉”各测 1 次，单轮中位数约为 250 ms 和 505 ms，累计约 14.97 秒和 30.32 秒。这个场景覆盖已有关键词时的扫描。连续输入、稀有命中和无匹配仍需单独测量。
- **摄入。** 5,500 条及以上，每次打开近 90 天页面都计算了 53 次日汇总。复用按日汇总可以直接消除由取同一份数据所触发的重复扫描。
- **本机数据库。** 无照片的 11,000/22,000 条库，数据库及 SQLite 辅助文件约占 14.6/27.8 MiB。原图另存文件，附件容量需要独立估算。

### 备份与容量

同一台 Mac 使用 `swiftc -O` 编译项目的备份核心，在 macOS 上操作临时本地目录。测试数据包含 11,000 条记录、内置饮品目录、150 个 2 MiB 的合成附件，共 300 MiB。附件用于模拟原图字节和校验开销，未做图片渲染。

- **写入。** 单次样本中首次准备与写入共 1.59 秒。只加一条无照片记录后耗时 1.49 秒，涵盖快照准备、读取本机原图、验证并复用备份原图，生成约 **10.4 MB** 的新 JSON。App 的全库 SwiftData 读出、写后重列和状态提交在这个测量之外。
- **列快照。** 用同等大小的有效快照测试 1、10、30 份，各测 3 次，中位数为 **0.17 / 1.73 / 5.17 秒**。读取规模和快照份数一起增长。iPhone 上还会经过文件协调，iCloud 文件可能需先下载。
- **读取待恢复数据。** 本地解码并校验整份归档用 0.30 秒，函数返回时持有全部 300 MiB 附件的数据句柄。完整恢复还需写回原图、恢复目录和营养数据、插入记录。

使用同一份原图的快照之间，备份目录已经复用照片文件。新增或修改后仍会重验旧原图、写一份完整资料 JSON、回读校验，再重新列出快照。照片的全量字节会同时保留在备份/恢复的 `[UUID: Data]` 中。文件可能以映射方式打开，实际常驻内存和峰值须在 iPhone 上测量。随着原图库达到数 GB，整库同时持有的设计仍会增大内存与 I/O 波动风险。清理预览还会同时持有解码后的快照，并校验最新快照的全部原图。清理需要在备份设置中手动发起。每天新增多条时，未清理的完整 JSON 会推高后续枚举成本。选择一份已有很多快照的目录时，首次列表读取仍在主线程。

以下按 365 天/年与每张原图 3 MB 估算，仅含当前引用的原图。大图、多菜照片以及备份中保留的旧照片会进一步占用空间。备份目录还需要容纳保留的快照 JSON。如果每天 6 条记录都带一张 3 MB 的原图，5 年约 **32.9 GB** 原图，iCloud Drive 备份另存相应的副本。

| 使用时间 | 每日 3 条 | 每日 6 条 | 每日 2 张照片 | 每日 4 张照片 |
| --- | ---: | ---: | ---: | ---: |
| 3 年 | 3,285 条 | 6,570 条 | 6.6 GB | 13.1 GB |
| 5 年 | 5,475 条 | 10,950 条 | 11.0 GB | 21.9 GB |
| 10 年 | 10,950 条 | 21,900 条 | 21.9 GB | 43.8 GB |

## 改动前建议实施顺序（历史与主库部分已完成，性能复测仍待完成）

1. **先消掉已经测到的重复计算。** 历史按选定日期从 SwiftData 取候选，每次更新解码一次，复用列表、分组和损坏提示的结果；摄入按 7/30/90 天取候选，共用同一份日汇总。切换图表选择沿用已计算的汇总，记录变更、本地日期或时区变化时刷新。用同一批模拟器数据复测默认历史和摄入，再看范围很长的查询还耗在哪里。
2. **单独处理首页和备份调度。** 首页只订阅当天数据和轻量备份状态。备份仍由成功保存、删除、回前台和手动操作触发，保留删除最后一条以及只改目录或设置时的资料库级待备份状态。设置页按需刷新完整快照列表；快照写入完成与列表刷新各自报告结果。写入去重时将定位候选与实际校验分开，无法确认候选是最新有效快照时按现有规则回查。
3. **按测量决定后续改动。** 用目标 iPhone 测多年范围搜索、真图滚动与多图保存、已配备份的启动和换机恢复。长范围仍慢时再做后台分批查询；图像处理进入主线程时优先迁出原图读写和校验，再按缓存命中情况决定是否需要磁盘缩略图。备份体量较大时先验证逐文件处理能否压低内存和读写峰值，之后再评估减少重复校验或改变快照格式。本机存储的全库统计和目录引用扫描可独立处理。

### 历史顺序与搜索

现代码按本地日期倒序、同一天内按时间正序、同一时间按 UUID 排序。SwiftData 列保留小数秒，历史使用 JSON 解码后的整秒时间。同一秒内两条记录可能在两种排序下换位。第一步沿用现有比较函数，日期筛选用本地日历的半开区间，并覆盖跨日、时区变化和旧数据。损坏记录提示目前按日期单独列出，用户切换记录类型或搜索时仍需看到日期范围内的损坏提示。[现有排序](/Users/jinhefeng/WeChatProjects/list/ios/GanfanHandbook/JournalHomeView.swift:1061) · [记录时间编码](/Users/jinhefeng/WeChatProjects/list/ios/Sources/GanfanCore/JournalModels.swift:388)

以后若分批加载，按展示的日期分组和顺序推进，避免跨页重复或跳过同秒记录。搜索遍历整个选定范围，包含名称、品牌、地址、备注和菜名，保留当前子串匹配。第一批没命中时继续查找后面的候选，范围查完才报无结果；日期、类型或关键词改变时丢弃旧查询结果。至少验证仅匹配多年以前一条、没有匹配、同秒记录跨批次，以及边加载边编辑或删除。

### 备份与恢复的完整性

移开首页列表仍会留下 `latestSnapshot(matching:)` 写入前调用 `listSnapshots()` 的开销。摘要或最新文件指针用于展示或定位候选，完整性以实际文件为准。备份目录可能被另一台设备或用户修改，复用的原图及自定义 Logo 仍按长度和 SHA-256 验证。分批读取时需确保发布的是同一个资料库版本，写入成功且该版本仍是当前版本才能清除待备份标记；出现新变更就保留标记并重试。目录写入成功与 iCloud 上传完成继续分别显示。[写入时定位最新快照](/Users/jinhefeng/WeChatProjects/list/ios/Sources/GanfanCore/BackupDirectoryStore.swift:479) · [当前备份状态确认](/Users/jinhefeng/WeChatProjects/list/ios/GanfanHandbook/StageZeroView.swift:375)

可以先在现有快照格式下逐文件读写和校验。恢复时将附件、记录及设置放入可回滚的准备流程，验证完成后才更新可见资料库。逐批提交到正在使用的库会留下部分恢复结果，而且现有恢复入口会拒绝再次向非空库恢复。需要覆盖旧快照、照片或 Logo 中途丢失、空间不足、用户退出，以及重启后重试。保留当前备份历史和清理行为。

### 照片与低频页面

列表已在后台缩小图片，离开后再次打开时可能重读原图、重新校验并编码。全屏看图会在主线程读取当前原图并为一餐的图片生成缩略图，多图餐食保存也有同步文件工作。如果实拍复测确认这里掉帧，先迁出主线程；缓存按资产和尺寸设上限，需要时可重建。

本机存储页为了找最近 8 张照片会解码并排序全库相关记录，也会同步遍历照片文件和读取记录体积。目录页删除饮品时会解码历史判断引用，饮品表单还会同步载入目录。可分别通过倒序按批取样、后台统计和复用目录结果降低这些页面的成本。

[历史过滤与行构建](/Users/jinhefeng/WeChatProjects/list/ios/GanfanHandbook/JournalHomeView.swift:1584) · [记录解码校验](/Users/jinhefeng/WeChatProjects/list/ios/Sources/GanfanCore/JournalModels.swift:397) · [SwiftData 动态查询示例](https://developer.apple.com/documentation/swiftdata/filtering-and-sorting-persistent-data)

[今日页查询与触发点](/Users/jinhefeng/WeChatProjects/list/ios/GanfanHandbook/JournalHomeView.swift:161) · [自动备份](/Users/jinhefeng/WeChatProjects/list/ios/GanfanHandbook/StageZeroView.swift:296) · [快照读取与恢复](/Users/jinhefeng/WeChatProjects/list/ios/Sources/GanfanCore/BackupDirectoryStore.swift:359) · [恢复插入](/Users/jinhefeng/WeChatProjects/list/ios/Sources/GanfanCore/JournalLibraryRestoreService.swift:117)

[摄入汇总](/Users/jinhefeng/WeChatProjects/list/ios/GanfanHandbook/JournalHomeView.swift:2527) · [列表缩略图](/Users/jinhefeng/WeChatProjects/list/ios/GanfanHandbook/JournalHomeView.swift:955) · [全屏照片](/Users/jinhefeng/WeChatProjects/list/ios/GanfanHandbook/JournalHomeView.swift:3996) · [多图餐食保存](/Users/jinhefeng/WeChatProjects/list/ios/GanfanHandbook/RecordForms.swift:1288) · [提交时校验](/Users/jinhefeng/WeChatProjects/list/ios/Sources/GanfanCore/JournalRecordCommitService.swift:15)

[本机存储统计](/Users/jinhefeng/WeChatProjects/list/ios/GanfanHandbook/JournalHomeView.swift:2699) · [目录删除引用检查](/Users/jinhefeng/WeChatProjects/list/ios/GanfanHandbook/CatalogManagementView.swift:652) · [录入表单加载目录](/Users/jinhefeng/WeChatProjects/list/ios/GanfanHandbook/RecordForms.swift:74)

数据模型已有独立的日期、类型和备份标记字段。打开测试库确认当前仅有记录 ID 的唯一索引。先通过按范围查询和分页减少数据，再用时间线确认日期排序/筛选是否需要单独的索引。SwiftData 的 `#Index` 是 iOS 18 的模型能力，项目部署目标是 iOS 17.0，采用前需要兼顾最低版本、旧库升级和旧快照恢复。若多年文本搜索仍需要优化，可再评估单独的搜索字段或索引，并保持中文子串、备注、地址和菜名的匹配行为。 [现有存储字段](/Users/jinhefeng/WeChatProjects/list/ios/Sources/GanfanCore/StoredJournalRecord.swift:42) · [部署目标](/Users/jinhefeng/WeChatProjects/list/ios/GanfanHandbook.xcodeproj/project.pbxproj:250) · [Apple SwiftData 索引介绍](https://developer.apple.com/videos/play/wwdc2024/10137/?time=716)

## 设备验收

先用同一份小库和 22,000 条库对照改动，保持当天记录、可见日期范围、设备和构建一致。第一轮验证固定日期范围的历史解码条数跟候选数走，每条只解码一次；历史与摄入的列表分组、损坏提示和营养口径一致；点选图表沿用同一份日汇总。

在目标 iPhone 上以 Release/Profile 测冷打开到首次可交互，单独测回前台和暖切。启动至少覆盖未配备份、已配置且干净、已配置且待备份，以及 iCloud 文件未下载的状态。使用真实 JPEG/HEIC 另测滚动与多图保存。按项目暖切验收方案记录中位数和 P95，采集卡顿时间线、主线程栈，以及备份/恢复过程的峰值内存和实际读写字节。备份测试同时核对保存后退出、备份期间编辑、目录外部改动、重新打开后的待备份状态与旧快照恢复。 [现有今日页验收方案](/Users/jinhefeng/WeChatProjects/list/docs/ios-today-performance-plan.md) · [Apple SwiftUI 性能采样方法](https://developer.apple.com/documentation/xcode/understanding-and-improving-swiftui-performance)

基线审计当时未跑真机、带照片的 UI 滚动、暖切、真实 iCloud 下载/上传与大库完整恢复，也未修改产品行为或读取用户资料库。后续代码实现仍未完成上述实测。仓库另有微信小程序，源代码显示它同步整读、整写一份记录数组，历史页还对整库排序；多年使用时单次写入和微信存储容量也需单独验收。上面的计时只覆盖 iOS 改动前基线。 [小程序存储入口](/Users/jinhefeng/WeChatProjects/list/utils/store.js:75) · [小程序记录排序](/Users/jinhefeng/WeChatProjects/list/utils/domain.js:90)
