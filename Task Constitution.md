# Task Constitution

## 1. Mission
Build the meal-logging product, with the current release direction as the native iOS app “吃吃喝喝”: local-first drink and meal records, user-selected iCloud Drive backup, and no historical-data migration.

## 2. Success Criteria
- [ ] Menu data has a stable structure for brands, drinks, city/store availability, options, nutrition variants, sources, and verification dates.
- [ ] Menu editors can import and validate batches without changing mini-program code for every update.
- [ ] The mini program can use a bundled catalog and optionally refresh from a versioned HTTPS catalog while preserving user-created drinks.
- [ ] Users can search, add, and edit catalog drinks in the mini program, including brand, optional category, aliases, one per-100-ml nutrition baseline, and active state; exact size variants take priority and the baseline scales to the recorded size.
- [ ] For the agreed mainstream brands, every drink listed in the current public menu is captured with its source and check date; city/store availability remains a separate verified layer.
- [ ] A user can still record a drink immediately when a brand or new item is missing from the catalog, and that gap can be reviewed for catalog follow-up.
- [ ] Drink and meal records have separate entry points and appear together in one time-ordered history.
- [ ] Meal records save an address, store name, automatic time, and multiple named dishes with individual photos.
- [ ] Mini Program and beverage-only totals exclude meals; native iOS Insights combines shared meal/drink nutrients per T6.3 while keeping beverage volume and caffeine drink-only; existing local drink records remain readable.
- [ ] The iOS app starts with an empty local library, saves records and photos on-device, and can back up to and restore from a user-selected iCloud Drive folder.
- [ ] The iOS app reproduces the Mini Program's nine page and data behaviors, applies the approved Logo and visual language, and keeps the first release single-user while retaining stable-ID/versioned-data seams for a future shared list.

## 3. Task Tree
### T6 — Native iOS app「吃吃喝喝」
- Status: 进行中（品牌及九页部分代码已接入；全功能和页面/设备验收仍待完成）
- Objective: Deliver a branded, local-first iPhone app reproducing all nine Mini Program pages and their data behavior, without importing Mini Program history; preserve the user's existing iOS records and keep a bounded extension path for future shared lists.
- Acceptance: Nine pages/data contracts are mapped and accepted; offline records/photos, menu, history, nutrition insights, diagnostics, and backup/restore work; iOS data survives upgrades; no login/sharing in v1; stable IDs and versioned boundaries support future architecture work.
- Details: `docs/ios-development-plan.md`; page/data map `docs/ios-miniprogram-parity-map.md`; core checks in `tests/mvp.test.md` sections G–I and full parity checks in section J.
- Current result: Native SwiftUI target includes local-first drink/meal flows, selected-folder backup/restore, the approved Logo/AppIcon, all nine page shells, and the first drink-data parity increment. Temperature/ice fields are backward-decodable; nutrition variants and per-unit baselines preserve confidence and source URL. Full effective drink catalog, nutrition data pack, custom logo assets, and logo visibility/overrides are now included in backup/restore, with legacy-snapshot compatibility; drink and meal forms support MapKit selection and manual address fallback. Swift core automation passes 54/54, and unsigned iOS/device-SDK and simulator builds succeed. The latest iPhone 18 Pro simulator screenshot confirms one visible brand title, an in-content search field, and a compact drink-count/cup/nutrition summary. Full page interaction/visual parity, physical iPhone launch (previous attempt stopped at the untrusted Developer App certificate), and actual iCloud delivery remain unverified.
- Next action: Continue page-by-page interaction and visual checks, then verify the selected-folder backup flow and empty-library restore on the physical iPhone after its developer certificate is trusted.

#### T6.1 — 页面/数据基线与品牌视觉
- Status: 进行中（九页映射、Logo/AppIcon 和共享品牌组件已接入；模拟器首页已做局部视觉检查，其余页面仍待对照）
- Objective: Establish the nine-page parity baseline and shared iOS brand system.
- Acceptance: Page map covers current iOS state, target behavior and data; IOS-3-01/02 are implemented and visually reviewed against the Mini Program.
- Depends on: T6 approval
- Evidence: `docs/ios-miniprogram-parity-map.md`; `tests/mvp.test.md` J-01/J-02.

