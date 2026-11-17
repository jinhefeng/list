import CryptoKit
import Charts
import SwiftData
import SwiftUI
import UIKit
import ImageIO

private struct TimelineItem: Identifiable {
    let storedRecord: StoredJournalRecord
    let record: JournalRecord

    var id: UUID { record.id }
}

@MainActor
private final class TodayRecordCache {
    private var libraryGeneration: Int?
    private var recordIDs: [String] = []
    private var cachedItems: [TimelineItem] = []

    func items(
        for storedRecords: [StoredJournalRecord],
        libraryGeneration: Int,
        decode: () -> [TimelineItem]
    ) -> [TimelineItem] {
        let currentIDs = storedRecords.map(\.recordID)
        guard self.libraryGeneration != libraryGeneration || recordIDs != currentIDs else {
            return cachedItems
        }

        self.libraryGeneration = libraryGeneration
        recordIDs = currentIDs
        cachedItems = decode()
        return cachedItems
    }
}

@MainActor
private enum JournalBrandLogoCatalog {
    private static var cachedGeneration: Int?
    private static var cachedBrands: [String: MenuBrand] = [:]
    private static var loadingGeneration: Int?
    private static var loadingTask: Task<[String: MenuBrand], Never>?

    static func loadBrands() async -> [String: MenuBrand] {
        let generation = UserDefaults.standard.integer(forKey: MenuCatalogRepository.changeGenerationKey)
        if generation == cachedGeneration {
            return cachedBrands
        }

        let task: Task<[String: MenuBrand], Never>
        if loadingGeneration == generation, let loadingTask {
            task = loadingTask
        } else {
            task = Task.detached(priority: .utility) {
                Self.readBrands()
            }
            loadingGeneration = generation
            loadingTask = task
        }

        let brands = await task.value
        guard !Task.isCancelled else { return cachedBrands }
        guard generation == UserDefaults.standard.integer(forKey: MenuCatalogRepository.changeGenerationKey) else {
            return await loadBrands()
        }
        cachedGeneration = generation
        cachedBrands = brands
        if loadingGeneration == generation {
            loadingGeneration = nil
            loadingTask = nil
        }
        return brands
    }

    nonisolated private static func readBrands() -> [String: MenuBrand] {
        guard let url = Bundle.main.url(forResource: "catalog", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let bundledCatalog = try? MenuCatalog.decode(data) else {
            return [:]
        }

        let catalog = (try? MenuCatalogRepository().catalog(from: bundledCatalog)) ?? bundledCatalog
        return Dictionary(catalog.brands.map { ($0.id, $0) }, uniquingKeysWith: { _, latest in latest })
    }
}

struct GanfanMainTabView: View {
    private enum Tab: Hashable {
        case today
        case history
        case insights
        case more
    }

    @State private var selectedTab: Tab = .today
    @State private var today = Date.now
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        TabView(selection: $selectedTab) {
            JournalHomeView(today: today)
                .tabItem { Label("今日", systemImage: "house.fill") }
                .tag(Tab.today)

            NavigationStack {
                HistoryView()
            }
            .tabItem { Label("历史", systemImage: "clock.fill") }
            .tag(Tab.history)

            NavigationStack {
                InsightsView()
            }
            .tabItem { Label("摄入", systemImage: "chart.bar.fill") }
            .tag(Tab.insights)

            NavigationStack {
                MoreView()
            }
            .tabItem { Label("更多", systemImage: "ellipsis.circle.fill") }
            .tag(Tab.more)
        }
        .tint(GanfanPalette.forest)
        .toolbarBackground(GanfanPalette.card, for: .tabBar)
        .toolbarBackground(.visible, for: .tabBar)
        .task {
            while !Task.isCancelled {
                let calendar = Calendar.current
                let startOfToday = calendar.startOfDay(for: .now)
                guard let nextDay = calendar.date(byAdding: .day, value: 1, to: startOfToday) else { return }
                do {
                    try await Task.sleep(for: .seconds(max(1, nextDay.timeIntervalSinceNow)))
                } catch {
                    return
                }
                today = .now
            }
        }
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active else { return }
            today = .now
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.significantTimeChangeNotification)) { _ in
            today = .now
        }
        .onReceive(NotificationCenter.default.publisher(for: .NSSystemTimeZoneDidChange)) { _ in
            today = .now
        }
    }
}

struct JournalHomeView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage(BackupChangeTracker.pendingKey) private var hasPendingLibraryChanges = false
    @AppStorage(BackupChangeTracker.generationKey) private var libraryChangeGeneration = 0
    @AppStorage(MenuCatalogRepository.changeGenerationKey) private var catalogChangeGeneration = 0
    @Query(sort: \StoredJournalRecord.consumedAt, order: .reverse)
    private var storedRecords: [StoredJournalRecord]
    @Query private var todayStoredRecords: [StoredJournalRecord]

    @StateObject private var backupWorkflow = BackupWorkflowModel.shared
    @State private var isCreatingDrink = false
    @State private var isCreatingMeal = false
    @State private var successfulSaveCount = 0
    @State private var brandCatalog: [String: MenuBrand] = [:]
    @State private var todayRecordCache = TodayRecordCache()

    private let today: Date

    init(today: Date) {
        self.today = today
        let calendar = Calendar.current
        let start = calendar.startOfDay(for: today)
        let end = calendar.date(byAdding: .day, value: 1, to: start) ?? start.addingTimeInterval(86_400)
        let predicate = #Predicate<StoredJournalRecord> { record in
            record.consumedAt >= start && record.consumedAt < end
        }
        _todayStoredRecords = Query(
            filter: predicate,
            sort: [
                SortDescriptor(\.consumedAt, order: .forward),
                SortDescriptor(\.recordID, order: .forward)
            ]
        )
    }

    private var todayItems: [TimelineItem] {
        todayRecordCache.items(
            for: todayStoredRecords,
            libraryGeneration: libraryChangeGeneration,
            decode: decodeTodayItems
        )
    }

    private func decodeTodayItems() -> [TimelineItem] {
        todayStoredRecords.compactMap { storedRecord -> TimelineItem? in
            guard let record = try? storedRecord.decodeRecord() else { return nil }
            return TimelineItem(storedRecord: storedRecord, record: record)
        }
    }

    private var unreadableRecordCount: Int {
        todayStoredRecords.count - todayItems.count
    }

    private var pendingBackupCount: Int {
        storedRecords.filter(\.needsBackup).count
    }

    private var dailyNutritionSummary: DailyNutritionSummary {
        .summarize(todayItems.map(\.record), on: today)
    }

    private var todayMealNutritionSummary: MealNutritionSummary {
        MealNutritionSummary(meals: todayItems.compactMap { item in
            guard case .meal(let meal) = item.record else { return nil }
            return meal
        })
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: GanfanSpacing.large) {
                    todayIntro
                    captureActions
                    todayRecordsHeading
                    unreadableRecordsNotice
                    todayRecordResults
                }
                .padding(.horizontal, GanfanSpacing.pageHorizontal)
                .padding(.vertical, 12)
                .frame(maxWidth: 680)
                .frame(maxWidth: .infinity)
            }
            .background(GanfanPalette.canvas)
            .navigationTitle("")
            .toolbar(.hidden, for: .navigationBar)
            .tint(GanfanPalette.forest)
            .background(GanfanPalette.canvas.ignoresSafeArea())
            .task {
                backupWorkflow.restoreSavedFolderAccess()
                backupWorkflow.backupIfNeeded(storedRecords: storedRecords, context: modelContext)
            }
            .task(id: catalogChangeGeneration) {
                brandCatalog = await JournalBrandLogoCatalog.loadBrands()
            }
            .onChange(of: libraryChangeGeneration) { _, _ in
                backupWorkflow.backupIfNeeded(storedRecords: storedRecords, context: modelContext)
            }
            .onChange(of: scenePhase) { _, phase in
                guard phase == .active else { return }
                backupWorkflow.restoreSavedFolderAccess()
                backupWorkflow.backupIfNeeded(storedRecords: storedRecords, context: modelContext)
            }
            .sheet(isPresented: $isCreatingDrink) {
                NavigationStack {
                    DrinkRecordForm(onSave: { successfulSaveCount += 1 })
                }
            }
            .sheet(isPresented: $isCreatingMeal) {
                NavigationStack {
                    MealRecordForm(onSave: { successfulSaveCount += 1 })
                }
            }
            .sensoryFeedback(.success, trigger: successfulSaveCount)
        }
    }

    private var todayIntro: some View {
        VStack(alignment: .leading, spacing: GanfanSpacing.mediumSmall) {
            todayHeader
            TodayNutritionSummary(
                drinkSummary: dailyNutritionSummary,
                mealSummary: todayMealNutritionSummary
            )
        }
    }

    private var todayHeader: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("今天")
                .font(.largeTitle.weight(.bold))
                .foregroundStyle(GanfanPalette.ink)
            dateLabel
            if let notice = backupHomeNotice {
                backupLink(for: notice)
                    .padding(.top, 4)
            }
        }
    }

    private var dateLabel: some View {
        Text("\(JournalRecordListFormatting.date(.now)) · \(JournalRecordListFormatting.weekday(.now))")
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func backupLink(for notice: HomeBackupNotice) -> some View {
        NavigationLink {
            BackupSettingsView()
        } label: {
            Label(notice.title, systemImage: notice.symbol)
                .font(.caption.weight(.semibold))
                .foregroundStyle(notice.isWarning ? Color.orange : GanfanPalette.forest)
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .background(
                    notice.isWarning ? Color.orange.opacity(0.10) : GanfanPalette.paleLeaf,
                    in: Capsule()
                )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("备份状态：\(notice.title)，点按打开备份与恢复设置")
    }

    private var isBackupPending: Bool {
        pendingBackupCount > 0 || hasPendingLibraryChanges
    }

    private var backupHomeNotice: HomeBackupNotice? {
        if backupWorkflow.folderBookmark.isEmpty { return .notConfigured }
        if let failure = backupWorkflow.homeFailure {
            switch failure {
            case .directoryUnavailable: return .directoryUnavailable
            case .backupFailed: return .backupFailed
            }
        }
        guard !backupWorkflow.isWorking, isBackupPending else { return nil }
        return .pending
    }

    @ViewBuilder
    private var captureActions: some View {
        if dynamicTypeSize.isAccessibilitySize {
            VStack(spacing: 12) {
                captureDrinkButton
                captureMealButton
            }
        } else {
            HStack(spacing: 12) {
                captureDrinkButton
                captureMealButton
            }
        }
    }

    private var captureDrinkButton: some View {
        HomeCaptureButton(title: "喝一杯", symbol: "cup.and.saucer.fill", isPrimary: true) {
            isCreatingDrink = true
        }
    }

    private var captureMealButton: some View {
        HomeCaptureButton(title: "吃一顿", symbol: "fork.knife", isPrimary: false) {
            isCreatingMeal = true
        }
    }

    private var todayRecordsHeading: some View {
        HStack(alignment: .firstTextBaseline) {
            Text("今天的记录")
                .font(.title3.weight(.semibold))
                .foregroundStyle(GanfanPalette.ink)
            Spacer()
            Text("\(todayItems.count) 条")
                .font(.footnote.monospacedDigit())
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var unreadableRecordsNotice: some View {
        if unreadableRecordCount > 0 {
            Label(
                "今日有 \(unreadableRecordCount) 条记录无法读取；原始数据仍保留在资料库中。",
                systemImage: "exclamationmark.triangle"
            )
            .font(.footnote)
            .foregroundStyle(.orange)
        }
    }

    private var todayRecordResults: some View {
        let items = todayItems
        return Group {
            if items.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("今天还没有记录")
                        .font(.headline)
                        .foregroundStyle(GanfanPalette.ink)
                    Text("记下一杯饮品或一餐，之后都能在这里找回。")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 12)
            } else {
                LazyVStack(spacing: 0) {
                    ForEach(Array(items.enumerated()), id: \.element.id) { entry in
                        JournalRecordCardRow(
                            item: entry.element,
                            style: .today,
                            brandCatalog: brandCatalog
                        )
                            .padding(.vertical, 12)
                            .transition(.asymmetric(
                                insertion: .move(edge: .top).combined(with: .opacity),
                                removal: .opacity
                            ))

                        if entry.offset < items.count - 1 {
                            Rectangle()
                                .fill(Color(uiColor: .separator).opacity(0.55))
                                .frame(height: 0.5)
                                .padding(.leading, 100)
                        }
                    }
                }
            }
        }
        .animation(recordListAnimation, value: items.map(\.id))
    }

    private var recordListAnimation: Animation? {
        reduceMotion ? nil : Animation.easeInOut(duration: 0.2)
    }
}

private struct JournalTimelineRow: View {
    let record: JournalRecord
    let brandCatalog: [String: MenuBrand]

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                switch record {
                case .drink(let drink):
                    Text(drink.drinkName)
                        .font(.headline)
                    Spacer(minLength: 8)
                    HStack(spacing: 5) {
                        GanfanBrandLogoIcon(
                            assetName: brandCatalog[drink.brandID]?.logoAssetName,
                            symbol: brandCatalog[drink.brandID]?.logoSymbol,
                            imageID: brandCatalog[drink.brandID]?.logoImageID,
                            dimension: 16
                        )
                        Text(drink.brandName)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                case .meal(let meal):
                    Label(meal.storeName.isEmpty ? "用餐记录" : meal.storeName, systemImage: "fork.knife")
                        .font(.headline)
                }
            }

            HStack(alignment: .top) {
                switch record {
                case .drink(let drink):
                    let serving = DrinkServingSelection(
                        temperature: drink.temperature,
                        ice: drink.ice,
                        legacyServingOption: drink.temperature == nil && drink.ice == nil ? drink.servingOption : nil
                    )
                    Text([drink.cupType, serving.displayLabel, drink.sweetness].filter { !$0.isEmpty }.joined(separator: " · "))
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                case .meal(let meal):
                    Text(meal.dishes.map(\.name).joined(separator: "、"))
                        .lineLimit(2)
                }
                Spacer(minLength: 8)
                Text(record.consumedAt.formatted(date: .abbreviated, time: .shortened))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .font(.subheadline)
            .foregroundStyle(.secondary)
        }
        .padding(.vertical, 5)
        .foregroundStyle(GanfanPalette.ink)
    }
}

private enum JournalRecordRowStyle: Equatable {
    case today
    case timeline

    var photoSize: CGFloat {
        switch self {
        case .today: 88
        case .timeline: 88
        }
    }

    var photoLayerOffset: CGFloat { 12 }
    var showsTimeInCard: Bool { self == .today }
}

private struct JournalPhotoEntry: Identifiable {
    let asset: PhotoAsset
    let label: String

    var id: UUID { asset.id }
}

private enum JournalRecordOverlayRoute: Identifiable {
    case detail(id: UUID, storedRecord: StoredJournalRecord)
    case photos(id: UUID, assets: [PhotoAsset], labels: [String], initialIndex: Int)

    var id: UUID {
        switch self {
        case .detail(let id, _), .photos(let id, _, _, _): id
        }
    }

    static func record(_ storedRecord: StoredJournalRecord) -> Self {
        .detail(id: UUID(), storedRecord: storedRecord)
    }

