# iOS「今日」页切换卡顿修复方案

日期：2026-11-16。归属 T6.3 页面修复与 T6.4 设备验收。当前证据来自工作区代码与内置目录，切页时间线待采集。

## 执行记录（2026-11-17）

- 已实现当天范围 SwiftData 查询、当日记录解码缓存、营养汇总复用、懒列表、跨日/前台/时区刷新；旧“微糖”在解码时兼容，不再由主页扫描全库迁移。
- 备份快照枚举、备份记录解码和写入后重列快照已放到后台任务。品牌目录使用独立代次缓存，首次读取在后台执行，普通记录更新不再触发目录重载。
- 核心测试 67/67 通过，iPhone 18 Pro 模拟器 Debug 构建和首页启动通过。此结果只证明模型、构建及空态启动；未完成带记录/备份目录的交互验收，也未采集 Release/Profile 时间线。
- 今日页仍保留全库 `@Query` 供备份状态和备份入口使用，因此全历史模型抓取是否仍影响首帧，需要 Instruments 实测。若 Profile 显示仍是主线程瓶颈，下一步将备份查询与状态订阅移出今日视图。
- 未完成项：同设备下纯暖切页、保存后返回、已配置备份目录和真实数据量场景各重复至少 20 次；记录中位数/P95、Hitches 和主线程调用栈，并完成新建/编辑/删除/恢复等页面验收。IOS-3-02 继续保持 TODO。

## 重新评估

| 优先级 | 代码证据 | 触发条件与判断 |
|---|---|---|
| 高 | `JournalHomeView` 的 `@Query` 无日期条件。`timelineItems` 每次访问都对全部记录做 JSON 解码、校验与排序，`todayItems` 在此之后才按天筛选。饮品和用餐汇总、数量、损坏提示、列表与动画分别触发。`ForEach` 的分隔线判断还在行构建闭包中访问 `todayItems.count`。 | 只要相关视图重新计算就可能重复发生，今天为空也要扫描历史。当日有多条记录时，分隔线判断可能把全库计算乘到行数上。闭包实际调用次数取决于 SwiftUI，需采样确认。当前用餐摘要增加了一个访问点。 |
| 高，取决于备份配置 | `BackupWorkflowModel.restoreSavedFolderAccess()` 在主线程调用 `BackupDirectoryStore.listSnapshots()`。后者在 iOS 上协调读取每个快照并完整解码、校验。触发自动备份时，`backupNow()` 会在启动后台任务前解码全库，写完以后也会在主线程重列快照。 | 进入时 `.task` 如果执行，或 App 回到前台，配置了目录就可能阻塞，已无待备份项也会列快照。快照较多或文件需经 iCloud Drive 协调读取时，应优先检查这条路径。 |
| 中 | `mergeLegacyMicroSweetness()` 每次执行都扫描全部记录，找不到旧值也要解码。`JournalBrandLogoCatalog.loadBrands()` 为取得 Logo 元数据同步处理约 1.08 MB、45 个品牌和 1,734 款饮品的内置目录，还会读入本地覆盖及可用的营养更新包。普通记录保存也会递增 `libraryChangeGeneration`，触发目录重载。 | 主页 `.task` 执行、变更后返回时可能叠加。纯 Tab 来回切是否重跑 `.task` 需记录生命周期来确认。 |
| 中，取决于当天内容 | 今日外层是 `LazyVStack`，记录列表却是其中一个普通 `VStack`。一餐最多创建 4 个缩略图视图，原图读取、缩放和 JPEG 编码已在后台，渲染时仍要从缩略图数据创建 `UIImage`。菜品缺少营养快照时，顶部汇总和用餐卡片会分别估算。 | 当天有大量记录、照片或菜品时优先查看布局、图片任务及营养计算。备用优化由采样结果决定。 |

相关入口见 [今日页](/Users/jinhefeng/WeChatProjects/list/ios/GanfanHandbook/JournalHomeView.swift:67)、[记录编解码](/Users/jinhefeng/WeChatProjects/list/ios/Sources/GanfanCore/JournalModels.swift:390)、[备份流程](/Users/jinhefeng/WeChatProjects/list/ios/GanfanHandbook/StageZeroView.swift:253)、[快照列表](/Users/jinhefeng/WeChatProjects/list/ios/Sources/GanfanCore/BackupDirectoryStore.swift:359)。

今日页还订阅了整个 `BackupWorkflowModel`。快照列表、进度文字等设置页字段的变化也可能触发今日页刷新，叠加第一项开销。若只从「历史」返回才卡，采样区间也要覆盖切走前的更新，历史列表的行闭包同样会读取重新计算的 `visibleItems`。[历史列表](/Users/jinhefeng/WeChatProjects/list/ios/GanfanHandbook/JournalHomeView.swift:1547)