#### T6.2 — 数据契约与本机仓储边界
- Status: 进行中（菜单、完整饮品目录和营养数据的备份恢复兼容已接入；重复快照抑制、旧备份预览清理及本机旧品牌/菜单自动合并已实现；本机仓储抽象和全量兼容验收仍待完成）
- Objective: Complete the catalog/nutrition/local override contract and isolate local persistence behind a replaceable boundary, with versioned IDs and backup compatibility.
- Acceptance: Domain tests cover catalog, nutrition provenance, custom overrides and stable record/photo IDs; existing iOS data stays readable; no account, membership or online sync is introduced.
- Depends on: T6.1

#### T6.3 — 九页功能与数据补齐
- Status: 进行中（新增品牌、网页菜单/Logo 候选、裁切保存及旧目录合并已接入；摄入洞察趋势页已实现，页面交互与视觉验收仍待完成）
- Objective: Complete Today, drink entry, catalog, meal entry, photo preview, storage diagnostics, history, record detail and nutrition insights.
- Acceptance: IOS-3-02–15 pass their behavior and page gates; IOS-3-13 defaults to 7 days with 30/90-day options and orders metrics as 热量、咖啡因、糖、脂肪、蛋白质、碳水化合物、水分（饮品）; has no separate daily-average cards, shows each metric's range average with the concise label 日均摄入 and the number of days used, excluding missing days from the average, and uses consistent cards with latest valid-day value, latest contributing record time, and a noninteractive mini trend on the collapsed face without a redundant source/estimate/date footer; the card flips to a large chart on tap, chart taps select a day immediately, vertical movement scrolls the page, and selection persists after release; drink-only metrics remain bar charts with visible fixed-point widths calculated from chart size and range length; combines shared meal/drink nutrients, keeps beverage volume/caffeine drink-only, includes estimates, preserves missing values as gaps, and has no record list; single-user navigation and filtering match scope.
- Depends on: T6.1, T6.2
- Current result: 饮品目录提供“新增品牌”向导，可在百度/Bing 的 App 内网页中读取结构化商品名、菜单列表和图片候选；用户可编辑菜单并选择、裁切 Logo 后保存。检索不调用 AI 或搜索 API，菜单候选保留网页来源并标记待核验。目录加载会把旧本地品牌按唯一名称/别名迁到内置 ID，合并同名菜单并保留旧饮品 ID；用户 Logo 优先，无用户 Logo 时继承软件包图案，恢复出的目录也会处理。今日页已按日查询并缓存解码结果，备份 I/O 和目录首次读取移到后台；核心测试 67/67、iOS 模拟器 Debug 构建和空态启动通过。历史数据量、备份目录与完整页面交互及 Release/Profile 性能采样仍待验收。

#### T6.4 — 集成与设备验收
- Status: 进行中（今日页模拟器空态启动通过；Release/Profile 性能和目标设备交互待测）
- Objective: Verify visual parity, data preservation, offline behavior, selected-folder backup and empty-library restore on the target iPhone.
- Acceptance: IOS-3-16/17 and relevant real-device checks pass; build, automation, UI runtime and cloud sync evidence remain distinct.
- Depends on: T6.1–T6.3

### T1 — Catalog structure, maintenance, and update foundation
- Status: 进行中
- Objective: Define the catalog contract, in-app maintenance flow, batch import, and safe mini-program update path.
- Acceptance: A template and importer produce a validated versioned catalog; users can search/add/edit catalog entries in the app; the app can opt into remote refresh and retain a local fallback and local overrides.
- Current result: Maintenance defaults to an empty list; search/filter or “展示全部饮品” opens 30-row batches. A global cup-type/capacity setting is shared by drink entry, Today, History, and Intake; record views hide capacity. Existing record sizes and complete nutrition snapshots remain intact. Custom-drink saves no longer add product-level cup mappings. The record form can add a missing drink directly to the selected existing brand and retain that brand association. Deletion requires confirmation and is blocked while any local record references the drink; local tombstones prevent configured remote refresh from restoring it. Brand/drink selectors share aligned label, value, and arrow columns; editing opens a scrollable modal over the unchanged list; the full-list button sits at the right of the catalog count card. Saving edits preserves active filters and the loaded batch size. A no-AI brand import wizard collects editable menu candidates and Logo choices from web pages. A phone-export importer maps unique names/aliases to stable brand IDs, merges same-name menus while preserving historical drink IDs, follows user-logo/package-logo precedence, imports Logo assets, and regenerates the iOS catalog; records, photos, and API settings are excluded.