    static func photoViewer(assets: [PhotoAsset], labels: [String], initialIndex: Int = 0) -> Self {
        .photos(id: UUID(), assets: assets, labels: labels, initialIndex: initialIndex)
    }
}

private struct JournalNutritionMetric: Identifiable {
    let symbol: String
    let label: String
    let value: String

    var id: String { label }
}

private struct MealNutritionSummary {
    struct Total {
        let value: Double?
        let knownDishCount: Int
        let totalDishCount: Int
        let isApproximate: Bool
    }

    let mealCount: Int
    let energyKcal: Total
    let proteinGrams: Total
    let fatGrams: Total

    init(meals: [MealRecord]) {
        let dishes = meals.flatMap(\.dishes)
        let snapshots = dishes.map { dish in
            dish.nutrition ?? RoughNutritionEstimator.dish(name: dish.name)
        }

        mealCount = meals.count
        energyKcal = Self.total(snapshots, keyPath: \.energyKcal, sourceKey: "energyKcal")
        proteinGrams = Self.total(snapshots, keyPath: \.proteinGrams, sourceKey: "proteinGrams")
        fatGrams = Self.total(snapshots, keyPath: \.fatGrams, sourceKey: "fatGrams")
    }

    private static func total(
        _ snapshots: [NutritionSnapshot],
        keyPath: KeyPath<NutritionSnapshot, Double?>,
        sourceKey: String
    ) -> Total {
        var values: [Double] = []
        var isApproximate = false
        for snapshot in snapshots {
            guard let value = snapshot[keyPath: keyPath], value.isFinite, value >= 0 else { continue }
            values.append(value)
            if snapshot.confidence == .estimated || snapshot.confidence == .rough
                || snapshot.metricSources[sourceKey] == "rough" {
                isApproximate = true
            }
        }

        return Total(
            value: values.isEmpty ? nil : values.reduce(0, +),
            knownDishCount: values.count,
            totalDishCount: snapshots.count,
            isApproximate: isApproximate
        )
    }
}

private struct JournalRecordCardRow: View {
    let item: TimelineItem
    let style: JournalRecordRowStyle
    let brandCatalog: [String: MenuBrand]

    @State private var activeOverlay: JournalRecordOverlayRoute?

    private var photoEntries: [JournalPhotoEntry] {
        switch item.record {
        case .drink(let drink):
            guard let photo = drink.photo else { return [] }
            return [JournalPhotoEntry(asset: photo, label: drink.drinkName)]
        case .meal(let meal):
            return meal.dishes.compactMap { dish in
                dish.photo.map { JournalPhotoEntry(asset: $0, label: dish.name) }
            }
        }
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            photoColumn
            detailAction
        }
        .sheet(item: $activeOverlay) { route in
            JournalRecordOverlaySheet(route: route)
        }
    }

    @ViewBuilder
    private var detailAction: some View {
        Button {
            activeOverlay = .record(item.storedRecord)
        } label: {
            recordDetails
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("查看\(recordTitle)详情")
        .accessibilityHint("从底部打开记录详情")
    }

    @ViewBuilder
    private var photoColumn: some View {
        switch item.record {
        case .drink:
            if photoEntries.isEmpty {
                photoPlaceholder("杯")
            } else {
                photoButton(at: 0)
            }
        case .meal:
            if photoEntries.isEmpty {
                photoPlaceholder("菜")
            } else {
                let visibleCount = min(photoEntries.count, 4)
                ZStack(alignment: .topLeading) {
                    ForEach(0..<visibleCount, id: \.self) { index in
                        photoButton(at: index)
                            .offset(y: CGFloat(index) * style.photoLayerOffset)
                            .zIndex(Double(visibleCount - index))
                    }
                }
                .frame(width: style.photoSize, height: photoStackHeight, alignment: .topLeading)
            }
        }
    }

    private var photoStackHeight: CGFloat {
        let visibleCount = min(photoEntries.count, 4)
        return style.photoSize + CGFloat(max(0, visibleCount - 1)) * style.photoLayerOffset
    }

    private func photoButton(at index: Int) -> some View {
        let entry = photoEntries[index]
        let showsCount = isMeal && index == 0 && photoEntries.count > 1

        return Button {
            activeOverlay = .photoViewer(
                assets: photoEntries.map(\.asset),
                labels: photoEntries.map(\.label),
                initialIndex: index
            )
        } label: {
            JournalPhotoThumbnail(asset: entry.asset, dimension: style.photoSize)
                .overlay {
                    RoundedRectangle(cornerRadius: GanfanShape.photo, style: .continuous)
                        .stroke(.white, lineWidth: 1.5)
                }
                .overlay(alignment: .bottomTrailing) {
                    if showsCount {
                        Text("共 \(photoEntries.count) 张")
                            .font(.caption.weight(.medium))
                            .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
                            .foregroundStyle(.white)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 4)
                            .background(.black.opacity(0.7), in: Capsule())
                            .padding(5)
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: GanfanShape.photo, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(entry.label.isEmpty ? "查看照片" : "查看\(entry.label)照片")
        .accessibilityHint(isMeal && photoEntries.count > 1 ? "共 \(photoEntries.count) 张，可左右滑动查看" : "")
    }

    private func photoPlaceholder(_ title: String) -> some View {
        RoundedRectangle(cornerRadius: GanfanShape.photo, style: .continuous)
            .fill(GanfanPalette.paleLeaf)
            .overlay {
                Text(title)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(GanfanPalette.leaf)
            }
            .frame(width: style.photoSize, height: style.photoSize)
            .accessibilityHidden(true)
    }

    @ViewBuilder
    private var recordDetails: some View {
        VStack(alignment: .leading, spacing: style == .today ? 4 : 6) {
            switch item.record {
            case .drink(let drink):
                drinkDetails(drink)
            case .meal(let meal):
                mealDetails(meal)
            }
        }
    }

    private func drinkDetails(_ drink: DrinkRecord) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(drink.drinkName)
                    .font(.headline)
                    .foregroundStyle(GanfanPalette.forest)
                    .lineLimit(1)
                Spacer(minLength: 4)
                if style.showsTimeInCard {
                    Text(JournalRecordListFormatting.time(drink.consumedAt))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize()
                }
            }

            let nutritionMetrics = Self.nutritionMetrics(drink.nutrition)
            if !nutritionMetrics.isEmpty {
                nutritionSummary(nutritionMetrics)
            }

            HStack(alignment: .center, spacing: 6) {
                GanfanBrandLogoIcon(
                    assetName: brandCatalog[drink.brandID]?.logoAssetName,
                    symbol: brandCatalog[drink.brandID]?.logoSymbol,
                    imageID: brandCatalog[drink.brandID]?.logoImageID,
                    dimension: 16
                )
                Text(drink.brandName.isEmpty ? "自定义饮品" : drink.brandName)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .fixedSize(horizontal: false, vertical: true)

            let servingLabel = Self.servingLabel(for: drink)
            let missingServingLabel = style == .today ? "冰度未记" : "未选择"
            let cupTypeLabel = drink.cupType.isEmpty ? "杯型未记录" : drink.cupType
            let sweetnessLabel = drink.sweetness.isEmpty ? "甜度未记" : drink.sweetness
            Text("\(cupTypeLabel) · \(servingLabel.isEmpty ? missingServingLabel : servingLabel) · \(sweetnessLabel)")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)

            if let location = Self.drinkLocationLabel(drink, style: style) {
                locationLine(location)
            }
        }
    }

    private func nutritionSummary(_ metrics: [JournalNutritionMetric]) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: style == .timeline ? 8 : 12) {
            ForEach(metrics) { metric in
                HStack(alignment: .firstTextBaseline, spacing: 3) {
                    Image(systemName: metric.symbol)
                        .font(.system(size: style == .timeline ? 9 : 10, weight: .semibold))
                    if style != .timeline {
                        Text(metric.label)
                            .lineLimit(1)
                    }
                    Text(metric.value)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
                .font(style == .timeline ? .caption2 : .caption)
                .foregroundStyle(GanfanPalette.leaf)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("\(metric.label) \(metric.value)")
            }
        }
    }

    private func mealDetails(_ meal: MealRecord) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(meal.storeName.isEmpty ? "用餐记录" : meal.storeName)
                    .font(.headline)
                    .foregroundStyle(GanfanPalette.forest)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 4)

                if style.showsTimeInCard {
                    Text(JournalRecordListFormatting.time(meal.consumedAt))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize()
                }
            }

            let nutrition = MealNutritionSummary(meals: [meal])
            let metrics = Self.mealNutritionMetrics(nutrition)
            if !metrics.isEmpty {
                nutritionSummary(metrics)
            }

            let dishNames = meal.dishes.map(\.name).filter { !$0.isEmpty }.joined(separator: "、")
            if !dishNames.isEmpty {
                Text(dishNames)
                    .font(style.showsTimeInCard ? .footnote : .caption2)
                    .foregroundStyle(.secondary)
                    .lineSpacing(style == .timeline ? 2 : 0)
                    .lineLimit(style == .timeline ? 4 : nil)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if !meal.locationAddress.isEmpty {
                locationLine(meal.locationAddress)
            }
        }
    }

    private func locationLine(_ label: String) -> some View {
        HStack(spacing: 5) {
            Image(systemName: "mappin.and.ellipse")
                .font(.system(size: style == .timeline ? 10 : 11, weight: .medium))
                .foregroundStyle(GanfanPalette.leaf)
            Text(label)
                .font(style == .timeline ? .caption2 : .caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.tail)
        }
        .accessibilityElement(children: .combine)
    }

    private var isMeal: Bool {
        if case .meal = item.record { return true }
        return false
    }

    private var recordTitle: String {
        switch item.record {
        case .drink(let drink): drink.drinkName
        case .meal(let meal): meal.storeName.isEmpty ? "用餐记录" : meal.storeName
        }
    }

    private static func drinkLocationLabel(_ drink: DrinkRecord, style: JournalRecordRowStyle) -> String? {
        let location = drink.locationName.trimmingCharacters(in: .whitespacesAndNewlines)
        let address = drink.locationAddress.trimmingCharacters(in: .whitespacesAndNewlines)
        let coordinatePattern = #"^\s*-?\d+(?:\.\d+)?\s*,\s*-?\d+(?:\.\d+)?\s*$"#
        if location.range(of: coordinatePattern, options: .regularExpression) != nil {
            return style == .today && !address.isEmpty ? address : nil
        }
        if !location.isEmpty { return location }
        return style == .today && !address.isEmpty ? address : nil
    }

    private static func servingLabel(for drink: DrinkRecord) -> String {
        let legacyOption = drink.servingOption.trimmingCharacters(in: .whitespacesAndNewlines)
        if !legacyOption.isEmpty {
            return legacyOption == "热" ? "热饮" : legacyOption
        }
        return DrinkServingSelection(temperature: drink.temperature, ice: drink.ice).displayLabel
    }

    private static func nutritionMetrics(_ nutrition: NutritionSnapshot?) -> [JournalNutritionMetric] {
        guard let nutrition else { return [] }
        let isEstimated: Bool
        switch nutrition.confidence {
        case .estimated, .rough: isEstimated = true
        case .official, .unavailable: isEstimated = false
        }

        var metrics: [JournalNutritionMetric] = []
        if let energy = nutrition.energyKcal {
            let step = isEstimated ? 10.0 : 1.0
            metrics.append(JournalNutritionMetric(
                symbol: "flame.fill",
                label: "能量",
                value: "\(compactNumber(rounded(energy, to: step))) kcal"
            ))
        }
        if let sugar = nutrition.sugarGrams {
            let step = isEstimated ? 5.0 : 0.1
            metrics.append(JournalNutritionMetric(
                symbol: "cube.fill",
                label: "糖",
                value: "\(compactNumber(rounded(sugar, to: step)))g"
            ))
        }
        if let caffeine = nutrition.caffeineMilligrams {
            let step = isEstimated ? 10.0 : 1.0
            metrics.append(JournalNutritionMetric(
                symbol: "cup.and.saucer.fill",
                label: "咖啡因",
                value: "\(compactNumber(rounded(caffeine, to: step)))mg"
            ))
        }
        return metrics
    }

    private static func mealNutritionMetrics(_ summary: MealNutritionSummary) -> [JournalNutritionMetric] {
        [
            mealMetric(summary.energyKcal, symbol: "flame.fill", label: "能量", unit: "kcal", roughStep: 10),
            mealMetric(summary.proteinGrams, symbol: "p.circle.fill", label: "蛋白质", unit: "g", roughStep: 1),
            mealMetric(summary.fatGrams, symbol: "drop.fill", label: "脂肪", unit: "g", roughStep: 1)
        ].compactMap { $0 }
    }

    private static func mealMetric(
        _ total: MealNutritionSummary.Total,
        symbol: String,
        label: String,
        unit: String,
        roughStep: Double
    ) -> JournalNutritionMetric? {
        guard let value = total.value else { return nil }
        let step = total.isApproximate ? roughStep : 0.1
        return JournalNutritionMetric(
            symbol: symbol,
            label: label,
            value: "\(compactNumber(rounded(value, to: step))) \(unit)"
        )
    }

    private static func rounded(_ value: Double, to step: Double) -> Double {
        (value / step).rounded(.toNearestOrAwayFromZero) * step
    }

    private static func compactNumber(_ value: Double) -> String {
        let nearestInteger = value.rounded(.toNearestOrAwayFromZero)
        if abs(value - nearestInteger) < 0.0001 {
            return String(Int(nearestInteger))
        }
        return String(format: "%.1f", locale: Locale(identifier: "en_US_POSIX"), value)
    }
}

private struct JournalPhotoThumbnail: View {
    let asset: PhotoAsset
    let dimension: CGFloat

    @State private var thumbnailData: Data?

    var body: some View {
        Group {
            if let thumbnailData, let image = UIImage(data: thumbnailData) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                Rectangle()
                    .fill(GanfanPalette.paleLeaf)
                    .overlay {
                        Image(systemName: "photo")
                            .font(.caption)
                            .foregroundStyle(GanfanPalette.leaf.opacity(0.7))
                    }
            }
        }
        .frame(width: dimension, height: dimension)
        .clipped()
        .task(id: asset.id) {
            let currentAsset = asset
            let photoStore = AppStoragePaths.photoStore
            let maxPixelSize = Int(dimension * 3)
            let data = await Task.detached(priority: .utility) { () -> Data? in
                guard let sourceData = try? photoStore.load(currentAsset) else { return nil }
                return JournalPhotoThumbnailLoader.thumbnailData(from: sourceData, maxPixelSize: maxPixelSize)
            }.value
            guard !Task.isCancelled else { return }
            thumbnailData = data
        }
    }
}

private enum JournalPhotoThumbnailLoader {
    static func thumbnailData(from data: Data, maxPixelSize: Int) -> Data? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
            kCGImageSourceShouldCacheImmediately: true
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }

        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(output, "public.jpeg" as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(destination, image, [kCGImageDestinationLossyCompressionQuality: 0.82] as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return output as Data
    }
}