## 执行顺序

1. **先采基线。** 按项目约定在 Device Hub 复现，使用 Release/Profile 构建在目标 iPhone 采样。分开记录纯 Tab 返回、保存记录后返回、App 启动或回前台。用 Instruments 的 SwiftUI、Time Profiler 和 Hitches 对齐同一段交互，记录主页 `.task` 是否启动、主线程耗时最大的调用及实际解码条数。已配置备份但无待处理的场景要单独覆盖。如遇主线程长时间等待文件协调，用 System Trace 检查等待区间。[Apple SwiftUI 性能分析指南](https://developer.apple.com/documentation/xcode/understanding-and-improving-swiftui-performance)
2. **让今日页只处理当天记录。** 在 SwiftData 层按 `StoredJournalRecord.consumedAt` 查询本地日历的 `[当天起点, 次日起点)`，用日历计算次日。将同一批查询结果解码一次并排序一次，给记录数、卡片、分隔线、动画 ID 与两类营养汇总共用。保留当前同日时间升序与 UUID 同时间排序规则。用同一日期区间驱动日期标签与汇总，在跨午夜、系统时间或时区改变、App 回前台时更新。编辑内容但 ID 不变、编辑时间跨日、删除和恢复也须触发正确刷新。将全库损坏记录计数交给独立诊断，在后台按库变更更新缓存并用于现有提示，当日解码失败可立即提示。[Apple SwiftData 动态查询示例](https://developer.apple.com/documentation/swiftdata/filtering-and-sorting-persistent-data)
3. **把维护工作移出切页路径。** 由 App 层按启动、前台激活和成功提交的数据变更调度备份，今日页观察状态摘要。配置目录时，主页状态检查和完整快照列表异步读取，列表按备份设置页需要刷新。备份需要全库时，在隔离的 SwiftData 上下文读取，或在原上下文提取值数据后再后台解码。避免把 `ModelContext` 和 `StoredJournalRecord` 传给后台任务。保留目录授权生命周期、备份期间发生新变更的代次校验、失败保留待备份状态以及恢复一致性。将旧甜度兼容移出主页任务。若采用一次性迁移，成功提交后记录版本，并覆盖恢复旧快照再次带入旧值的路径。
4. **降低列表和目录开销。** 让记录行直接参与懒布局，复用已计算的条数。品牌 Logo 索引由今日、历史、摄入等页面共享，初次从后台载入，普通记录保存不重新解析目录。品牌、Logo、本地目录更新和备份恢复后使缓存失效，保留内置与自定义 Logo 的覆盖规则。有照片或菜品的场景仍掉帧时，再按采样决定是否复用缩略图和单菜营养估算。

首轮可分开提交「当天查询与列表」和「主页维护任务」。如果基线在已配置备份的场景显示主要阻塞来自快照读取，可先提交备份侧修复。先用现有日期字段实现并测量，再决定是否需要修改 SwiftData schema。

## 性能与功能验收

执行前在 `tests/mvp.test.md` 补齐今日页切换和数据刷新用例，衔接 IOS-3-02、IOS-3-16、IOS-3-24 及现有备份用例，按 `agent.md` 记录测试和设备结果。

| 场景 | 通过条件 |
|---|---|
| 固定当天条数，历史记录从 100 条增加到 1,000 条 | 主页展示链路解码历史记录数为 0。一次记录刷新中每条今日记录最多解码一次。重复切 Tab、备份状态更新和 Logo 到达时，列表与营养推导不再反复解码。 |
| 无备份目录、已配置且干净、已配置且待备份 | 今日首个可操作帧前的主线程调用栈没有完整快照枚举、云目录协调文件读写、全库备份解码或全量目录合并。手动备份、失败提示和备份期间修改记录后补备份均通过。 |
| 当天为空，或含多条带照片的饮品和用餐 | 空态、计数、卡片顺序、已保存和估算营养、未知值表达一致。滚动、详情和照片弹层正常。 |
| 新建、同 ID 编辑、跨日编辑、删除、恢复、午夜与时区切换 | 列表和两种营养汇总随数据及日期刷新。旧甜度展示、损坏提示与备份状态正确，旧快照恢复可用。 |

在同一设备、构建配置和样本下，每组暖切页至少重复 20 次。对比点按至今日首个可操作帧的中位数和 P95，配合 Hitches 与主线程调用栈判断改善。启动和回前台独立记录。首轮建议暖切 P95 不超过 100 ms，按目标设备的基线及系统切换动画耗时确认预算，同时要求没有应用代码造成的可重现切页掉帧。记录当前真机时间线前，以上均为验收目标。
