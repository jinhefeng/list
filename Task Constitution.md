# Task Constitution

## 1. Mission
Build a local drink-and-meal logging mini program with a searchable, maintainable beverage catalog, starting with popular drinks in Hangzhou, Changzhou, and Shanghai, with clear source and verification status.

## 2. Success Criteria
- [ ] Menu data has a stable structure for brands, drinks, city/store availability, options, nutrition variants, sources, and verification dates.
- [ ] Menu editors can import and validate batches without changing mini-program code for every update.
- [ ] The mini program can use a bundled catalog and optionally refresh from a versioned HTTPS catalog while preserving user-created drinks.
- [ ] Users can search, add, and edit catalog drinks in the mini program, including brand, optional category, aliases, one per-100-ml nutrition baseline, and active state; exact size variants take priority and the baseline scales to the recorded size.
- [ ] For the agreed mainstream brands, every drink listed in the current public menu is captured with its source and check date; city/store availability remains a separate verified layer.
- [ ] A user can still record a drink immediately when a brand or new item is missing from the catalog, and that gap can be reviewed for catalog follow-up.
- [ ] Drink and meal records have separate entry points and appear together in one time-ordered history.
- [ ] Meal records save an address, store name, automatic time, and multiple named dishes with individual photos.
- [ ] Drink nutrition summaries exclude meal records; existing local drink records remain readable.

## 3. Task Tree
### T1 — Catalog structure, maintenance, and update foundation
- Status: 进行中
- Objective: Define the catalog contract, in-app maintenance flow, batch import, and safe mini-program update path.
- Acceptance: A template and importer produce a validated versioned catalog; users can search/add/edit catalog entries in the app; the app can opt into remote refresh and retain a local fallback and local overrides.
- Current result: Maintenance defaults to an empty list; search/filter or “展示全部饮品” opens 30-row batches. A global cup-type/capacity setting is shared by drink entry, Today, History, and Intake; record views hide capacity. Existing record sizes and complete nutrition snapshots remain intact. Custom-drink saves no longer add product-level cup mappings. The record form can add a missing drink directly to the selected existing brand and retain that brand association. Deletion requires confirmation and is blocked while any local record references the drink; local tombstones prevent configured remote refresh from restoring it. Brand/drink selectors share aligned label, value, and arrow columns; editing opens a scrollable modal over the unchanged list; the full-list button sits at the right of the catalog count card. Saving edits preserves active filters and the loaded batch size.

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
- Output: A meal entry page, map-confirmed addresses, drag-reorderable multi-dish records, mixed timeline rendering, and drink-only nutrition summaries.
- Acceptance: Users can save and edit a meal with a map-confirmed address, store name, time, and named dishes with individual photos; record cards show their map location last when available; one drink-style meal card shows every dish name, a fully visible first photo, clearly offset later photos exposed on the right, and a “共 X 张” badge; opening a meal photo shows all photos in that record with swipe navigation and tappable bottom thumbnails; meal and drink records sort together by time; the History page shows each date once for consecutive same-day records and supports multi-select record-type filters discovered from stored records, including unknown future type keys; new types are included by default and legacy records without a type remain drinks; nutrition counts remain drink-only; create-entry buttons appear on Today, not History or Intake; Today shows only the All Records link plus a small catalog icon, with no Intake link or fixed bottom navigation.
- Depends on: Existing local record storage, native map selection, and local photo persistence.
- Next action: Check date grouping, content scrolling, and navigation through Today links and native back; review the photo stack and viewer in WeChat Developer Tools, then verify map selection and dish ordering on device.

## 4. Current Focus
- Task: T2
- Parent path: T2
- Objective: Expand three-city drink candidates and separately reconcile current Taobao Flash Sale store menus.
- Next action: Continue reviewing remaining pages of partially covered public-menu brands, beginning with brands whose page counts are already known; record exclusions and source-count drift. Then check sample delivery menus in Hangzhou Shangcheng, Changzhou Tianning, and Shanghai Huangpu, recording the store, item, source, and check date. All public-menu names remain pending for store availability.