private struct JournalHistoryTimelineEntry: View {
    let item: TimelineItem
    let dateLabel: String?
    let isLast: Bool
    let brandCatalog: [String: MenuBrand]

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            VStack(alignment: .trailing, spacing: 4) {
                if let dateLabel {
                    Text(dateLabel)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(GanfanPalette.ink)
                }
                Text(JournalRecordListFormatting.time(item.record.consumedAt))
                    .font(.footnote.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            .frame(width: 58, alignment: .trailing)

            Color.clear
                .frame(width: 24)

            JournalRecordCardRow(
                item: item,
                style: .timeline,
                brandCatalog: brandCatalog
            )
        }
        .padding(.vertical, 12)
        .overlay(alignment: .topLeading) {
            GeometryReader { geometry in
                let railX: CGFloat = 70
                if !isLast {
                    Rectangle()
                        .fill(Color(uiColor: .separator).opacity(0.8))
                        .frame(width: 1, height: max(0, geometry.size.height - 17))
                        .position(x: railX, y: 17 + max(0, geometry.size.height - 17) / 2)
                }
                Circle()
                    .fill(GanfanPalette.forest)
                    .frame(width: 8, height: 8)
                    .position(x: railX, y: 17)
            }
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        }
    }
}

private enum JournalRecordListFormatting {
    static func precedes(_ lhs: TimelineItem, _ rhs: TimelineItem) -> Bool {
        precedes(
            lhs.record.consumedAt,
            id: lhs.id.uuidString,
            rhs.record.consumedAt,
            id: rhs.id.uuidString
        )
    }

    static func precedes(_ lhsDate: Date, id lhsID: String, _ rhsDate: Date, id rhsID: String) -> Bool {
        let lhsDay = Calendar.current.startOfDay(for: lhsDate)
        let rhsDay = Calendar.current.startOfDay(for: rhsDate)
        if lhsDay != rhsDay { return lhsDay > rhsDay }
        if lhsDate != rhsDate { return lhsDate < rhsDate }
        return lhsID < rhsID
    }

    static func time(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_GB")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = .current
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: date)
    }

    static func date(_ date: Date) -> String {
        let components = Calendar.current.dateComponents([.month, .day], from: date)
        guard let month = components.month, let day = components.day else { return "" }
        return "\(month)月\(day)日"
    }

    static func weekday(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.calendar = Calendar.current
        formatter.dateFormat = "EEEE"
        return formatter.string(from: date)
    }
}

private struct DailyNutritionHero: View {
    let summary: DailyNutritionSummary
    let title: String

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 5) {
                Text(title)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(GanfanPalette.ink)
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text("\(summary.drinkCount)")
                        .font(.largeTitle.weight(.bold).monospacedDigit())
                        .foregroundStyle(GanfanPalette.ink)
                    Text("杯饮品")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }

            Rectangle()
                .fill(Color(uiColor: .separator).opacity(0.55))
                .frame(height: 0.5)

            HStack(alignment: .top, spacing: 10) {
                NutritionMetricColumn(title: "能量 · kcal", value: summary.energyKcal.value, unit: "")
                NutritionMetricColumn(title: "糖 · g", value: summary.sugarGrams.value, unit: "")
                NutritionMetricColumn(title: "咖啡因 · mg", value: summary.caffeineMilligrams.value, unit: "")
            }

            Text(qualityText)
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
    }

    private var qualityText: String {
        guard summary.drinkCount > 0 else { return "录入饮品后显示营养汇总" }
        return "官方 \(summary.officialCount) · 估算 \(summary.estimatedCount) · 粗估 \(summary.roughCount) · 暂无 \(summary.unavailableCount)"
    }
}

private enum HomeBackupNotice {
    case notConfigured
    case pending
    case directoryUnavailable
    case backupFailed

    var title: String {
        switch self {
        case .notConfigured: "未设置备份"
        case .pending: "待备份"
        case .directoryUnavailable: "目录不可访问"
        case .backupFailed: "备份异常"
        }
    }

    var symbol: String {
        switch self {
        case .notConfigured: "icloud.slash"
        case .pending: "clock.arrow.circlepath"
        case .directoryUnavailable, .backupFailed: "exclamationmark.triangle.fill"
        }
    }

    var isWarning: Bool {
        switch self {
        case .pending: false
        default: true
        }
    }
}

private struct DrinkNutritionMetric: Identifiable {
    let title: String
    let symbol: String
    let value: Double?
    let unit: String
    var isApproximate = false
    var roundingStep: Double? = nil

    var id: String { title }

    var formattedValue: String {
        guard let value, value.isFinite, value >= 0 else { return "—" }
        let roundedValue: Double
        if let roundingStep, roundingStep > 0 {
            roundedValue = (value / roundingStep).rounded(.toNearestOrAwayFromZero) * roundingStep
        } else {
            roundedValue = value
        }
        let formatted = roundedValue.formatted(.number.precision(.fractionLength(0...1)))
        return isApproximate ? "约 \(formatted)" : formatted
    }

    var spokenValue: String {
        guard value != nil else { return "暂无数据" }
        return "\(formattedValue) \(unit)"
    }
}

private struct TodayNutritionSummary: View {
    let drinkSummary: DailyNutritionSummary
    let mealSummary: MealNutritionSummary

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private var shouldRoundCombinedEnergy: Bool {
        drinkSummary.energyKcal.confidence == .estimated || drinkSummary.energyKcal.confidence == .rough
            || mealSummary.energyKcal.isApproximate
    }

    private var combinedEnergy: Double? {
        let values = [drinkSummary.energyKcal.value, mealSummary.energyKcal.value].compactMap { $0 }
        guard !values.isEmpty else { return nil }
        return values.reduce(0, +)
    }

    private var combinedEnergyMetric: DrinkNutritionMetric {
        DrinkNutritionMetric(
            title: "总能量",
            symbol: "flame.fill",
            value: combinedEnergy,
            unit: "kcal",
            isApproximate: true,
            roundingStep: shouldRoundCombinedEnergy ? 10 : nil
        )
    }

    private var metrics: [DrinkNutritionMetric] {
        [
            combinedMetric(
                title: "蛋白质",
                symbol: "p.circle.fill",
                drinkValue: drinkSummary.proteinGrams.value,
                mealValue: mealSummary.proteinGrams.value,
                unit: "g"
            ),
            combinedMetric(
                title: "脂肪",
                symbol: "drop.fill",
                drinkValue: drinkSummary.fatGrams.value,
                mealValue: mealSummary.fatGrams.value,
                unit: "g"
            ),
            DrinkNutritionMetric(
                title: "糖",
                symbol: "cube.fill",
                value: drinkSummary.sugarGrams.value,
                unit: "g"
            ),
            DrinkNutritionMetric(
                title: "咖啡因",
                symbol: "cup.and.saucer.fill",
                value: drinkSummary.caffeineMilligrams.value,
                unit: "mg"
            )
        ]
    }

    private func combinedMetric(
        title: String,
        symbol: String,
        drinkValue: Double?,
        mealValue: Double?,
        unit: String
    ) -> DrinkNutritionMetric {
        let values = [drinkValue, mealValue].compactMap { $0 }
        return DrinkNutritionMetric(
            title: title,
            symbol: symbol,
            value: values.isEmpty ? nil : values.reduce(0, +),
            unit: unit
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: GanfanSpacing.mediumSmall) {
            HStack {
                Label("今日摄入", systemImage: "fork.knife")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(GanfanPalette.forest)
                Spacer(minLength: 8)
                Text("\(drinkSummary.drinkCount) 杯 · \(mealSummary.mealCount) 餐")
                    .font(.subheadline.weight(.semibold).monospacedDigit())
                    .foregroundStyle(GanfanPalette.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }

            if drinkSummary.drinkCount == 0 && mealSummary.mealCount == 0 {
                Text("记录饮品或用餐后显示摄入汇总")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: GanfanSpacing.mediumSmall) {
                    energySummary(accessibilityLayout: true)
                    ForEach(metrics) { metric in
                        metricRow(metric)
                    }
                }
            } else {
                VStack(alignment: .leading, spacing: GanfanSpacing.mediumSmall) {
                    energySummary(accessibilityLayout: false)
                    HStack(alignment: .top, spacing: GanfanSpacing.small) {
                        ForEach(metrics) { metric in
                            compactMetricColumn(metric)
                        }
                    }
                }
            }

            if hasIncompleteNutritionData {
                Text("部分营养项暂无数据，合计仅包含已有值")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            GanfanPalette.paleLeaf.opacity(0.42),
            in: RoundedRectangle(cornerRadius: GanfanShape.surface, style: .continuous)
        )
        .accessibilityElement(children: .contain)
    }

    private var hasIncompleteNutritionData: Bool {
        drinkSummary.energyKcal.knownRecordCount < drinkSummary.drinkCount
            || mealSummary.energyKcal.knownDishCount < mealSummary.energyKcal.totalDishCount
            || drinkSummary.proteinGrams.knownRecordCount < drinkSummary.drinkCount
            || mealSummary.proteinGrams.knownDishCount < mealSummary.proteinGrams.totalDishCount
            || drinkSummary.fatGrams.knownRecordCount < drinkSummary.drinkCount
            || mealSummary.fatGrams.knownDishCount < mealSummary.fatGrams.totalDishCount
            || drinkSummary.sugarGrams.knownRecordCount < drinkSummary.drinkCount
            || drinkSummary.caffeineMilligrams.knownRecordCount < drinkSummary.drinkCount
    }

    private func energySummary(accessibilityLayout: Bool) -> some View {
        let drinkValue = componentValue(
            drinkSummary.energyKcal.value,
            shouldRound: drinkSummary.energyKcal.confidence == .estimated || drinkSummary.energyKcal.confidence == .rough
        )
        let mealValue = componentValue(
            mealSummary.energyKcal.value,
            shouldRound: mealSummary.energyKcal.isApproximate
        )

        return Group {
            if accessibilityLayout {
                VStack(alignment: .leading, spacing: 4) {
                    metricColumn(combinedEnergyMetric)
                    Text("饮品 \(drinkValue) · 用餐 \(mealValue)")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel("总能量，\(combinedEnergyMetric.spokenValue)，饮品 \(drinkValue)，用餐 \(mealValue)")
            } else {
                HStack(alignment: .center) {
                    VStack(alignment: .leading, spacing: 4) {
                        metricLabel(
                            combinedEnergyMetric,
                            textFont: .caption,
                            iconFont: .caption2.weight(.semibold)
                        )
                        HStack(alignment: .firstTextBaseline, spacing: 3) {
                            Text(combinedEnergyMetric.formattedValue)
                                .font(.title3.weight(.semibold).monospacedDigit())
                                .foregroundStyle(GanfanPalette.ink)
                                .lineLimit(1)
                                .minimumScaleFactor(0.75)
                            Text(combinedEnergyMetric.unit)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("\(combinedEnergyMetric.title)，\(combinedEnergyMetric.spokenValue)")
                    Spacer(minLength: 12)
                    VStack(alignment: .trailing, spacing: 3) {
                        Text("饮品 \(drinkValue)")
                        Text("用餐 \(mealValue)")
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .accessibilityElement(children: .combine)
                }
            }
        }
    }

    private func componentValue(_ value: Double?, shouldRound: Bool) -> String {
        guard let value, value.isFinite, value >= 0 else { return "— kcal" }
        let roundedValue = shouldRound
            ? (value / 10).rounded(.toNearestOrAwayFromZero) * 10
            : value
        let formatted = roundedValue.formatted(.number.precision(.fractionLength(0...1)))
        return "\(formatted) kcal"
    }

    private func metricColumn(_ metric: DrinkNutritionMetric) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            metricLabel(metric, textFont: .caption, iconFont: .caption2.weight(.semibold))

            metricAmount(metric, font: .title3.weight(.semibold))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(metric.title)，\(metric.spokenValue)")
    }

    private func compactMetricColumn(_ metric: DrinkNutritionMetric) -> some View {
        HStack(alignment: .top, spacing: 4) {
            Image(systemName: metric.symbol)
                .font(.system(size: 9, weight: .semibold))

            VStack(alignment: .leading, spacing: 3) {
                Text(metric.title)
                    .font(.caption2)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)

                metricAmount(metric, font: .footnote.weight(.semibold))
            }
        }
        .foregroundStyle(.secondary)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(metric.title)，\(metric.spokenValue)")
    }

    private func metricLabel(
        _ metric: DrinkNutritionMetric,
        textFont: Font,
        iconFont: Font
    ) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 4) {
            Image(systemName: metric.symbol)
                .font(iconFont)
            Text(metric.title)
                .font(textFont)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .foregroundStyle(.secondary)
    }

    private func metricRow(_ metric: DrinkNutritionMetric) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Label(metric.title, systemImage: metric.symbol)
                .font(.body)
                .foregroundStyle(.secondary)
            Spacer(minLength: 12)
            metricAmount(metric, font: .body.weight(.semibold))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(metric.title)，\(metric.spokenValue)")
    }

    private func metricAmount(
        _ metric: DrinkNutritionMetric,
        font: Font
    ) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 3) {
            Text(metric.formattedValue)
                .font(font.monospacedDigit())
                .foregroundStyle(GanfanPalette.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
            Text(metric.unit)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }
}

private struct HomeCaptureButton: View {
    let title: String
    let symbol: String
    let isPrimary: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 9) {
                Image(systemName: symbol)
                    .font(.body.weight(.medium))
                Text(title)
                    .font(.headline)
                Spacer(minLength: 4)
            }
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 14)
            .padding(.vertical, 14)
            .contentShape(RoundedRectangle(cornerRadius: GanfanShape.control, style: .continuous))
        }
        .buttonStyle(HomeCaptureButtonStyle(isPrimary: isPrimary))
        .accessibilityLabel(title)
        .accessibilityHint("打开\(title)记录表单")
    }
}

private struct HomeCaptureButtonStyle: ButtonStyle {
    let isPrimary: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(isPrimary ? Color.white : GanfanPalette.forest)
            .background(
                isPrimary ? GanfanPalette.forestSurface : GanfanPalette.card,
                in: RoundedRectangle(cornerRadius: GanfanShape.control, style: .continuous)
            )
            .overlay {
                if !isPrimary {
                    RoundedRectangle(cornerRadius: GanfanShape.control, style: .continuous)
                        .stroke(Color(uiColor: .separator).opacity(0.45), lineWidth: 1)
                }
            }
            .opacity(configuration.isPressed ? 0.78 : 1)
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.985 : 1)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.16), value: configuration.isPressed)
    }
}

private struct NutritionMetricColumn: View {
    let title: String
    let value: Double?
    let unit: String

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(valueText)
                .font(.title3.weight(.semibold).monospacedDigit())
                .foregroundStyle(GanfanPalette.ink)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var valueText: String {
        guard let value else { return "—" }
        let rounded = value.rounded(.toNearestOrAwayFromZero)
        let text = value == rounded ? String(Int(rounded)) : String(format: "%.1f", value)
        return unit.isEmpty ? text : "\(text)\(unit)"
    }
}

private struct HistoryView: View {
    @AppStorage(MenuCatalogRepository.changeGenerationKey) private var catalogChangeGeneration = 0
    @Query(sort: \StoredJournalRecord.consumedAt, order: .reverse)
    private var storedRecords: [StoredJournalRecord]
    @State private var startDate = Calendar.current.date(byAdding: .day, value: -29, to: .now) ?? .now
    @State private var endDate = Date.now
    @State private var selectedTypes: Set<String> = ["drink", "meal"]
    @State private var searchText = ""
    @State private var isShowingFilters = false
    @State private var brandCatalog: [String: MenuBrand] = [:]