### T2 — 补全主流品牌菜单并核验城市门店
- Status: 进行中（候选菜单仍不完整；权威品牌菜单与门店核验待补）
- Objective: Build complete drink-name coverage from the current public menus of mainstream tea chains and major coffee chains, then reconcile store availability for center-city samples in Hangzhou Shangcheng District, Changzhou Tianning District, and Shanghai Huangpu District.
- Acceptance: Every drink shown in each selected brand's current public menu is in the catalog with source and check date; each city/store listing is separately marked verified, pending, or unavailable; users can search an item or add a missing one without leaving the record flow.
- Depends on: T1
- Current blocker: Public brand menus do not establish which items a specific Taobao Flash Sale store sells. Public source paging is also incomplete; 喜茶第 1–11 页已检查，但第 10 页所指第 12 页目前无法读取，且不同页面自报 207–222 款、11–12 页；蜜雪冰城第 1–9 页已检查，不同页面自报 161–174 款且有跨页重复；古茗第 1–6 页已检查，汇编自报 117 款并有重复名称。Four ranked coffee brands have no reliable mainland current-menu source, and 猫屎咖啡 has only a Guangzhou single-store recommendation sample. Latest searches found wrong-region or same-name results for missing brands (including a Hong Kong Pacific Coffee menu and an unrelated Blue Lane Coffee); none is valid mainland menu evidence. Keep references pending until sourced and audited; do not claim platform-level or brand-menu completeness prematurely.
- Brand-scope basis: [2026 tea-chain top 15](https://ranking.iimedia.cn/ranking/161) plus [2026 coffee-chain top 15](https://www.iimedia.cn/c880/112246.html), with Starbucks added as a major global chain. The two ranked lists do not overlap, so the initial target is 31 brands; city sample review may identify additional high-coverage local brands.
- First result: The catalog now has 32 brands and 789 candidate drink names, tracked in `data/catalog-coverage.json`. This includes 16 additional 1点点 national-launch names, four 沪上阿姨 menu-page names, the Hangzhou-limited 阿嬷手作 drink 桂花酒酿一米, 109 new 喜茶 candidates from pages 2–11, 117 new 蜜雪冰城 candidates from pages 2–9, and 95 new 古茗 candidates from pages 1–6. Official store locators list 1点点 locations in all three sample districts; a local report documents 阿嬷手作 delivery orders during a 2026 campaign. Current Taobao Flash Sale store menus remain pending, and none of the core 31 brands has passed the all-pages completeness audit.

### T3 — Review coverage and keep menus current
- Status: 未开始
- Objective: Track missing brands, changed menus, and catalog release history.
- Acceptance: Coverage can be reviewed by city and brand, and stale or unavailable entries are visible for follow-up.
- Depends on: T1, T2

### T4 — 零星项目 / Miscellaneous
- Status: 未开始
- Objective: 收纳不属于主工作流的小型、独立事项。
- Acceptance: 每个事项都有来源、状态和下一动作。
- Children: as needed

### T5 — 饮食记录扩展 / Meal logging
- Status: 进行中
- Objective: Add meal records while keeping drink entry separate and sharing one chronological history.
- Output: A meal entry page, map-confirmed addresses, drag-reorderable multi-dish records, mixed timeline rendering, and beverage-only summaries outside the native iOS Insights trends.
- Acceptance: Users can save and edit a meal with a map-confirmed address, store name, time, and named dishes with individual photos; record cards show their map location last when available; one drink-style meal card shows every dish name, a fully visible first photo, clearly offset later photos exposed on the right, and a “共 X 张” badge; opening a meal photo shows all photos in that record with swipe navigation and tappable bottom thumbnails; meal and drink records sort together by time; the History page shows each date once for consecutive same-day records and supports multi-select record-type filters discovered from stored records, including unknown future type keys; new types are included by default and legacy records without a type remain drinks; beverage-specific totals remain drink-only, while native iOS Insights combines shared nutrients under T6.3; create-entry buttons appear on Today, not History or Intake; Today links to All Records, catalog and local-storage diagnostics; the native iOS app has four bottom tabs (Today, History, Insights, Menu), with local-storage diagnostics reachable from Menu and no Intake tab.
- Depends on: Existing local record storage, native map selection, and local photo persistence.
- Diagnostics: 17 tests + 18 quota-model checks; device pending. See docs/photo-storage-whitebox.md.
- Next action: Check date grouping, content scrolling, and navigation through Today links and native back; review the photo stack and viewer in WeChat Developer Tools, then verify map selection and dish ordering on device.

## 4. Current Focus
- Task: T6.3
- Parent path: T6 → T6.3
- Objective: Complete and verify the nine iOS page flows against the Mini Program's behavior and data contracts.
- Next action: 按新趋势页口径完成摄入洞察的图表交互与视觉验收；九页页面门未完整通过前保持 T6.3 进行中。

## 5. Decision Log
| Date | Decision | Rationale | Impact |
|---|---|---|---|
| 2026-10-14 | Start with Hangzhou, Changzhou, and Shanghai; keep platform/store coverage distinct from brand-level product identity. | Existing project scope names these three cities and menus vary by locality. | Catalog rows carry city/store provenance and verification status. |
| 2026-10-14 | Keep remote catalog refresh optional until an HTTPS endpoint is configured. | This repository has no cloud backend or approved catalog host configured. | The app remains usable from bundled/local data; deployment setup is documented. |
| 2026-10-15 | Use Taobao Flash Sale as the current platform source; do not treat the legacy Ele.me H5 page as current menu evidence. | Alibaba Group says Ele.me was fully rebranded as Taobao Flash Sale in December 2025; the legacy H5 page returned no usable sample-store menu and Taobao web navigation was blocked by site-safety policy. | City/store menu items stay pending until verified from an approved Taobao Flash Sale page. |
| 2026-10-15 | Use public menu pages to seed brand and drink names while keeping all entries pending. | The user asked to search publicly available menus; public menus are useful for discovery but do not show the current menu of the selected Taobao Flash Sale sample stores. | Each reference keeps its source URL and cannot be promoted to verified until checked against a local platform menu. |
| 2026-10-15 | Raise the menu acceptance bar from a starter list to every drink in current public menus for the agreed mainstream brands. | The user said missing a purchased drink could make users abandon the product; a starter list is insufficient. | T2 tracks source-page completeness separately from local Taobao Flash Sale store verification; the initial brand boundary is 2026 top-15 tea + 2026 top-15 coffee + Starbucks. |
| 2026-10-15 | Keep source-reported menu totals and reviewed pages in a separate coverage ledger. | Public aggregators have changing counts and some pages mix food or frozen desserts with drinks. | Current catalog counts remain candidates; none are treated as complete until page-by-page reconciliation. |
| 2026-10-15 | Keep drink and meal entry separate, but place both record types in one time-sorted history; meal photos belong to individual dishes. | The user wants separate input flows and a shared history. | Beverage-only summaries remain drink-only; native iOS Insights follows the later combined-trend scope. |
| 2026-10-15 | Show each meal as one drink-style history card with every dish photo and name. | The user chose the single-card option for meal history. | Home and history cards show all dishes together; dish order follows the entry form. |
| 2026-10-15 | Use a right-side exposed photo stack and an enlarged viewer with swipe navigation and tappable bottom thumbnails. | The user selected the right-side stack and requested switching among the photos in one meal. | Home, history, and meal editing open the same ordered photo viewer with a “共 X 张” badge on cards. |
| 2026-10-15 | Keep meal and drink creation buttons on Today; keep History and Intake focused on review. | The user asked to show drink locations on Today and remove create buttons from the other two tabs. | Drink and meal cards display map locations last when available; History and Intake have no add-entry buttons. |
| 2026-10-15 | Match Today drink-card information order to History and place location last. | The user reported inconsistent field order and excessive bottom whitespace hiding page content. | The three pages use compact bottom-safe-area spacing; fixed navigation was later removed. |
| 2026-10-15 | Remove the fixed bottom navigation and show a date only on the first record for each day. | The user asked to remove the bottom bar and reduce repeated dates in the History timeline. | Today links to All Records; catalog maintenance uses a header icon; secondary pages return through native back navigation. |
| 2026-11-13 | Replace the earlier iOS no-tab layout with four bottom tabs: Today, History, Insights, and Menu. | The user provided a revised home-screen reference and asked to optimize the overall layout to match it. | This supersedes the 2026-10-15 iOS bottom-navigation decision; the Mini Program is unchanged. Storage diagnostics remains accessible from Menu. |
| 2026-10-15 | Keep only the All Records link on Today and represent catalog maintenance with an icon. | The user asked to remove the Intake link and replace the catalog text entry with a simple icon. | The catalog page remains reachable from the header icon. |
| 2026-10-15 | Build History record-type options dynamically from saved records; treat missing legacy types as drinks and auto-select newly observed types. | The user asked for type filtering that can grow with future record categories. | Known types have friendly labels; unknown types remain filterable by their stored key. |
| 2026-10-15 | Added an in-app beverage list page for searching, adding, and editing brand, category, aliases, and per-unit nutrition. | The user needs drink data to be maintainable in the Mini Program so missing items and nutrition can be added. | Unit nutrition is a labeled fallback; edits are stored locally and preserved during configured catalog refresh. |
| 2026-10-15 | Simplified catalog nutrition to one per-100-ml baseline, rendered 30 matches at a time, made category optional, and automatically saved record-created custom drinks into the local catalog. | The user asked to reduce nutrition entry to one value set and avoid a large default list; prior custom entries should be reusable. | Exact size variants still take priority; known legacy cup values can convert, ambiguous legacy values remain unchanged; local custom drinks appear in later record selection. |
| 2026-10-15 | Unified record nutrition input with the catalog's per-100-ml unit, saved per-record nutrition snapshots, required capacity for custom nutrition calculations when unknown, and displayed cup type plus capacity on Today. | The user reported missing cup labels and nutrition values that did not persist or match catalog units. | Historical snapshots remain stable when catalog data changes; custom drink baselines sync locally for later selection. |
| 2026-10-15 | Hid cup capacities from record and history views, added per-drink capacity configuration, made the catalog list empty until searched/filtered with 30-row view batches, simplified per-100-ml field labels, and added reference-guarded confirmed deletion. | The user approved the plan and specified hidden capacities and safe deletion. | Missing capacity preserves the baseline but skips serving conversion; referenced drinks are retained, and local deletion is retained through configured remote refresh. |
| 2026-10-15 | Moved cup names and capacities to one shared setting, added a button to expose the full catalog in 30-item batches, and separated card actions into a stable bottom row. | The user wants global cup sizes, explicit full-list access, and a clearer catalog card. | Existing record sizes and snapshots remain intact; all new record and summary calculations read the global mapping. |
| 2026-11-17 | Native iOS Insights uses 7/30/90-day per-metric trends ordered 热量、咖啡因、糖、脂肪、蛋白质、碳水化合物、水分（饮品）; consistent cards show latest values/timestamps, flip from a noninteractive mini preview to a selectable large chart, and preserve selection on release; shared meal/drink nutrients combine, drink volume/caffeine stay separate, estimates count, and missing values remain gaps. | User approved the new Insights design and implementation. | T6.3, IOS-3-13/14; Mini Program behavior unchanged. |
| 2026-11-18 | Removed the two standalone daily-average cards, added range averages and data-day coverage to each metric card, made chart taps select values immediately, and switched drink charts to daily lines for 30/90-day ranges. | User approved the revised card layout and interaction. | T6.3, IOS-3-13/14; Mini Program behavior unchanged. |
| 2026-11-18 | Simplified the card average label to “日均摄入” with a day-count basis, and made chart selection gestures coexist with vertical page scrolling. | User asked to simplify the wording and allow scrolling from within the expanded chart. | T6.3, IOS-3-13/14; Mini Program behavior unchanged. |
| 2026-11-18 | Removed the redundant collapsed-card footer and kept caffeine/water charts as bars in all ranges with range-adaptive widths. | User asked to remove the source/date footer and improve the bar-chart density without using lines. | T6.3, IOS-3-13/14; Mini Program behavior unchanged. |
| 2026-11-18 | Replaced proportional bar widths with plot-size-aware fixed widths and removed chart drag selection so vertical page scrolling remains available; chart values are selected by tap. | User reported bars disappearing and intermittent vertical scroll conflicts. | T6.3, IOS-3-13/14; Mini Program behavior unchanged. |

## 6. Knowledge Context
- Constraints: Preserve existing Mini Program changes. The iOS app starts empty, stores its working library on-device, and writes backup copies to a user-selected directory that may be in iCloud Drive; no historical migration is needed. Do not claim sample or pending menu items are verified.
- Dependencies: A future HTTPS host must be added to WeChat's request domain allowlist before remote refresh works in production.
- Relevant files: `data/catalog.js`, `utils/store.js`, `pages/record/record.js`, `README.md`.

## 7. Change History
| Date | Change | Reason | Affected tasks |
|---|---|---|---|
| 2026-11-17 | Updated native iOS Insights and IOS-3-13/14 acceptance for the requested metric order, daily meal/drink nutrition trends, separate beverage metrics, estimate handling, and missing-data gaps. | User approved syncing the new page scope into the project documentation. | T6.3 |
| 2026-10-26 | Added read-only photo/cache diagnostics and exact photo errors. | User approved diagnosis; device check pending. | T5 |
| 2026-11-13 | Started native iOS app “吃吃喝喝” as a fresh local-first product with selected-folder iCloud Drive backups; no historical-data migration. | User approved the iOS direction and development plan. | T6 |
| 2026-11-13 | Implemented the first local-record UI/core and advanced T6 to backup/restore; 21 Swift core tests pass and iOS/Simulator SDK builds succeed, with device runtime gates still pending. | Continued the approved implementation plan and kept automated evidence separate from device acceptance. | T6 |
| 2026-11-13 | Implemented versioned file snapshots, original-photo verification, automatic/manual backup triggers, snapshot listing, and transactional restore to an empty SwiftData library; 38 Swift core tests pass and both SDK builds succeed. | Continued T6 through the backup/restore code package while preserving device gates for real iCloud behavior. | T6 |
| 2026-11-13 | Expanded the approved iOS scope to all nine Mini Program pages and data behaviors, retained single-user v1, and recorded future shared-list constraints without enabling collaboration; added the parity map and IOS-3 acceptance cases. | User requested eventual full page/data reproduction, Logo use and future multi-person extensibility, then approved the iteration plan. | T6, T6.1–T6.4 |
| 2026-11-13 | Added backward-compatible drink temperature/ice fields, legacy serving normalization, nutrition variant/per-unit calculation with provenance, and form/detail display; 51 core tests and the latest iOS SDK build pass. | Continued the approved nine-page iOS implementation and filled an identified drink-data gap. | T6.2, T6.3 |
| 2026-11-13 | Added menu/cup settings to versioned backup restore, MapKit selection and manual address fallback to drink/meal forms, map display in details, and Home title/search/summary-card refinements; 54 core tests pass and the latest iPhone 18 Pro simulator screenshot was reviewed. | Continued the approved page-parity iteration while keeping physical-device, iCloud-delivery, and remaining page gates distinct. | T6.1–T6.3 |
| 2026-11-15 | Suppressed duplicate snapshots; added retention preview/confirmation, 7-day grace, and cleanup for unreferenced backup images. | User approved reducing redundant snapshot growth while preserving a review step and recovery history. | T6.2, T6.4 |
| 2026-11-16 | Fixed backup snapshot result typing, SwiftUI snapshot summary type-check complexity, and byte-count formatter usage; Swift package and iOS Simulator builds pass. | User reported compile errors after backup retention implementation. | T6.2, T6.4 |
| 2026-11-16 | Added a no-AI brand import wizard with editable web-extracted menu candidates and Logo cropping, plus phone catalog export and a preview-first project importer for brands, drinks, and Logo assets. The simulator build, JavaScript syntax checks, and diff whitespace check pass; device interaction and a real phone export/import remain unverified. | The user asked for an add-brand flow and a way to bring phone-maintained catalog data back into the project, then asked whether web research can work without AI. | T1, T6.3 |
| 2026-11-16 | Added idempotent migration from old local/restored brands to unique packaged name/alias matches; merged duplicate menus, preserved historical drink IDs, applied user-logo/package-logo precedence, and made the phone importer use the same identity rule. Swift core 65/65, targeted Node 10/10, and iOS 27.2 Simulator Debug build pass; full `npm test` still reports six domain/Mini Program failures outside this change, and real phone data/device acceptance remains open. | User approved name-based brand/menu merging with user-custom logos preferred and packaged logos used when local logos are empty. | T1, T6.2, T6.3 |
| 2026-10-14 | Created initial task tree for the catalog expansion and update work. | User approved the catalog foundation and three-city verification approach. | T1–T3 |
| 2026-10-15 | Corrected platform source references and recorded the Taobao Flash Sale page-access blocker. | User clarified that current research must use Taobao Flash Sale. | T2 |
| 2026-10-15 | Added 15 brands and public menu reference products with source links; all stay pending. | User requested public online menu research after direct Taobao access was unavailable. | T2 |
| 2026-10-15 | Expanded the coverage boundary to the 2026 top-15 tea chains plus major coffee chains and changed T2 acceptance to full current public-menu coverage. | User clarified that missing any purchased drink threatens ongoing use. | T2; current focus moved from T5 to T2 |
| 2026-10-15 | Expanded the working boundary to the 2026 top-15 tea and coffee rankings plus Starbucks; added the 11 coffee-ranking brands missing from the seed and a per-brand coverage ledger. | The earlier boundary missed much of the ranked coffee category; the user requires comprehensive drink discovery. | T2; 31 brands and 447 candidate names, all still subject to source/page and store verification |
| 2026-10-15 | Rechecked the four brands without usable mainland menus and kept them marked as source gaps. | Public searches surfaced Hong Kong Pacific Coffee materials and unrelated Blue Lane/DIO names, but no current mainland menu for 上岛咖啡、蓝湾咖啡、迪欧咖啡 or 太平洋咖啡. | T2 remains in progress; no brand or platform-level completeness claim is justified. |
| 2026-10-15 | Refreshed third-party source counts while keeping them explicitly non-authoritative. | The open pages report 119 M Stand drinks/6 pages and 135 Lucky Coffee drinks/7 pages; Starbucks changed from an earlier 263/14 observation to 230/12. | T2 records source observations, not verified expected counts or Taobao Flash Sale inventory. |
| 2026-10-15 | Added T5 after user approval to capture meal logging as a product workstream. | User requested separate drink/meal entry and a shared history. | T5 |
| 2026-10-15 | Fixed meal and drink photo handling to save temporary images before previewing or generating thumbnails. | Developer Tools returned 500 for temporary image URLs and warned that `wx.saveFile` is deprecated. | T5 |
| 2026-10-15 | Removed manual address inputs, added map-only address selection, multi-dish drag sorting, and all-dish rendering in meal cards. | The user required map-confirmed locations, reorderable dishes, and selected the one-card history layout. | T5 |
| 2026-10-15 | Changed meal photos to a right-side exposed stack and added a shared swipeable viewer with tappable bottom thumbnails. | The user chose the right-side stack and asked to switch within the current meal record. | T5 |
| 2026-10-15 | Added drink locations to Today cards and removed create-entry buttons from History and Intake. | The user asked Today to show beverage locations and wanted the other two tabs focused on reviewing records and intake. | T5 |
| 2026-10-15 | Removed fixed bottom navigation and showed each History date once per day. | The user asked to remove the bottom bar and reduce repeated same-day dates. | Today links to All Records; catalog maintenance uses a header icon, and native back returns from secondary pages. |
| 2026-10-15 | Replaced the catalog text link with an icon and removed the Today-to-Intake link. | The user wanted a quieter catalog entry and only an All Records link on Today. | T5 |
| 2026-10-15 | Added a multi-select record-type filter whose options come from stored record types, with new types included by default. | The user requested type filtering and noted that more record types may be added later. | T5; unknown type keys remain filterable and are not rendered as drinks. |

| 2026-10-15 | Simplified nutrition editing to one per-100-ml baseline, added incremental rendering, made category optional, and saved record-created custom drinks into the local catalog. | The user requested lower maintenance effort and reusable custom drinks. | Exact size nutrition remains preferred; ambiguous legacy per-cup values are preserved; T1 is the current focus. | T1 |

| 2026-10-15 | Added the in-app beverage catalog page with editable brand, category, aliases, and per-unit nutrition. | The user asked to maintain missing and existing drink data directly in the mini program. | T1 |
| 2026-10-15 | Unified record nutrition input with the catalog's per-100-ml unit, saved per-record nutrition snapshots, required capacity for custom nutrition calculations when unknown, and displayed cup type plus capacity on Today. | The user reported missing cup labels and nutrition values that did not persist or match catalog units. | T1 |
| 2026-10-15 | Hid capacity in record/history UI, added editor configuration for cup-to-capacity mappings, made the list demand-driven with 30-item chunks, simplified nutrition labels, and added deletion confirmation/reference blocking. | The user approved the plan and specified hidden capacities and safe deletion. | T1 |
| 2026-10-15 | Changed cup types/capacities to a shared local setting; added the all-drinks button with 30-row batching and stabilized card action layout. | The user requested global cup settings, a full-list entry point, and clearer drink cards. | T1 |
| 2026-10-15 | Aligned brand/drink selectors, moved catalog edits into a list-preserving modal, and placed “展示全部” in the count card; edit saves retain the current filter and loaded batch size. | The user confirmed the UI refinement plan. | T1; runtime interaction still needs WeChat Developer Tools review. |
| 2026-10-15 | Added 21 candidate drink names from current public menu/release sources, including a Hangzhou-only 阿嬷手作 drink; recorded official 1点点 store listings in all three sample districts and kept Taobao Flash Sale availability pending. | The user asked to expand the list around takeout drinks available in the three city centers. | T2; 32 brands and 468 candidates, with store-menu checks still outstanding. |
| 2026-10-16 | Added 109 drink-name candidates from 喜茶 menu pages 2–11, recorded page review and changing source totals, and bumped the bundled catalog version. | The user asked to continue finding broader public menus; pages mix drinks with desserts and report inconsistent totals. | T2; 32 brands and 577 candidates. Page 12 remains unreadable; all entries remain pending for specific-store availability. |
| 2026-10-16 | Added 117 drink-name candidates from 蜜雪冰城 menu pages 2–9, deduplicated cup-size repetitions, and recorded source-count drift. | Public pages contain repeated items, sundae products, and changing item totals. | T2; 32 brands and 694 candidates. All candidates remain pending for specific-store availability. |
| 2026-10-16 | Added 95 drink-name candidates from 古茗 menu pages 1–6 and recorded the page coverage and duplicate-name caveat. | The public aggregator reports 117 items and repeats names across pages. | T2; 32 brands and 789 candidates. All candidates remain pending for specific-store availability. |
| 2026-10-15 | Added a record-flow action to create a missing drink under the already selected brand, keeping its brand association and allowing return to menu selection. | The user reported that selecting an existing brand did not support adding a new drink. | T1 |

## 8. Detail Pointers
- Format: v1 single-file
- iOS plan: docs/ios-development-plan.md；今日页性能修复与验收（T6.3/T6.4）：`docs/ios-today-performance-plan.md`
- History: recent changes retained here

## 9. Current Round
- Round: R1
- Frontier: T1, T2, T3, T5
- Granularity target: objective + output + acceptance + dependency
- Exit condition: each frontier task has a first result or explicit blocker
- Status: in progress

## 10. Technical Debt Queue
| ID | Discovered in | Debt | Why deferred | Trigger / target round | Priority | Status |
|---|---|---|---|---|---|---|
| D-001 | T5 | 6 pre-existing test failures; see tests/mvp.test.md. | Outside photo diagnostics. | Test maintenance | P2 | queued |