## 5. Decision Log
| Date | Decision | Rationale | Impact |
|---|---|---|---|
| 2026-10-14 | Start with Hangzhou, Changzhou, and Shanghai; keep platform/store coverage distinct from brand-level product identity. | Existing project scope names these three cities and menus vary by locality. | Catalog rows carry city/store provenance and verification status. |
| 2026-10-14 | Keep remote catalog refresh optional until an HTTPS endpoint is configured. | This repository has no cloud backend or approved catalog host configured. | The app remains usable from bundled/local data; deployment setup is documented. |
| 2026-10-15 | Use Taobao Flash Sale as the current platform source; do not treat the legacy Ele.me H5 page as current menu evidence. | Alibaba Group says Ele.me was fully rebranded as Taobao Flash Sale in December 2025; the legacy H5 page returned no usable sample-store menu and Taobao web navigation was blocked by site-safety policy. | City/store menu items stay pending until verified from an approved Taobao Flash Sale page. |
| 2026-10-15 | Use public menu pages to seed brand and drink names while keeping all entries pending. | The user asked to search publicly available menus; public menus are useful for discovery but do not show the current menu of the selected Taobao Flash Sale sample stores. | Each reference keeps its source URL and cannot be promoted to verified until checked against a local platform menu. |
| 2026-10-15 | Raise the menu acceptance bar from a starter list to every drink in current public menus for the agreed mainstream brands. | The user said missing a purchased drink could make users abandon the product; a starter list is insufficient. | T2 tracks source-page completeness separately from local Taobao Flash Sale store verification; the initial brand boundary is 2026 top-15 tea + 2026 top-15 coffee + Starbucks. |
| 2026-10-15 | Keep source-reported menu totals and reviewed pages in a separate coverage ledger. | Public aggregators have changing counts and some pages mix food or frozen desserts with drinks. | Current catalog counts remain candidates; none are treated as complete until page-by-page reconciliation. |
| 2026-10-15 | Keep drink and meal entry separate, but place both record types in one time-sorted history; meal photos belong to individual dishes. | The user wants separate input flows and a shared history. | Meal records are discriminated from drinks, and nutrition summaries continue to include drinks only. |
| 2026-10-15 | Show each meal as one drink-style history card with every dish photo and name. | The user chose the single-card option for meal history. | Home and history cards show all dishes together; dish order follows the entry form. |
| 2026-10-15 | Use a right-side exposed photo stack and an enlarged viewer with swipe navigation and tappable bottom thumbnails. | The user selected the right-side stack and requested switching among the photos in one meal. | Home, history, and meal editing open the same ordered photo viewer with a “共 X 张” badge on cards. |
| 2026-10-15 | Keep meal and drink creation buttons on Today; keep History and Intake focused on review. | The user asked to show drink locations on Today and remove create buttons from the other two tabs. | Drink and meal cards display map locations last when available; History and Intake have no add-entry buttons. |
| 2026-10-15 | Match Today drink-card information order to History and place location last. | The user reported inconsistent field order and excessive bottom whitespace hiding page content. | The three pages use compact bottom-safe-area spacing; fixed navigation was later removed. |
| 2026-10-15 | Remove the fixed bottom navigation and show a date only on the first record for each day. | The user asked to remove the bottom bar and reduce repeated dates in the History timeline. | Today links to All Records; catalog maintenance uses a header icon; secondary pages return through native back navigation. |
| 2026-10-15 | Keep only the All Records link on Today and represent catalog maintenance with an icon. | The user asked to remove the Intake link and replace the catalog text entry with a simple icon. | The catalog page remains reachable from the header icon. |
| 2026-10-15 | Build History record-type options dynamically from saved records; treat missing legacy types as drinks and auto-select newly observed types. | The user asked for type filtering that can grow with future record categories. | Known types have friendly labels; unknown types remain filterable by their stored key. |
| 2026-10-15 | Added an in-app beverage list page for searching, adding, and editing brand, category, aliases, and per-unit nutrition. | The user needs drink data to be maintainable in the Mini Program so missing items and nutrition can be added. | Unit nutrition is a labeled fallback; edits are stored locally and preserved during configured catalog refresh. |
| 2026-10-15 | Simplified catalog nutrition to one per-100-ml baseline, rendered 30 matches at a time, made category optional, and automatically saved record-created custom drinks into the local catalog. | The user asked to reduce nutrition entry to one value set and avoid a large default list; prior custom entries should be reusable. | Exact size variants still take priority; known legacy cup values can convert, ambiguous legacy values remain unchanged; local custom drinks appear in later record selection. |
| 2026-10-15 | Unified record nutrition input with the catalog's per-100-ml unit, saved per-record nutrition snapshots, required capacity for custom nutrition calculations when unknown, and displayed cup type plus capacity on Today. | The user reported missing cup labels and nutrition values that did not persist or match catalog units. | Historical snapshots remain stable when catalog data changes; custom drink baselines sync locally for later selection. |
| 2026-10-15 | Hid cup capacities from record and history views, added per-drink capacity configuration, made the catalog list empty until searched/filtered with 30-row view batches, simplified per-100-ml field labels, and added reference-guarded confirmed deletion. | The user approved the plan and specified hidden capacities and safe deletion. | Missing capacity preserves the baseline but skips serving conversion; referenced drinks are retained, and local deletion is retained through configured remote refresh. |
| 2026-10-15 | Moved cup names and capacities to one shared setting, added a button to expose the full catalog in 30-item batches, and separated card actions into a stable bottom row. | The user wants global cup sizes, explicit full-list access, and a clearer catalog card. | Existing record sizes and snapshots remain intact; all new record and summary calculations read the global mapping. |

## 6. Knowledge Context
- Constraints: Existing app changes are uncommitted; preserve them. No catalog backend or endpoint is configured. Records and photos stay on-device. Do not claim sample or pending menu items are verified.
- Dependencies: A future HTTPS host must be added to WeChat's request domain allowlist before remote refresh works in production.
- Relevant files: `data/catalog.js`, `utils/store.js`, `pages/record/record.js`, `README.md`.

## 7. Change History
| Date | Change | Reason | Affected tasks |
|---|---|---|---|
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
- Active branch detail: none
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