    private var filterSummary: String {
        let formatter = DateIntervalFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        let range = formatter.string(from: startDate, to: endDate)
        let types = [
            selectedTypes.contains("drink") ? "饮品" : nil,
            selectedTypes.contains("meal") ? "用餐" : nil
        ].compactMap { $0 }.joined(separator: "、")
        return types.isEmpty ? "\(range) · 未选择记录类型" : "\(range) · \(types)"
    }

    private var visibleItems: [TimelineItem] {
        let start = Calendar.current.startOfDay(for: startDate)
        let end = Calendar.current.date(byAdding: .day, value: 1, to: Calendar.current.startOfDay(for: endDate)) ?? endDate
        let items = storedRecords.compactMap { storedRecord -> TimelineItem? in
            guard let record = try? storedRecord.decodeRecord(),
                  record.consumedAt >= start,
                  record.consumedAt < end else { return nil }
            let type = Self.typeKey(record)
            guard selectedTypes.contains(type) else { return nil }
            guard Self.matchesSearch(record, query: searchText) else { return nil }
            return TimelineItem(storedRecord: storedRecord, record: record)
        }
        return items.sorted(by: JournalRecordListFormatting.precedes)
    }

    private var unreadableRecords: [StoredJournalRecord] {
        storedRecords.filter { storedRecord in
            storedRecord.consumedAt >= Calendar.current.startOfDay(for: startDate)
                && storedRecord.consumedAt < (Calendar.current.date(byAdding: .day, value: 1, to: Calendar.current.startOfDay(for: endDate)) ?? endDate)
                && (try? storedRecord.decodeRecord()) == nil
        }.sorted {
            JournalRecordListFormatting.precedes(
                $0.consumedAt,
                id: $0.recordID,
                $1.consumedAt,
                id: $1.recordID
            )
        }
    }

    var body: some View {
        List {
            Section {
                HStack {
                    Text(filterSummary)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .listRowInsets(EdgeInsets(top: 0, leading: 12, bottom: 0, trailing: 12))
                .listRowSeparator(.hidden)
                .listRowBackground(Color.clear)
            }

            if !unreadableRecords.isEmpty {
                Section("无法读取的记录") {
                    ForEach(unreadableRecords) { item in
                        Label("\(item.recordType) · \(item.consumedAt.formatted(date: .abbreviated, time: .shortened))", systemImage: "exclamationmark.triangle")
                            .font(.footnote)
                            .foregroundStyle(.orange)
                    }
                }
            }

            if visibleItems.isEmpty {
                ContentUnavailableView("没有匹配的记录", systemImage: "calendar", description: Text("调整日期范围或记录类型后再试。"))
                    .listRowBackground(Color.clear)
            } else {
                ForEach(Array(visibleItems.enumerated()), id: \.element.id) { entry in
                    let index = entry.offset
                    let item = entry.element
                    let previousItem = index > 0 ? visibleItems[index - 1] : nil
                    let startsNewDay = previousItem.map {
                        !Calendar.current.isDate($0.record.consumedAt, inSameDayAs: item.record.consumedAt)
                    } ?? true

                    JournalHistoryTimelineEntry(
                        item: item,
                        dateLabel: startsNewDay ? JournalRecordListFormatting.date(item.record.consumedAt) : nil,
                        isLast: index == visibleItems.count - 1,
                        brandCatalog: brandCatalog
                    )
                    .listRowInsets(EdgeInsets(top: 0, leading: 12, bottom: 0, trailing: 12))
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
                }
            }
        }
        .listSectionSpacing(.compact)
        .scrollContentBackground(.hidden)
        .task(id: catalogChangeGeneration) {
            brandCatalog = await JournalBrandLogoCatalog.loadBrands()
        }
        .background(GanfanPalette.canvas)
        .tint(GanfanPalette.forest)
        .navigationTitle("全部记录")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
        .searchable(text: $searchText, prompt: "搜索饮品、餐厅或菜品")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    isShowingFilters = true
                } label: {
                    Image(systemName: "slider.horizontal.3")
                }
                .accessibilityLabel("筛选记录")
            }
        }
        .sheet(isPresented: $isShowingFilters) {
            NavigationStack {
                HistoryFiltersView(
                    startDate: $startDate,
                    endDate: $endDate,
                    selectedTypes: $selectedTypes
                )
            }
        }
    }

    private func typeBinding(_ key: String) -> Binding<Bool> {
        Binding(
            get: { selectedTypes.contains(key) },
            set: { selected in
                if selected { selectedTypes.insert(key) } else { selectedTypes.remove(key) }
            }
        )
    }

    private static func typeKey(_ record: JournalRecord) -> String {
        switch record {
        case .drink: "drink"
        case .meal: "meal"
        }
    }

    private static func matchesSearch(_ record: JournalRecord, query: String) -> Bool {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !needle.isEmpty else { return true }
        switch record {
        case .drink(let drink):
            return [drink.brandName, drink.drinkName, drink.locationName, drink.locationAddress, drink.notes]
                .contains { $0.localizedCaseInsensitiveContains(needle) }
        case .meal(let meal):
            return [meal.storeName, meal.locationAddress, meal.notes].contains { $0.localizedCaseInsensitiveContains(needle) }
                || meal.dishes.contains { $0.name.localizedCaseInsensitiveContains(needle) }
        }
    }
}

private struct HistoryFiltersView: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var startDate: Date
    @Binding var endDate: Date
    @Binding var selectedTypes: Set<String>

    var body: some View {
        Form {
            Section("快捷范围") {
                HStack(spacing: 8) {
                    rangeButton("近 7 天", days: 7)
                    rangeButton("近 30 天", days: 30)
                }
            }

            Section("自定义日期") {
                DatePicker("开始", selection: $startDate, in: ...endDate, displayedComponents: .date)
                DatePicker("结束", selection: $endDate, in: startDate..., displayedComponents: .date)
            }

            Section("记录类型") {
                Toggle("饮品", isOn: typeBinding("drink"))
                Toggle("用餐", isOn: typeBinding("meal"))
            }
        }
        .scrollContentBackground(.hidden)
        .background(GanfanPalette.canvas)
        .tint(GanfanPalette.forest)
        .navigationTitle("筛选记录")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("重置") {
                    startDate = Calendar.current.date(byAdding: .day, value: -29, to: .now) ?? .now
                    endDate = .now
                    selectedTypes = ["drink", "meal"]
                }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("完成") { dismiss() }
            }
        }
    }

    private func rangeButton(_ title: String, days: Int) -> some View {
        Button(title) {
            endDate = .now
            startDate = Calendar.current.date(byAdding: .day, value: -(days - 1), to: .now) ?? .now
        }
        .buttonStyle(.bordered)
        .tint(GanfanPalette.forest)
    }

    private func typeBinding(_ key: String) -> Binding<Bool> {
        Binding(
            get: { selectedTypes.contains(key) },
            set: { selected in
                if selected { selectedTypes.insert(key) } else { selectedTypes.remove(key) }
            }
        )
    }
}

private enum IntakeTrendRange: Int, CaseIterable, Identifiable, Hashable {
    case week = 7
    case month = 30
    case quarter = 90

    var id: Int { rawValue }
    var title: String { "近 \(rawValue) 天" }
    var axisStride: Int {
        switch self {
        case .week: 1
        case .month: 7
        case .quarter: 14
        }
    }
}

private enum IntakeTrendGraphStyle: Equatable {
    case line
    case area
    case bars
}

private enum IntakeTrendMetric: String, CaseIterable, Identifiable, Hashable {
    case energy
    case caffeine
    case sugar
    case fat
    case protein
    case carbohydrate
    case drinkVolume

    var id: String { rawValue }

    var title: String {
        switch self {
        case .energy: "热量"
        case .protein: "蛋白质"
        case .fat: "脂肪"
        case .carbohydrate: "碳水化合物"
        case .sugar: "糖"
        case .drinkVolume: "水分（饮品）"
        case .caffeine: "咖啡因"
        }
    }

    var unit: String {
        switch self {
        case .energy: "kcal / 天"
        case .protein, .fat, .carbohydrate, .sugar: "g / 天"
        case .drinkVolume: "ml / 天"
        case .caffeine: "mg / 天"
        }
    }

    var symbol: String {
        switch self {
        case .energy: "flame.fill"
        case .protein: "figure.strengthtraining.traditional"
        case .fat: "drop.fill"
        case .carbohydrate: "leaf.fill"
        case .sugar: "cube.fill"
        case .drinkVolume: "waterbottle.fill"
        case .caffeine: "cup.and.saucer.fill"
        }
    }

    var tint: Color {
        switch self {
        case .energy: Color(uiColor: .systemOrange)
        case .protein: GanfanPalette.forest
        case .fat: Color(uiColor: .systemPurple)
        case .carbohydrate: Color(uiColor: .systemBlue)
        case .sugar: Color(uiColor: .systemPink)
        case .drinkVolume: Color(uiColor: .systemTeal)
        case .caffeine: Color(uiColor: .systemBrown)
        }
    }

    var isDrinkOnly: Bool { self == .drinkVolume || self == .caffeine }

    var graphStyle: IntakeTrendGraphStyle {
        switch self {
        case .energy: .area
        case .caffeine, .drinkVolume: .bars
        case .sugar, .fat, .protein, .carbohydrate: .line
        }
    }

    var nutritionSourceKey: String? {
        switch self {
        case .energy: "energyKcal"
        case .protein: "proteinGrams"
        case .fat: "fatGrams"
        case .carbohydrate: "carbohydrateGrams"
        case .sugar: "sugarGrams"
        case .drinkVolume: nil
        case .caffeine: "caffeineMilligrams"
        }
    }

    func value(in nutrition: NutritionSnapshot) -> Double? {
        switch self {
        case .energy: nutrition.energyKcal
        case .protein: nutrition.proteinGrams
        case .fat: nutrition.fatGrams
        case .carbohydrate: nutrition.carbohydrateGrams
        case .sugar: nutrition.sugarGrams
        case .drinkVolume: nil
        case .caffeine: nutrition.caffeineMilligrams
        }
    }

    func formatted(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(0)))
    }

    func axisLabel(_ value: Double) -> String {
        guard abs(value) >= 1_000 else { return formatted(value) }
        let compact = (value / 1_000).formatted(.number.precision(.fractionLength(0...1)))
        return "\(compact)k"
    }
}

private struct IntakeMetricValue {
    let value: Double?
    let knownCount: Int
    let totalCount: Int
    let containsEstimate: Bool
    let latestRecordAt: Date?

    static let empty = IntakeMetricValue(
        value: nil,
        knownCount: 0,
        totalCount: 0,
        containsEstimate: false,
        latestRecordAt: nil
    )
}

private struct IntakeMetricAccumulator {
    private(set) var sum = 0.0
    private(set) var knownCount = 0
    private(set) var totalCount = 0
    private(set) var containsEstimate = false
    private(set) var latestRecordAt: Date?

    mutating func add(_ value: Double?, isEstimated: Bool, recordedAt: Date) {
        totalCount += 1
        guard let value, value.isFinite, value >= 0 else { return }
        sum += value
        knownCount += 1
        containsEstimate = containsEstimate || isEstimated
        latestRecordAt = max(latestRecordAt ?? recordedAt, recordedAt)
    }

    var total: IntakeMetricValue {
        IntakeMetricValue(
            value: knownCount == 0 ? nil : sum,
            knownCount: knownCount,
            totalCount: totalCount,
            containsEstimate: containsEstimate,
            latestRecordAt: latestRecordAt
        )
    }
}

private struct IntakeDailySummary: Identifiable {
    let date: Date
    let recordCount: Int
    let drinkCount: Int
    let metrics: [IntakeTrendMetric: IntakeMetricValue]

    var id: Date { date }

    func value(for metric: IntakeTrendMetric) -> IntakeMetricValue {
        metrics[metric] ?? .empty
    }
}

private struct IntakeDailyAccumulator {
    private(set) var recordCount = 0
    private(set) var drinkCount = 0
    private var metrics = Dictionary(
        uniqueKeysWithValues: IntakeTrendMetric.allCases.map { ($0, IntakeMetricAccumulator()) }
    )

    mutating func add(_ drink: DrinkRecord) {
        recordCount += 1
        drinkCount += 1
        let snapshot = drink.nutrition
        for metric in [IntakeTrendMetric.energy, .protein, .fat, .carbohydrate, .sugar, .caffeine] {
            let value = snapshot.flatMap { metric.value(in: $0) }
            metrics[metric, default: IntakeMetricAccumulator()].add(
                value,
                isEstimated: Self.isEstimated(snapshot, metric: metric),
                recordedAt: drink.consumedAt
            )
        }
        metrics[.drinkVolume, default: IntakeMetricAccumulator()].add(
            drink.sizeML.map(Double.init),
            isEstimated: false,
            recordedAt: drink.consumedAt
        )
    }

    mutating func add(_ meal: MealRecord) {
        recordCount += 1
        for dish in meal.dishes {
            let isFallbackEstimate = dish.nutrition == nil
            let snapshot = dish.nutrition ?? RoughNutritionEstimator.dish(name: dish.name)
            for metric in [.energy, .protein, .fat, .carbohydrate, .sugar] as [IntakeTrendMetric] {
                metrics[metric, default: IntakeMetricAccumulator()].add(
                    metric.value(in: snapshot),
                    isEstimated: isFallbackEstimate || Self.isEstimated(snapshot, metric: metric),
                    recordedAt: meal.consumedAt
                )
            }
        }
    }

    func summary(on date: Date) -> IntakeDailySummary {
        IntakeDailySummary(
            date: date,
            recordCount: recordCount,
            drinkCount: drinkCount,
            metrics: metrics.mapValues { $0.total }
        )
    }

    private static func isEstimated(_ snapshot: NutritionSnapshot?, metric: IntakeTrendMetric) -> Bool {
        guard let snapshot else { return false }
        if snapshot.confidence != .official { return true }
        guard let sourceKey = metric.nutritionSourceKey else { return false }
        guard let source = snapshot.metricSources[sourceKey] else { return false }
        return ["rough", "estimated"].contains(source)
    }
}

private struct IntakeTrendPoint: Identifiable {
    let date: Date
    let value: Double?
    let knownCount: Int
    let totalCount: Int
    let containsEstimate: Bool
    let latestRecordAt: Date?
    let recordCount: Int
    let drinkCount: Int
    let segment: Int

    var id: Date { date }
}

private struct IntakeTrendCard: View {
    let metric: IntakeTrendMetric
    let points: [IntakeTrendPoint]
    let range: IntakeTrendRange
    @Binding var selectedDate: Date
    @Binding var expandedMetric: IntakeTrendMetric?
    @Binding var hasSelectedChartDate: Bool
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var isExpanded: Bool { expandedMetric == metric }

    private var validPoints: [IntakeTrendPoint] {
        points.filter { $0.value != nil }
    }

    private var averageValue: Double? {
        let values = validPoints.compactMap(\.value)
        guard !values.isEmpty else { return nil }
        return values.reduce(0, +) / Double(values.count)
    }

    private var averageLabel: String {
        guard let averageValue else { return "—" }
        let prefix = validPoints.contains(where: \.containsEstimate) ? "约 " : ""
        return "\(prefix)\(metric.formatted(averageValue)) \(unitShortLabel)"
    }

    private var graphStyle: IntakeTrendGraphStyle {
        metric.graphStyle
    }

    private func adaptiveBarWidth(plotWidth: CGFloat, includesYAxis: Bool) -> CGFloat {
        let yAxisAllowance: CGFloat = includesYAxis ? 44 : 0
        let usableWidth = max(plotWidth - yAxisAllowance, 1)
        let slotWidth = usableWidth / CGFloat(max(points.count, 1))
        let minimumWidth: CGFloat = includesYAxis ? 2.5 : 2
        let maximumWidth: CGFloat = includesYAxis ? 28 : 16
        return min(max(slotWidth * 0.72, minimumWidth), maximumWidth)
    }

    private var chartDomain: ClosedRange<Date> {
        (points.first?.date ?? .now)...(points.last?.date ?? .now)
    }

    private var latestPoint: IntakeTrendPoint? {
        points.last { $0.value != nil }
    }

    private var selectedPoint: IntakeTrendPoint? {
        points.first { Calendar.current.isDate($0.date, inSameDayAs: selectedDate) }
    }

    private var latestRecordLabel: String {
        guard let date = latestPoint?.latestRecordAt else { return "暂无数据" }
        if Calendar.current.isDateInToday(date) {
            return date.formatted(date: .omitted, time: .shortened)
        }
        return date.formatted(.dateTime.month(.abbreviated).day().hour().minute())
    }

    private var latestValueLabel: String {
        guard let latestPoint, let value = latestPoint.value else { return "—" }
        return "\(latestPoint.containsEstimate ? "约 " : "")\(metric.formatted(value))"
    }

    private var selectedValueLabel: String {
        guard let selectedPoint else { return "暂无数据" }
        guard let value = selectedPoint.value else {
            if selectedPoint.recordCount == 0 { return "暂无记录" }
            if metric.isDrinkOnly && selectedPoint.drinkCount == 0 { return "暂无饮品记录" }
            return metric == .drinkVolume ? "容量未记录" : "暂无营养数据"
        }
        return "\(selectedPoint.containsEstimate ? "约 " : "")\(metric.formatted(value))"
    }

    private var unitShortLabel: String {
        switch metric {
        case .energy: "kcal"
        case .protein, .fat, .carbohydrate, .sugar: "g"
        case .drinkVolume: "ml"
        case .caffeine: "mg"
        }
    }

    private var selectedDateLabel: String {
        (selectedPoint?.date ?? selectedDate)
            .formatted(.dateTime.month(.abbreviated).day().weekday(.abbreviated))
    }

    private var selectedDataNote: String {
        guard let selectedPoint else { return "选择某一天查看数据" }
        guard selectedPoint.value != nil else {
            return selectedPoint.recordCount == 0 ? "这一天没有记录" : "缺失数据不会按 0 计入"
        }
        if selectedPoint.knownCount < selectedPoint.totalCount {
            return "部分数据 · \(selectedPoint.knownCount)/\(selectedPoint.totalCount) 项有值"
        }
        return selectedPoint.containsEstimate ? "包含估算值" : "当日合计"
    }

    var body: some View {
        ZStack(alignment: .top) {
            frontFace
                .opacity(isExpanded ? 0 : 1)
                .rotation3DEffect(.degrees(isExpanded ? -180 : 0), axis: (x: 0, y: 1, z: 0), perspective: 0.72)
                .frame(height: isExpanded ? 0 : nil, alignment: .top)
                .allowsHitTesting(!isExpanded)
                .accessibilityHidden(isExpanded)

            expandedFace
                .opacity(isExpanded ? 1 : 0)
                .rotation3DEffect(.degrees(isExpanded ? 0 : 180), axis: (x: 0, y: 1, z: 0), perspective: 0.72)
                .frame(height: isExpanded ? nil : 0, alignment: .top)
                .allowsHitTesting(isExpanded)
                .accessibilityHidden(!isExpanded)
        }
        .frame(maxWidth: .infinity)
        .animation(reduceMotion ? nil : .spring(response: 0.52, dampingFraction: 0.88), value: isExpanded)
    }

    private var frontFace: some View {
        Button(action: expand) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 8) {
                    Image(systemName: metric.symbol)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(metric.tint)
                    Text(metric.title)
                        .font(.headline.weight(.semibold))
                        .foregroundStyle(metric.tint)
                    Spacer(minLength: 4)
                    Text(latestRecordLabel)
                        .font(.caption.weight(.medium).monospacedDigit())
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.tertiary)
                }

                if dynamicTypeSize.isAccessibilitySize {
                    VStack(alignment: .leading, spacing: 10) {
                        previewValue
                        miniTrendChart
                            .frame(maxWidth: .infinity)
                            .frame(height: 84)
                    }
                } else {
                    HStack(alignment: .bottom, spacing: 10) {
                        previewValue
                            .frame(maxWidth: .infinity, alignment: .leading)
                        miniTrendChart
                            .frame(width: 142, height: 82)
                    }
                }

                averageSummary
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(GanfanPalette.card, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(metric.title)，\(latestValueLabel) \(unitShortLabel)，最新记录 \(latestRecordLabel)")
        .accessibilityHint("轻点翻转查看大图并选择日期")
    }

    private var previewValue: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(latestValueLabel)
                    .font(.system(.largeTitle, design: .rounded).weight(.semibold).monospacedDigit())
                    .foregroundStyle(GanfanPalette.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
                Text(unitShortLabel)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.secondary)
            }
            Text(latestPoint?.date.formatted(.dateTime.month(.abbreviated).day().weekday(.abbreviated)) ?? "当前范围暂无数据")
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
    }

    private var averageSummary: some View {
        HStack(spacing: 7) {
            Text("日均摄入")
                .foregroundStyle(.secondary)
            Text(averageLabel)
                .fontWeight(.semibold)
                .foregroundStyle(GanfanPalette.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.78)
            Spacer(minLength: 2)
            Text("按 \(validPoints.count) 天计算")
                .font(.caption2.monospacedDigit())
                .foregroundStyle(.secondary)
                .padding(.horizontal, 7)
                .padding(.vertical, 4)
                .background(GanfanPalette.canvas, in: Capsule())
        }
        .font(.caption)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("日均摄入，\(averageLabel)，按 \(validPoints.count) 天计算")
    }

    private var miniTrendChart: some View {
        GeometryReader { geometry in
            let columnWidth = adaptiveBarWidth(plotWidth: geometry.size.width, includesYAxis: false)
            Chart {
                if graphStyle == .bars {
                    ForEach(validPoints) { point in
                        BarMark(
                            x: .value("日期", point.date),
                            y: .value(metric.title, point.value ?? 0),
                            width: .fixed(columnWidth)
                        )
                        .foregroundStyle(metric.tint.opacity(point.date == latestPoint?.date ? 1 : 0.58))
                    }
                } else {
                    ForEach(validPoints) { point in
                        if graphStyle == .area {
                            AreaMark(
                                x: .value("日期", point.date),
                                yStart: .value("基线", 0.0),
                                yEnd: .value(metric.title, point.value ?? 0),
                                series: .value("连续数据段", point.segment)
                            )
                            .interpolationMethod(.linear)
                            .foregroundStyle(metric.tint.opacity(0.12))
                        }

                        LineMark(
                            x: .value("日期", point.date),
                            y: .value(metric.title, point.value ?? 0),
                            series: .value("连续数据段", point.segment)
                        )
                        .interpolationMethod(.linear)
                        .lineStyle(StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))
                        .foregroundStyle(metric.tint.opacity(point.date == latestPoint?.date ? 0.95 : 0.46))

                        if point.date == latestPoint?.date {
                            PointMark(
                                x: .value("日期", point.date),
                                y: .value(metric.title, point.value ?? 0)
                            )
                            .symbolSize(42)
                            .foregroundStyle(metric.tint)
                        }
                    }
                }
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
            .chartXScale(domain: chartDomain)
            .chartYScale(domain: .automatic(includesZero: true))
            .chartXAxis(.hidden)
            .chartYAxis(.hidden)
            .chartLegend(.hidden)
            .accessibilityHidden(true)
        }
    }

    private var expandedFace: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: metric.symbol)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(metric.tint)
                Text(metric.title)
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(metric.tint)
                Spacer(minLength: 4)
                Text(latestRecordLabel)
                    .font(.caption.weight(.medium).monospacedDigit())
                    .foregroundStyle(.secondary)
                Button(action: collapse) {
                    Image(systemName: "chevron.down")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: 32, height: 32)
                        .background(GanfanPalette.canvas, in: Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("收起\(metric.title)趋势")
            }

            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(selectedValueLabel)
                    .font(.title2.weight(.bold).monospacedDigit())
                    .foregroundStyle(GanfanPalette.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                Text(unitShortLabel)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
                Spacer(minLength: 4)
                Text(selectedDateLabel)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            averageSummary

            largeTrendChart
                .frame(height: 190)
                .accessibilityLabel("\(metric.title)每日摄入趋势")
                .accessibilityHint("轻点选择日期；松开后保留所选日期")

            HStack(spacing: 5) {
                Circle().fill(metric.tint).frame(width: 6, height: 6)
                Text(selectedDataNote)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Spacer()
                Text(metric.isDrinkOnly ? "饮品 · \(metric.unit)" : "用餐 + 饮品 · \(metric.unit)")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(GanfanPalette.card, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .accessibilityElement(children: .contain)
    }

    private var largeTrendChart: some View {
        GeometryReader { chartGeometry in
            let columnWidth = adaptiveBarWidth(plotWidth: chartGeometry.size.width, includesYAxis: true)
            Chart {
                if graphStyle == .bars {
                    ForEach(validPoints) { point in
                        BarMark(
                            x: .value("日期", point.date),
                            y: .value(metric.title, point.value ?? 0),
                            width: .fixed(columnWidth)
                        )
                        .foregroundStyle(metric.tint.opacity(selectedPoint?.date == point.date ? 1 : 0.58))
                    }
                } else {
                    ForEach(validPoints) { point in
                        if graphStyle == .area {
                            AreaMark(
                                x: .value("日期", point.date),
                                yStart: .value("基线", 0.0),
                                yEnd: .value(metric.title, point.value ?? 0),
                                series: .value("连续数据段", point.segment)
                            )
                            .interpolationMethod(.linear)
                            .foregroundStyle(metric.tint.opacity(0.1))
                        }

                        LineMark(
                            x: .value("日期", point.date),
                            y: .value(metric.title, point.value ?? 0),
                            series: .value("连续数据段", point.segment)
                        )
                        .interpolationMethod(.linear)
                        .lineStyle(StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))
                        .foregroundStyle(metric.tint)

                        if range == .week || selectedPoint?.date == point.date {
                            PointMark(
                                x: .value("日期", point.date),
                                y: .value(metric.title, point.value ?? 0)
                            )
                            .symbolSize(selectedPoint?.date == point.date ? 64 : 30)
                            .foregroundStyle(metric.tint)
                        }
                    }
                }

                RuleMark(x: .value("所选日期", selectedDate))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
                    .foregroundStyle(Color.secondary.opacity(0.45))
            }
            .frame(width: chartGeometry.size.width, height: chartGeometry.size.height)
            .chartXScale(domain: chartDomain)
            .chartYScale(domain: .automatic(includesZero: true))
            .chartXAxis {
                AxisMarks(values: .stride(by: .day, count: range.axisStride)) { value in
                    AxisTick(length: 3)
                    AxisValueLabel {
                        if let date = value.as(Date.self) {
                            Text(range == .week
                                 ? date.formatted(.dateTime.weekday(.abbreviated))
                                 : date.formatted(.dateTime.month(.abbreviated).day()))
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .chartYAxis {
                AxisMarks(position: .leading, values: .automatic(desiredCount: 4)) { value in
                    AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5, dash: [2, 3]))
                        .foregroundStyle(Color.secondary.opacity(0.22))
                    AxisTick(length: 3)
                    AxisValueLabel {
                        if let amount = value.as(Double.self) {
                            Text(metric.axisLabel(amount))
                                .font(.caption2.monospacedDigit())
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .chartOverlay { proxy in
                GeometryReader { overlayGeometry in
                    if let plotFrameAnchor = proxy.plotFrame {
                        let plotFrame = overlayGeometry[plotFrameAnchor]
                        Rectangle()
                            .fill(.clear)
                            .contentShape(Rectangle())
                            .frame(width: plotFrame.width, height: plotFrame.height)
                            .position(x: plotFrame.midX, y: plotFrame.midY)
                            // Tap-only selection lets the parent scroll view own vertical drags.
                            .simultaneousGesture(
                                SpatialTapGesture()
                                    .onEnded { value in
                                        guard let date = proxy.value(atX: value.location.x, as: Date.self) else { return }
                                        selectNearestPoint(to: date)
                                    }
                            )
                    }
                }
            }
        }
    }

    private func selectNearestPoint(to date: Date) {
        guard let nearestPoint = points.min(by: {
            abs($0.date.timeIntervalSince(date)) < abs($1.date.timeIntervalSince(date))
        }) else { return }
        selectedDate = nearestPoint.date
        hasSelectedChartDate = true
    }

    private func expand() {
        let updates = {
            expandedMetric = metric
            if !hasSelectedChartDate, let latestPoint {
                selectedDate = latestPoint.date
                hasSelectedChartDate = true
            }
        }
        if reduceMotion {
            updates()
        } else {
            withAnimation(.spring(response: 0.52, dampingFraction: 0.88)) {
                updates()
            }
        }
    }

    private func collapse() {
        if reduceMotion {
            expandedMetric = nil
        } else {
            withAnimation(.spring(response: 0.52, dampingFraction: 0.88)) {
                expandedMetric = nil
            }
        }
    }
}

private struct InsightsView: View {
    @Query(sort: \StoredJournalRecord.consumedAt, order: .reverse)
    private var storedRecords: [StoredJournalRecord]
    @State private var range: IntakeTrendRange = .week
    @State private var selectedDate = Calendar.current.startOfDay(for: .now)
    @State private var expandedMetric: IntakeTrendMetric?
    @State private var hasSelectedChartDate = false

    private let calendar = Calendar.current

    private var dateRange: (start: Date, end: Date) {
        let today = calendar.startOfDay(for: .now)
        let start = calendar.date(byAdding: .day, value: -(range.rawValue - 1), to: today) ?? today
        return (start, today)
    }

    private var dailySummaries: [IntakeDailySummary] {
        let bounds = dateRange
        let endExclusive = calendar.date(byAdding: .day, value: 1, to: bounds.end) ?? bounds.end.addingTimeInterval(86_400)
        var accumulators: [Date: IntakeDailyAccumulator] = [:]

        for storedRecord in storedRecords where storedRecord.consumedAt >= bounds.start && storedRecord.consumedAt < endExclusive {
            guard let record = try? storedRecord.decodeRecord() else { continue }
            let day = calendar.startOfDay(for: record.consumedAt)
            switch record {
            case .drink(let drink):
                accumulators[day, default: IntakeDailyAccumulator()].add(drink)
            case .meal(let meal):
                accumulators[day, default: IntakeDailyAccumulator()].add(meal)
            }
        }

        return (0..<range.rawValue).compactMap { offset in
            guard let date = calendar.date(byAdding: .day, value: offset, to: bounds.start) else { return nil }
            return (accumulators[date] ?? IntakeDailyAccumulator()).summary(on: date)
        }
    }

    private var visibleMetrics: [IntakeTrendMetric] {
        IntakeTrendMetric.allCases.filter { metric in
            dailySummaries.contains { $0.value(for: metric).value != nil }
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 5) {
                    Text("按天查看营养摄入")
                        .font(.title3.weight(.bold))
                        .foregroundStyle(GanfanPalette.ink)
                    Text(rangeCaption)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Picker("时间范围", selection: $range) {
                    ForEach(IntakeTrendRange.allCases) { item in
                        Text(item.title).tag(item)
                    }
                }
                .pickerStyle(.segmented)

                if visibleMetrics.isEmpty {
                    emptyState
                } else {
                    ForEach(visibleMetrics) { metric in
                        IntakeTrendCard(
                            metric: metric,
                            points: trendPoints(for: metric),
                            range: range,
                            selectedDate: $selectedDate,
                            expandedMetric: $expandedMetric,
                            hasSelectedChartDate: $hasSelectedChartDate
                        )
                    }
                }

                Text("热量和营养素合并用餐与饮品；水分（饮品）和咖啡因单独统计。估算值会参与合计，缺失值不会按 0 计入。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 2)
            }
            .padding(.horizontal, GanfanSpacing.pageHorizontal)
            .padding(.vertical, 16)
            .frame(maxWidth: 680, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .background(GanfanPalette.canvas)
        .onChange(of: range) { _, _ in
            let latestDataDay = dailySummaries.last { day in
                IntakeTrendMetric.allCases.contains { day.value(for: $0).value != nil }
            }?.date
            selectedDate = latestDataDay ?? dateRange.end
            hasSelectedChartDate = false
        }
        .onChange(of: selectedDate) { _, date in
            guard let nearestDate = dailySummaries.min(by: {
                      abs($0.date.timeIntervalSince(date)) < abs($1.date.timeIntervalSince(date))
                  })?.date,
                  !calendar.isDate(date, inSameDayAs: nearestDate) else { return }
            selectedDate = nearestDate
        }
        .navigationTitle("摄入洞察")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
    }

    private var rangeCaption: String {
        guard let first = dailySummaries.first?.date, let last = dailySummaries.last?.date else { return range.title }
        return "每日总摄入 · \(first.formatted(date: .abbreviated, time: .omitted)) – \(last.formatted(date: .abbreviated, time: .omitted))"
    }

    private var emptyState: some View {
        let hasRecords = dailySummaries.contains { $0.recordCount > 0 }
        return VStack(alignment: .leading, spacing: 7) {
            Label(
                hasRecords ? "暂时没有可用的营养数据" : "最近 \(range.rawValue) 天还没有记录",
                systemImage: hasRecords ? "chart.xyaxis.line" : "fork.knife"
            )
            .font(.headline)
            .foregroundStyle(GanfanPalette.ink)
            Text(hasRecords
                 ? "已有记录缺少可统计的营养值；补充数据后会显示趋势。"
                 : "记录用餐或饮品后，这里会显示每日摄入趋势。")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(GanfanPalette.card, in: RoundedRectangle(cornerRadius: GanfanShape.surface, style: .continuous))
    }

    private func trendPoints(for metric: IntakeTrendMetric) -> [IntakeTrendPoint] {
        var segment = 0
        var previousPointHadValue = false
        return dailySummaries.map { day in
            let total = day.value(for: metric)
            if total.value != nil {
                if !previousPointHadValue { segment += 1 }
                previousPointHadValue = true
            } else {
                previousPointHadValue = false
            }
            return IntakeTrendPoint(
                date: day.date,
                value: total.value,
                knownCount: total.knownCount,
                totalCount: total.totalCount,
                containsEstimate: total.containsEstimate,
                latestRecordAt: total.latestRecordAt,
                recordCount: day.recordCount,
                drinkCount: day.drinkCount,
                segment: segment
            )
        }
    }
}

private struct StorageUsageSnapshot {
    let photoFileCount: Int?
    let photoBytes: Int?
    let recordPayloadBytes: Int
    let settingsBytes: Int?
}

private struct RecentPhotoCard: Identifiable {
    let recordID: UUID
    let asset: PhotoAsset
    let label: String
    let occurredAt: Date

    var id: String { "\(recordID.uuidString)-\(asset.id.uuidString)" }
}

struct StorageDiagnosticsView: View {
    @Query(sort: \StoredJournalRecord.consumedAt, order: .reverse)
    private var storedRecords: [StoredJournalRecord]
    @State private var usage: StorageUsageSnapshot?
    @State private var failures: [PhotoStorageFailureEvent] = []
    @State private var copyMessage: String?
    @State private var activePhotoOverlay: JournalRecordOverlayRoute?

    private let failureStore = PhotoStorageDiagnosticsStore()
    private let catalogRepository = MenuCatalogRepository()

    private var recentPhotos: [RecentPhotoCard] {
        let photos = storedRecords.compactMap { storedRecord -> [RecentPhotoCard]? in
            guard let record = try? storedRecord.decodeRecord() else { return nil }
            switch record {
            case .drink(let drink):
                guard let photo = drink.photo else { return [] }
                return [RecentPhotoCard(recordID: drink.id, asset: photo, label: drink.drinkName, occurredAt: drink.consumedAt)]
            case .meal(let meal):
                return meal.dishes.compactMap { dish in
                    dish.photo.map { RecentPhotoCard(recordID: meal.id, asset: $0, label: dish.name, occurredAt: meal.consumedAt) }
                }
            }
        }.flatMap { $0 }
        return photos.sorted { $0.occurredAt > $1.occurredAt }.prefix(8).map { $0 }
    }

    var body: some View {
        List {
            Section {
                NavigationLink {
                    BackupSettingsView()
                } label: {
                    Label("iCloud Drive 备份与恢复", systemImage: "icloud.and.arrow.up")
                }
                Button("刷新统计", systemImage: "arrow.clockwise", action: refresh)
                Button("复制诊断摘要", systemImage: "doc.on.doc", action: copySummary)
            }

            Section("本机占用") {
                LabeledContent("照片文件", value: usage?.photoBytes.map(Self.byteLabel) ?? "无法读取")
                LabeledContent("照片文件数", value: usage?.photoFileCount.map(String.init) ?? "无法读取")
                LabeledContent("记录数据估算", value: usage.map { Self.byteLabel($0.recordPayloadBytes) } ?? "读取中")
                LabeledContent("菜单与偏好", value: usage?.settingsBytes.map(Self.byteLabel) ?? "暂无")
                Text("记录占用按编码字段估算；照片占用来自本机照片目录文件，不包含 iCloud 下载状态。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("最近的照片") {
                if recentPhotos.isEmpty {
                    Text("还没有关联到记录的照片。")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(recentPhotos) { item in
                        Button {
                            activePhotoOverlay = .photoViewer(assets: [item.asset], labels: [item.label])
                        } label: {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(item.label).font(.subheadline.weight(.medium))
                                Text(item.occurredAt.formatted(date: .abbreviated, time: .shortened))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            Section("最近失败") {
                if failures.isEmpty {
                    Text("没有记录到照片存储失败。")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(failures) { event in
                        VStack(alignment: .leading, spacing: 3) {
                            HStack {
                                Text(stageTitle(event.stage)).font(.subheadline.weight(.medium))
                                Spacer()
                                Text(event.occurredAt.formatted(date: .abbreviated, time: .shortened))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Text("\(reasonTitle(event.reason))\(event.byteCount.map { " · \(Self.byteLabel($0))" } ?? "")")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                Text("诊断只保留失败环节、通用原因和大小；不会保存记录正文、照片内容、文件路径或原始错误。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .scrollContentBackground(.hidden)
        .background(GanfanPalette.canvas)
        .tint(GanfanPalette.forest)
        .navigationTitle("本机存储")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $activePhotoOverlay) { route in
            JournalRecordOverlaySheet(route: route)
        }
        .task { refresh() }
        .alert("诊断摘要", isPresented: Binding(
            get: { copyMessage != nil },
            set: { if !$0 { copyMessage = nil } }
        )) {
            Button("好", role: .cancel) { copyMessage = nil }
        } message: {
            Text(copyMessage ?? "")
        }
    }

    private func refresh() {
        let photoUsage = Self.photoUsage(at: AppStoragePaths.photoStore.directoryURL)
        usage = StorageUsageSnapshot(
            photoFileCount: photoUsage?.count,
            photoBytes: photoUsage?.bytes,
            recordPayloadBytes: storedRecords.reduce(0) { $0 + $1.payload.count },
            settingsBytes: catalogRepository.savedStateByteCount
        )
        failures = failureStore.recentEvents
    }

    private func copySummary() {
        guard let usage else {
            copyMessage = "统计尚未完成，请稍后重试。"
            return
        }
        let report = [
            "吃吃喝喝本机存储诊断",
            "照片文件：\(usage.photoBytes.map(Self.byteLabel) ?? "无法读取")",
            "照片文件数：\(usage.photoFileCount.map(String.init) ?? "无法读取")",
            "记录数据估算：\(Self.byteLabel(usage.recordPayloadBytes))",
            "菜单与偏好：\(usage.settingsBytes.map(Self.byteLabel) ?? "暂无")",
            "近期照片失败：\(failures.count)"
        ].joined(separator: "\n")
        UIPasteboard.general.string = report
        copyMessage = "已复制摘要。内容不包含记录正文、照片、文件路径或原始错误。"
    }

    private static func photoUsage(at directory: URL) -> (count: Int, bytes: Int)? {
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: directory.path) else { return (0, 0) }
        guard let enumerator = fileManager.enumerator(
            at: directory,
            includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey],
            options: [.skipsHiddenFiles]
        ) else { return nil }
        var count = 0
        var bytes = 0
        for case let fileURL as URL in enumerator {
            do {
                let values = try fileURL.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
                guard values.isRegularFile == true else { continue }
                count += 1
                bytes += values.fileSize ?? 0
            } catch {
                return nil
            }
        }
        return (count, bytes)
    }

    private static func byteLabel(_ bytes: Int) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file)
    }

    private func stageTitle(_ stage: PhotoStorageFailureStage) -> String {
        switch stage {
        case .photoSelection: "读取所选照片"
        case .photoWrite: "保存原图"
        case .thumbnailWrite: "保存缩略图"
        case .photoRead: "读取本机照片"
        }
    }

    private func reasonTitle(_ reason: PhotoStorageFailureReason) -> String {
        switch reason {
        case .permissionDenied: "访问权限不足"
        case .diskFull: "设备空间不足"
        case .integrityMismatch: "文件校验未通过"
        case .unsupportedFormat: "照片格式不受支持"
        case .unknown: "未分类错误"
        }
    }
}

private struct RecordDetailSection<Content: View>: View {
    let title: String
    let symbol: String
    let trailing: AnyView?
    let content: Content

    init(
        title: String,
        symbol: String,
        trailing: AnyView? = nil,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.symbol = symbol
        self.trailing = trailing
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 9) {
                Image(systemName: symbol)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(GanfanPalette.forest)
                    .frame(width: 30, height: 30)
                    .background(GanfanPalette.paleLeaf, in: RoundedRectangle(cornerRadius: 10, style: .continuous))

                Text(title)
                    .font(.headline)
                    .foregroundStyle(GanfanPalette.ink)

                if let trailing {
                    Spacer(minLength: 4)
                    trailing
                }
            }

            content
        }
    }
}

private struct RecordDetailFact: Identifiable {
    let title: String
    let value: String
    let symbol: String

    var id: String { title }
}

private struct RecordDetailMetric: Identifiable {
    let title: String
    let value: String
    let unit: String
    let symbol: String
    let note: String?
    let hasValue: Bool

    var id: String { title }
}

private struct RecordDetailIconBadge: View {
    let symbol: String
    let dimension: CGFloat
    let symbolSize: CGFloat

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: symbolSize, weight: .semibold))
            .foregroundStyle(GanfanPalette.forest)
            .frame(width: dimension, height: dimension)
            .background(
                GanfanPalette.paleLeaf,
                in: RoundedRectangle(cornerRadius: dimension * 0.28, style: .continuous)
            )
            .accessibilityHidden(true)
    }
}

private struct RecordDetailHero: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    let kind: String
    let title: String
    let consumedAt: Date
    let symbol: String
    var compact: Bool = false
    var brandName: String? = nil
    var brand: MenuBrand? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: compact ? 10 : 16) {
            metadataHeader

            Text(title)
                .font(compact ? .title2.weight(.semibold) : .largeTitle.weight(.bold))
                .foregroundStyle(GanfanPalette.ink)
                .fixedSize(horizontal: false, vertical: true)

            if let brandName, !brandName.isEmpty {
                HStack(spacing: 8) {
                    GanfanBrandLogoIcon(
                        assetName: brand?.logoAssetName,
                        symbol: brand?.logoSymbol,
                        imageID: brand?.logoImageID,
                        dimension: 22
                    )

                    Text(brandName)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(compact ? 14 : 18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(GanfanPalette.card, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    @ViewBuilder
    private var metadataHeader: some View {
        if compact {
            HStack(alignment: .center, spacing: 10) {
                kindIcon

                VStack(alignment: .leading, spacing: 3) {
                    Text(kind)
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(GanfanPalette.leaf)

                    Text(consumedAt.formatted(date: .complete, time: .omitted))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 4)

                Label(consumedAt.formatted(date: .omitted, time: .shortened), systemImage: "clock")
                    .font(.caption.weight(.medium).monospacedDigit())
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: true, vertical: false)
                    .accessibilityElement(children: .combine)
            }
        } else if dynamicTypeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: 9) {
                HStack(spacing: 12) {
                    kindIcon
                    Text(kind)
                        .font(.headline.weight(.semibold))
                        .foregroundStyle(GanfanPalette.leaf)
                }

                Text(consumedAt.formatted(date: .complete, time: .omitted))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                Label(consumedAt.formatted(date: .omitted, time: .shortened), systemImage: "clock")
                    .font(.subheadline.weight(.semibold).monospacedDigit())
                    .foregroundStyle(GanfanPalette.ink)
            }
        } else {
            HStack(alignment: .center, spacing: 12) {
                kindIcon

                VStack(alignment: .leading, spacing: 4) {
                    Text(kind)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(GanfanPalette.leaf)

                    Text(consumedAt.formatted(date: .complete, time: .omitted))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 4)

                VStack(spacing: 3) {
                    Image(systemName: "clock")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(GanfanPalette.leaf)
                    Text(consumedAt.formatted(date: .omitted, time: .shortened))
                        .font(.subheadline.weight(.semibold).monospacedDigit())
                        .foregroundStyle(GanfanPalette.ink)
                }
                .accessibilityElement(children: .combine)
            }
        }
    }

    private var kindIcon: some View {
        Image(systemName: symbol)
            .font(.system(size: compact ? 18 : 22, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: compact ? 38 : 46, height: compact ? 38 : 46)
            .background(GanfanPalette.forest, in: RoundedRectangle(cornerRadius: compact ? 12 : 15, style: .continuous))
            .accessibilityHidden(true)
    }
}

private struct RecordDetailFactGrid: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    let facts: [RecordDetailFact]

    private var columns: [GridItem] {
        dynamicTypeSize.isAccessibilitySize
            ? [GridItem(.flexible(), spacing: 8, alignment: .leading)]
            : [GridItem(.adaptive(minimum: 132), spacing: 8, alignment: .leading)]
    }

    var body: some View {
        LazyVGrid(columns: columns, alignment: .leading, spacing: 8) {
            ForEach(facts) { fact in
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 6) {
                        RecordDetailIconBadge(symbol: fact.symbol, dimension: 22, symbolSize: 12)
                        Text(fact.title)
                            .font(.caption.weight(.medium))
                            .foregroundStyle(.secondary)
                    }

                    Text(fact.value)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(GanfanPalette.ink)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12)
                .background(GanfanPalette.card, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .accessibilityElement(children: .combine)
            }
        }
    }
}

private struct RecordDetailMetricGrid: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    let metrics: [RecordDetailMetric]
    var compact = false

    private var columns: [GridItem] {
        dynamicTypeSize.isAccessibilitySize
            ? [GridItem(.flexible(), spacing: 8, alignment: .leading)]
            : [GridItem(.adaptive(minimum: 132), spacing: 8, alignment: .leading)]
    }

    var body: some View {
        LazyVGrid(columns: columns, alignment: .leading, spacing: compact ? 5 : 8) {
            ForEach(metrics) { metric in
                HStack(alignment: .center, spacing: compact ? 7 : 9) {
                    RecordDetailIconBadge(
                        symbol: metric.symbol,
                        dimension: compact ? 21 : 26,
                        symbolSize: compact ? 12 : 14
                    )

                    VStack(alignment: .leading, spacing: compact ? 0 : 2) {
                        HStack(alignment: .firstTextBaseline, spacing: 3) {
                            Text(metric.value)
                                .font(metric.hasValue
                                      ? (compact ? .subheadline.weight(.bold).monospacedDigit() : .body.weight(.bold).monospacedDigit())
                                      : .caption.weight(.semibold))
                                .foregroundStyle(metric.hasValue ? GanfanPalette.ink : Color(uiColor: .secondaryLabel))
                                .fixedSize(horizontal: false, vertical: true)

                            if !metric.unit.isEmpty {
                                Text(metric.unit)
                                    .font(.caption.weight(.medium))
                                    .foregroundStyle(.secondary)
                            }
                        }

                        HStack(spacing: 4) {
                            Text(metric.title)
                                .font(compact ? .caption2.weight(.medium) : .caption.weight(.medium))
                                .foregroundStyle(.secondary)

                            if let note = metric.note {
                                Text(note)
                                    .font(.caption2.weight(.medium))
                                    .foregroundStyle(GanfanPalette.leaf)
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxWidth: .infinity, minHeight: compact ? 42 : 54, alignment: .leading)
                .padding(.horizontal, compact ? 8 : 10)
                .padding(.vertical, compact ? 5 : 8)
                .background(GanfanPalette.card, in: RoundedRectangle(cornerRadius: compact ? 11 : 14, style: .continuous))
                .accessibilityElement(children: .combine)
            }
        }
    }
}

private struct RecordDetailConfidenceBadge: View {
    let confidence: NutritionSnapshot.Confidence

    private var symbol: String {
        switch confidence {
        case .official: "checkmark.seal.fill"
        case .estimated: "chart.bar.fill"
        case .rough: "sparkles"
        case .unavailable: "questionmark.circle.fill"
        }
    }

    private var tint: Color {
        switch confidence {
        case .official, .estimated: GanfanPalette.forest
        case .rough: GanfanPalette.leaf
        case .unavailable: Color(uiColor: .secondaryLabel)
        }
    }

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: symbol)
                .font(.system(size: 14, weight: .semibold))
                .accessibilityHidden(true)
            Text(confidence.displayName)
                .font(.footnote.weight(.semibold))
        }
            .foregroundStyle(tint)
            .padding(.horizontal, 11)
            .padding(.vertical, 7)
            .background(tint.opacity(0.1), in: Capsule())
    }
}

private struct RecordDetailNutritionHeaderAccessory: View {
    let confidence: NutritionSnapshot.Confidence
    let assumptions: String
    let source: String
    let sourceURL: String?

    init(nutrition: NutritionSnapshot) {
        confidence = nutrition.confidence
        assumptions = nutrition.assumptions
        source = nutrition.source
        sourceURL = nutrition.sourceURL
    }

    init(snapshots: [NutritionSnapshot]) {
        let confidences = snapshots.map(\.confidence)
        if confidences.isEmpty || confidences.allSatisfy({ $0 == .unavailable }) {
            confidence = .unavailable
        } else if confidences.contains(.rough) {
            confidence = .rough
        } else if confidences.contains(.estimated) || confidences.contains(.unavailable) {
            confidence = .estimated
        } else {
            confidence = .official
        }

        assumptions = Self.joinUnique(snapshots.map(\.assumptions))
        source = Self.joinUnique(snapshots.map(\.source))
        let links = Self.joinUnique(snapshots.compactMap(\.sourceURL))
        sourceURL = links.isEmpty ? nil : links
    }

    private var hasDetails: Bool {
        !assumptions.isEmpty || !source.isEmpty || !(sourceURL?.isEmpty ?? true)
    }

    var body: some View {
        HStack(spacing: 6) {
            RecordDetailConfidenceBadge(confidence: confidence)

            if hasDetails {
                RecordDetailNutritionInfoButton(
                    assumptions: assumptions,
                    source: source,
                    sourceURL: sourceURL
                )
            }
        }
    }

    private static func joinUnique(_ values: [String]) -> String {
        values.reduce(into: [String]()) { result, value in
            let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines)
            if !normalized.isEmpty && !result.contains(normalized) {
                result.append(normalized)
            }
        }
        .joined(separator: "；")
    }
}

private struct RecordDetailNutritionInfoButton: View {
    let assumptions: String
    let source: String
    let sourceURL: String?

    @State private var isPresented = false

    var body: some View {
        Button {
            isPresented = true
        } label: {
            Image(systemName: "info.circle")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(GanfanPalette.forest)
                .frame(width: 30, height: 30)
                .background(GanfanPalette.paleLeaf, in: Circle())
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("查看营养估算说明")
        .popover(isPresented: $isPresented, arrowEdge: .top) {
            VStack(alignment: .leading, spacing: 13) {
                Text("营养说明")
                    .font(.headline)
                    .foregroundStyle(GanfanPalette.ink)

                if !assumptions.isEmpty {
                    detailBlock("估算假设", value: assumptions, symbol: "lightbulb")
                }

                if !source.isEmpty {
                    detailBlock("营养来源", value: source, symbol: "doc.text.magnifyingglass")
                }

                if let sourceURL, !sourceURL.isEmpty {
                    Divider()
                    if let url = URL(string: sourceURL), ["http", "https"].contains(url.scheme?.lowercased() ?? "") {
                        Link(destination: url) {
                            Label("打开来源链接", systemImage: "arrow.up.right")
                                .font(.footnote.weight(.medium))
                        }
                    } else {
                        detailBlock("来源链接", value: sourceURL, symbol: "link")
                    }
                }
            }
            .padding(16)
            .frame(width: 290, alignment: .leading)
            .presentationCompactAdaptation(.popover)
        }
    }

    private func detailBlock(_ title: String, value: String, symbol: String) -> some View {
        HStack(alignment: .top, spacing: 9) {
            Image(systemName: symbol)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(GanfanPalette.leaf)
                .frame(width: 18)
                .padding(.top, 2)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
                Text(value)
                    .font(.footnote)
                    .foregroundStyle(GanfanPalette.ink)
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

private struct RecordDetailInfoRow: View {
    let title: String
    let value: String
    let symbol: String

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: symbol)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(GanfanPalette.leaf)
                .frame(width: 20)
                .padding(.top, 2)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Text(value)
                    .font(.body)
                    .foregroundStyle(GanfanPalette.ink)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityElement(children: .combine)
    }
}

private struct RecordDetailView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @AppStorage(MenuCatalogRepository.changeGenerationKey) private var catalogChangeGeneration = 0

    let storedRecord: StoredJournalRecord

    @State private var isEditing = false
    @State private var isConfirmingDelete = false
    @State private var errorMessage: String?
    @State private var brandCatalog: [String: MenuBrand] = [:]
    @State private var activePhotoOverlay: JournalRecordOverlayRoute?

    private var decodedRecord: JournalRecord? {
        try? storedRecord.decodeRecord()
    }

    var body: some View {
        Group {
            if let record = decodedRecord {
                detailContent(for: record)
            } else {
                ContentUnavailableView(
                    "无法读取这条记录",
                    systemImage: "exclamationmark.triangle",
                    description: Text("资料仍保留在本机资料库中。")
                )
            }
        }
        .navigationTitle("记录详情")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
        .task(id: catalogChangeGeneration) {
            brandCatalog = await JournalBrandLogoCatalog.loadBrands()
        }
        .toolbar {
            if decodedRecord != nil {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button("编辑", systemImage: "pencil") { isEditing = true }
                        Button("删除记录", systemImage: "trash", role: .destructive) { isConfirmingDelete = true }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                }
            }
        }
        .confirmationDialog("删除这条记录？", isPresented: $isConfirmingDelete, titleVisibility: .visible) {
            Button("删除", role: .destructive, action: deleteRecord)
            Button("取消", role: .cancel) {}
        }
        .sheet(isPresented: $isEditing) {
            NavigationStack {
                if let record = decodedRecord {
                    switch record {
                    case .drink:
                        DrinkRecordForm(storedRecord: storedRecord)
                    case .meal:
                        MealRecordForm(storedRecord: storedRecord)
                    }
                }
            }
        }
        .alert("操作未完成", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("好", role: .cancel) { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "请稍后重试。")
        }
    }

    @ViewBuilder
    private func detailContent(for record: JournalRecord) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                switch record {
                case .drink(let drink): drinkContent(drink)
                case .meal(let meal): mealContent(meal)
                }
            }
            .frame(maxWidth: 680, alignment: .leading)
            .padding(.horizontal, 16)
            .padding(.vertical, 18)
            .frame(maxWidth: .infinity)
        }
        .background(GanfanPalette.canvas)
        .sheet(item: $activePhotoOverlay) { route in
            JournalRecordOverlaySheet(route: route)
        }
    }

    @ViewBuilder
    private func drinkContent(_ drink: DrinkRecord) -> some View {
        let serving = DrinkServingSelection(
            temperature: drink.temperature,
            ice: drink.ice,
            legacyServingOption: drink.temperature == nil && drink.ice == nil ? drink.servingOption : nil
        )
        let facts = [
            RecordDetailFact(title: "杯型", value: drink.cupType, symbol: "cup.and.saucer.fill"),
            RecordDetailFact(title: "温度", value: serving.displayLabel, symbol: "thermometer.medium"),
            RecordDetailFact(title: "甜度", value: drink.sweetness, symbol: "cube.fill"),
            RecordDetailFact(title: "容量", value: drink.sizeML.map { "\($0) ml" } ?? "", symbol: "ruler")
        ].filter { !$0.value.isEmpty }

        RecordDetailHero(
            kind: "饮品记录",
            title: drink.drinkName,
            consumedAt: drink.consumedAt,
            symbol: "cup.and.saucer.fill",
            compact: true,
            brandName: drink.brandName,
            brand: brandCatalog[drink.brandID]
        )

        if let photo = drink.photo {
            Button {
                activePhotoOverlay = .photoViewer(assets: [photo], labels: [drink.drinkName])
            } label: {
                RecordDetailPhoto(asset: photo)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("查看\(drink.drinkName)照片")
        }

        RecordDetailSection(title: "点单信息", symbol: "slider.horizontal.3") {
            if facts.isEmpty {
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "info.circle")
                        .font(.system(size: 14, weight: .medium))
                        .padding(.top, 2)
                        .accessibilityHidden(true)
                    Text("本次没有记录杯型、温度或甜度")
                        .font(.footnote)
                }
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 2)
            } else {
                RecordDetailFactGrid(facts: facts)
            }
        }

        drinkNutritionSection(drink.nutrition)

        if !drink.locationName.isEmpty || !drink.locationAddress.isEmpty || drink.latitude != nil {
            RecordDetailSection(title: "地点", symbol: "mappin.and.ellipse") {
                VStack(alignment: .leading, spacing: 14) {
                    if let latitude = drink.latitude, let longitude = drink.longitude {
                        StaticRecordLocationMap(
                            name: drink.locationName,
                            address: drink.locationAddress,
                            latitude: latitude,
                            longitude: longitude
                        )
                    }
                    let addressDetails = [drink.locationName, drink.locationAddress]
                        .filter { !$0.isEmpty }
                        .joined(separator: " · ")
                    if !addressDetails.isEmpty {
                        RecordDetailInfoRow(title: "地址", value: addressDetails, symbol: "mappin.and.ellipse")
                    }
                }
            }
        }

        if !drink.notes.isEmpty {
            RecordDetailSection(title: "备注", symbol: "text.quote") {
                Text(drink.notes)
                    .font(.body)
                    .foregroundStyle(GanfanPalette.ink)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(14)
                    .background(GanfanPalette.card, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
        }
    }

    @ViewBuilder
    private func drinkNutritionSection(_ nutrition: NutritionSnapshot?) -> some View {
        RecordDetailSection(
            title: "营养信息",
            symbol: "chart.bar.xaxis",
            trailing: nutrition.map { AnyView(RecordDetailNutritionHeaderAccessory(nutrition: $0)) }
        ) {
            if let nutrition {
                let metrics = nutritionMetrics(for: nutrition)
                VStack(alignment: .leading, spacing: 8) {
                    if metrics.contains(where: \.hasValue) {
                        RecordDetailMetricGrid(metrics: metrics, compact: true)
                    } else {
                        Label("暂无营养数据", systemImage: "leaf")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .padding(.vertical, 2)
                    }
                }
            } else {
                Label("这条记录没有保存营养资料", systemImage: "leaf")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 2)
            }
        }
    }

    private func nutritionMetrics(for nutrition: NutritionSnapshot) -> [RecordDetailMetric] {
        [
            nutritionMetric("能量", symbol: "flame.fill", value: nutrition.energyKcal, unit: "kcal"),
            nutritionMetric("糖", symbol: "cube.fill", value: nutrition.sugarGrams, unit: "g"),
            nutritionMetric("咖啡因", symbol: "cup.and.saucer.fill", value: nutrition.caffeineMilligrams, unit: "mg"),
            nutritionMetric("蛋白质", symbol: "figure.strengthtraining.traditional", value: nutrition.proteinGrams, unit: "g", sourceKey: "proteinGrams", sources: nutrition.metricSources),
            nutritionMetric("脂肪", symbol: "drop.fill", value: nutrition.fatGrams, unit: "g", sourceKey: "fatGrams", sources: nutrition.metricSources),
            nutritionMetric("碳水化合物", symbol: "leaf.fill", value: nutrition.carbohydrateGrams, unit: "g", sourceKey: "carbohydrateGrams", sources: nutrition.metricSources)
        ]
    }

    private func nutritionMetric(
        _ title: String,
        symbol: String,
        value: Double?,
        unit: String,
        sourceKey: String? = nil,
        sources: [String: String] = [:]
    ) -> RecordDetailMetric {
        guard let value, value.isFinite, value >= 0 else {
            return RecordDetailMetric(title: title, value: "暂无数据", unit: "", symbol: symbol, note: nil, hasValue: false)
        }

        let isRough = sourceKey.flatMap { sources[$0] } == "rough"
        return RecordDetailMetric(
            title: title,
            value: value.formatted(.number.precision(.fractionLength(0...1))),
            unit: unit,
            symbol: symbol,
            note: isRough ? "粗估" : nil,
            hasValue: true
        )
    }

    @ViewBuilder
    private func mealContent(_ meal: MealRecord) -> some View {
        let photoEntries = meal.dishes.compactMap { dish in
            dish.photo.map { (asset: $0, label: dish.name) }
        }
        let mealNutrition = meal.dishes.map {
            $0.nutrition ?? RoughNutritionEstimator.dish(name: $0.name)
        }

        RecordDetailHero(
            kind: "用餐记录",
            title: meal.storeName.isEmpty ? "用餐记录" : meal.storeName,
            consumedAt: meal.consumedAt,
            symbol: "fork.knife",
            compact: true
        )

        RecordDetailSection(
            title: "营养信息",
            symbol: "chart.bar.xaxis",
            trailing: AnyView(RecordDetailNutritionHeaderAccessory(snapshots: mealNutrition))
        ) {
            VStack(alignment: .leading, spacing: 7) {
                RecordDetailMetricGrid(metrics: [
                    mealMetric("能量", symbol: "flame.fill", value: mealNutrition.compactMap(\.energyKcal).reduce(0, +), unit: "kcal"),
                    mealMetric("蛋白质", symbol: "figure.strengthtraining.traditional", value: mealNutrition.compactMap(\.proteinGrams).reduce(0, +), unit: "g"),
                    mealMetric("脂肪", symbol: "drop.fill", value: mealNutrition.compactMap(\.fatGrams).reduce(0, +), unit: "g"),
                    mealMetric("碳水化合物", symbol: "leaf.fill", value: mealNutrition.compactMap(\.carbohydrateGrams).reduce(0, +), unit: "g")
                ], compact: true)

                HStack(alignment: .top, spacing: 7) {
                    Image(systemName: "info.circle")
                        .font(.system(size: 13, weight: .medium))
                        .padding(.top, 2)
                        .accessibilityHidden(true)
                    Text("参考估算，实际份量与烹调用油会带来差异")
                        .font(.caption2)
                }
                    .foregroundStyle(.secondary)
            }
        }

        RecordDetailSection(title: "菜品", symbol: "fork.knife") {
            VStack(alignment: .leading, spacing: 10) {
                Text("\(meal.dishes.count) 道菜")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)

                ForEach(Array(meal.dishes.enumerated()), id: \.element.id) { item in
                    mealDishCard(dish: item.element, index: item.offset, photoEntries: photoEntries)
                }
            }
        }

        if !meal.locationAddress.isEmpty || meal.latitude != nil {
            RecordDetailSection(title: "地点", symbol: "mappin.and.ellipse") {
                VStack(alignment: .leading, spacing: 14) {
                    if let latitude = meal.latitude, let longitude = meal.longitude {
                        StaticRecordLocationMap(
                            name: meal.storeName,
                            address: meal.locationAddress,
                            latitude: latitude,
                            longitude: longitude
                        )
                    }
                    if !meal.locationAddress.isEmpty {
                        RecordDetailInfoRow(title: "地址", value: meal.locationAddress, symbol: "map")
                    }
                }
            }
        }

        if !meal.notes.isEmpty {
            RecordDetailSection(title: "备注", symbol: "text.quote") {
                Text(meal.notes)
                    .font(.body)
                    .foregroundStyle(GanfanPalette.ink)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(14)
                    .background(GanfanPalette.card, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
        }
    }

    private func mealMetric(_ title: String, symbol: String, value: Double, unit: String) -> RecordDetailMetric {
        RecordDetailMetric(
            title: title,
            value: "约 \(Int(value))",
            unit: unit,
            symbol: symbol,
            note: nil,
            hasValue: true
        )
    }

    @ViewBuilder
    private func mealDishCard(
        dish: MealDish,
        index: Int,
        photoEntries: [(asset: PhotoAsset, label: String)]
    ) -> some View {
        let row = HStack(spacing: 12) {
            if let photo = dish.photo {
                JournalPhotoThumbnail(asset: photo, dimension: 76)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay(alignment: .bottomTrailing) {
                        Image(systemName: "arrow.up.left.and.arrow.down.right")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(.primary)
                            .padding(6)
                            .background(.ultraThinMaterial, in: Circle())
                            .padding(4)
                    }
            } else {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(GanfanPalette.paleLeaf)
                    .frame(width: 76, height: 76)
                    .overlay {
                        Image(systemName: "fork.knife")
                            .font(.title3.weight(.medium))
                            .foregroundStyle(GanfanPalette.leaf)
                    }
            }

            VStack(alignment: .leading, spacing: 5) {
                Text("\(index + 1). \(dish.name)")
                    .font(.headline)
                    .foregroundStyle(GanfanPalette.ink)
                    .fixedSize(horizontal: false, vertical: true)

                let nutrition = dish.nutrition ?? RoughNutritionEstimator.dish(name: dish.name)
                HStack(spacing: 6) {
                    Image(systemName: "flame.fill")
                        .font(.system(size: 13, weight: .semibold))
                        .accessibilityHidden(true)
                    Text(nutrition.energyKcal.map { "约 \(Int($0)) kcal" } ?? "暂无能量数据")
                        .font(.footnote)
                }
                    .foregroundStyle(.secondary)

                Text(nutrition.confidence.displayName)
                    .font(.caption)
                    .foregroundStyle(GanfanPalette.leaf)
            }
            Spacer(minLength: 0)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(GanfanPalette.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .contentShape(Rectangle())

        if let photo = dish.photo {
            let photoIndex = photoEntries.firstIndex { $0.asset.id == photo.id } ?? 0
            Button {
                activePhotoOverlay = .photoViewer(
                    assets: photoEntries.map(\.asset),
                    labels: photoEntries.map(\.label),
                    initialIndex: photoIndex
                )
            } label: {
                row
            }
            .buttonStyle(.plain)
            .accessibilityLabel("查看第 \(index + 1) 道菜：\(dish.name) 的照片")
        } else {
            row
        }
    }

    private func deleteRecord() {
        let previousRecord = decodedRecord
        BackupChangeTracker().markChanged()
        modelContext.delete(storedRecord)
        do {
            try modelContext.save()
            if let previousRecord {
                for asset in Self.photoAssets(in: previousRecord) {
                    try? AppStoragePaths.photoStore.remove(asset)
                }
            }
            dismiss()
        } catch {
            modelContext.rollback()
            errorMessage = error.localizedDescription
        }
    }

    private static func photoAssets(in record: JournalRecord) -> [PhotoAsset] {
        switch record {
        case .drink(let drink):
            return [drink.photo].compactMap { $0 }
        case .meal(let meal):
            return meal.dishes.compactMap(\.photo)
        }
    }
}

private struct RecordDetailPhoto: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    let asset: PhotoAsset

    @State private var image: UIImage?
    @State private var failed = false

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: .infinity, maxHeight: 360)
            } else if failed {
                ContentUnavailableView("照片无法读取", systemImage: "photo.badge.exclamationmark")
                    .frame(maxWidth: .infinity, minHeight: 180)
            } else {
                ProgressView("读取照片")
                    .frame(maxWidth: .infinity, minHeight: 180)
            }
        }
        .background(GanfanPalette.card)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(alignment: .bottomTrailing) {
            HStack(spacing: 6) {
                Image(systemName: "arrow.up.left.and.arrow.down.right")
                    .font(.system(size: 12, weight: .semibold))
                    .accessibilityHidden(true)
                if !dynamicTypeSize.isAccessibilitySize {
                    Text("查看照片")
                        .font(.caption.weight(.semibold))
                }
            }
            .foregroundStyle(.primary)
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(.ultraThinMaterial, in: Capsule())
            .padding(10)
        }
        .task(id: asset.id) {
            let currentAsset = asset
            let photoStore = AppStoragePaths.photoStore
            let data = await Task.detached(priority: .utility) { () -> Data? in
                guard let sourceData = try? photoStore.load(currentAsset) else { return nil }
                return JournalPhotoThumbnailLoader.thumbnailData(from: sourceData, maxPixelSize: 2_000)
            }.value
            guard !Task.isCancelled else { return }
            image = data.flatMap(UIImage.init(data:))
            failed = image == nil
        }
    }
}

private struct JournalRecordOverlaySheet: View {
    let route: JournalRecordOverlayRoute

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            switch route {
            case .detail(_, let storedRecord):
                RecordDetailView(storedRecord: storedRecord)
                    .toolbar {
                        ToolbarItem(placement: .topBarLeading) {
                            Button("关闭") { dismiss() }
                        }
                    }
            case .photos(_, let assets, let labels, let initialIndex):
                PhotoViewer(assets: assets, labels: labels, initialIndex: initialIndex)
                    .toolbar {
                        ToolbarItem(placement: .topBarLeading) {
                            Button("关闭", systemImage: "xmark") { dismiss() }
                        }
                    }
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .presentationCornerRadius(28)
        .presentationBackground(GanfanPalette.canvas)
    }
}

private struct PhotoViewer: View {
    let assets: [PhotoAsset]
    let labels: [String]
    @Environment(\.colorScheme) private var colorScheme
    @State private var currentIndex: Int
    @State private var currentImage: UIImage?
    @State private var thumbnailImages: [UUID: UIImage] = [:]
    @State private var errorMessage: String?

    init(assets: [PhotoAsset], labels: [String], initialIndex: Int = 0) {
        self.assets = assets
        self.labels = labels
        let safeIndex = assets.isEmpty ? 0 : min(max(0, initialIndex), assets.count - 1)
        _currentIndex = State(initialValue: safeIndex)
    }

    var body: some View {
        VStack(spacing: 0) {
            TabView(selection: $currentIndex) {
                ForEach(Array(assets.enumerated()), id: \.offset) { item in
                    let index = item.offset
                    let asset = item.element
                    Group {
                        if index == currentIndex, let currentImage {
                            Image(uiImage: currentImage)
                                .resizable()
                                .scaledToFit()
                        } else if let image = thumbnailImages[asset.id] {
                            Image(uiImage: image)
                                .resizable()
                                .scaledToFit()
                        } else if let errorMessage {
                            ContentUnavailableView("照片无法读取", systemImage: "photo.badge.exclamationmark", description: Text(errorMessage))
                        } else {
                            ProgressView("读取照片")
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(.black)
                    .tag(index)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))

            if assets.count > 1 {
                VStack(spacing: 10) {
                    Text("\(currentIndex + 1) / \(assets.count) · \(currentLabel)")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.white)
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 10) {
                            ForEach(Array(assets.enumerated()), id: \.offset) { item in
                                let index = item.offset
                                let asset = item.element
                                Button { currentIndex = index } label: {
                                    Group {
                                        if let image = thumbnailImages[asset.id] {
                                            Image(uiImage: image)
                                                .resizable()
                                                .scaledToFill()
                                        } else {
                                            Rectangle().fill(.white.opacity(0.16))
                                        }
                                    }
                                    .frame(width: 58, height: 58)
                                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                                    .overlay {
                                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                                            .stroke(index == currentIndex ? .white : .clear, lineWidth: 2)
                                    }
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel(labels.indices.contains(index) ? labels[index] : "第 \(index + 1) 张照片")
                            }
                        }
                        .padding(.horizontal, 16)
                    }
                }
                .padding(.vertical, 12)
                .background(.black)
            }
        }
        .background(.black)
        .padding(10)
        .background(GanfanPalette.canvas)
        .overlay {
            if colorScheme != .dark {
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .stroke(Color.white.opacity(0.28), lineWidth: 1)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .navigationTitle("照片")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            loadThumbnails()
            loadCurrentAsset()
        }
        .onChange(of: currentIndex) { _, _ in loadCurrentAsset() }
        .sensoryFeedback(.selection, trigger: currentIndex)
    }

    private var currentLabel: String {
        labels.indices.contains(currentIndex) ? labels[currentIndex] : "照片"
    }

    private func loadCurrentAsset() {
        guard assets.indices.contains(currentIndex) else { return }
        let asset = assets[currentIndex]
        do {
            let data = try AppStoragePaths.photoStore.load(asset)
            currentImage = Self.downsample(data, maxPixelSize: 2_400)
            if currentImage == nil {
                errorMessage = "照片文件格式无法解码。"
            }
        } catch {
            currentImage = nil
            PhotoStorageDiagnosticsStore().record(
                stage: .photoRead,
                reason: PhotoStorageDiagnosticsStore.reason(for: error),
                byteCount: asset.byteCount
            )
            errorMessage = "当前照片未能读取，其他照片仍可继续查看。"
        }
    }

    private func loadThumbnails() {
        for asset in assets where thumbnailImages[asset.id] == nil {
            do {
                let data = try AppStoragePaths.photoStore.load(asset)
                if let thumbnail = Self.downsample(data, maxPixelSize: 140) {
                    thumbnailImages[asset.id] = thumbnail
                }
            } catch {
                PhotoStorageDiagnosticsStore().record(
                    stage: .photoRead,
                    reason: PhotoStorageDiagnosticsStore.reason(for: error),
                    byteCount: asset.byteCount
                )
                continue
            }
        }
    }

    private static func downsample(_ data: Data, maxPixelSize: Int) -> UIImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
            kCGImageSourceShouldCacheImmediately: true
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
        return UIImage(cgImage: image)
    }
}

enum AppStoragePaths {
    static var photoStore: LocalPhotoStore {
        let applicationSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return LocalPhotoStore(
            directoryURL: applicationSupport
                .appendingPathComponent("GanfanHandbook", isDirectory: true)
                .appendingPathComponent("Photos", isDirectory: true)
        )
    }

    static var brandLogoPhotoStore: LocalPhotoStore {
        let applicationSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return LocalPhotoStore(
            directoryURL: applicationSupport
                .appendingPathComponent("GanfanHandbook", isDirectory: true)
                .appendingPathComponent("BrandLogos", isDirectory: true)
        )
    }

    static func brandLogoImageData(for id: UUID) -> Data? {
        let url = brandLogoPhotoStore.directoryURL
            .appendingPathComponent("\(id.uuidString).png", isDirectory: false)
        return try? Data(contentsOf: url, options: [.mappedIfSafe])
    }

    static func brandLogoIDs() -> [UUID] {
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: brandLogoPhotoStore.directoryURL,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }
        return files.compactMap { file in
            guard file.pathExtension.lowercased() == "png" else { return nil }
            return UUID(uuidString: file.deletingPathExtension().lastPathComponent)
        }
        .sorted { $0.uuidString < $1.uuidString }
    }

    static func brandLogoAssets() throws -> [PhotoAsset] {
        try brandLogoIDs().map { id in
            let fileName = "\(id.uuidString).png"
            let data = try Data(contentsOf: brandLogoPhotoStore.directoryURL.appendingPathComponent(fileName))
            let digest = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
            return try PhotoAsset(
                id: id,
                fileName: fileName,
                fileExtension: "png",
                byteCount: data.count,
                sha256: digest
            )
        }
    }

    static func removeBrandLogo(_ id: UUID) throws {
        let url = brandLogoPhotoStore.directoryURL
            .appendingPathComponent("\(id.uuidString).png", isDirectory: false)
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        try FileManager.default.removeItem(at: url)
    }
}
