import CryptoKit
import SwiftData
import SwiftUI
import UIKit
import ImageIO

private struct TimelineItem: Identifiable {
    let storedRecord: StoredJournalRecord
    let record: JournalRecord

    var id: UUID { record.id }
}

private enum JournalBrandLogoCatalog {
    static func loadBrands() -> [String: MenuBrand] {
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

    var body: some View {
        TabView(selection: $selectedTab) {
            JournalHomeView()
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
    }
}

struct JournalHomeView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage(BackupChangeTracker.pendingKey) private var hasPendingLibraryChanges = false
    @AppStorage(BackupChangeTracker.generationKey) private var libraryChangeGeneration = 0
    @Query(sort: \StoredJournalRecord.consumedAt, order: .reverse)
    private var storedRecords: [StoredJournalRecord]

    @StateObject private var backupWorkflow = BackupWorkflowModel.shared
    @State private var isCreatingDrink = false
    @State private var isCreatingMeal = false
    @State private var successfulSaveCount = 0
    @State private var brandCatalog: [String: MenuBrand] = [:]

    private var timelineItems: [TimelineItem] {
        let items = storedRecords.compactMap { storedRecord -> TimelineItem? in
            guard let record = try? storedRecord.decodeRecord() else { return nil }
            return TimelineItem(storedRecord: storedRecord, record: record)
        }

        return items.sorted(by: JournalRecordListFormatting.precedes)
    }

    private var todayItems: [TimelineItem] {
        timelineItems.filter { Calendar.current.isDateInToday($0.record.consumedAt) }
    }

    private func mergeLegacyMicroSweetness() {
        var replacements: [(StoredJournalRecord, DrinkRecord)] = []
        for storedRecord in storedRecords {
            guard let record = try? storedRecord.decodeRecord(),
                  case .drink(let drink) = record,
                  drink.sweetness == "微糖",
                  let migratedDrink = try? drink.replacingSweetness("三分糖") else {
                continue
            }
            replacements.append((storedRecord, migratedDrink))
        }
        guard !replacements.isEmpty else { return }

        do {
            for (storedRecord, drink) in replacements {
                try storedRecord.replace(with: .drink(drink))
            }
            try modelContext.save()
            BackupChangeTracker().markChanged()
        } catch {
            modelContext.rollback()
        }
    }

    private var unreadableRecordCount: Int {
        storedRecords.count - timelineItems.count
    }

    private var pendingBackupCount: Int {
        storedRecords.filter(\.needsBackup).count
    }

    private var dailyNutritionSummary: DailyNutritionSummary {
        .summarize(timelineItems.map(\.record), on: .now)
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
                brandCatalog = JournalBrandLogoCatalog.loadBrands()
                mergeLegacyMicroSweetness()
                backupWorkflow.restoreSavedFolderAccess()
                backupWorkflow.backupIfNeeded(storedRecords: storedRecords, context: modelContext)
            }
            .onChange(of: libraryChangeGeneration) { _, _ in
                brandCatalog = JournalBrandLogoCatalog.loadBrands()
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
            TodayDrinkNutritionSummary(summary: dailyNutritionSummary)
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
        HomeCaptureButton(title: "记饮品", symbol: "cup.and.saucer.fill", isPrimary: true) {
            isCreatingDrink = true
        }
    }

    private var captureMealButton: some View {
        HomeCaptureButton(title: "记用餐", symbol: "fork.knife", isPrimary: false) {
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
                "有 \(unreadableRecordCount) 条记录无法读取；原始数据仍保留在资料库中。",
                systemImage: "exclamationmark.triangle"
            )
            .font(.footnote)
            .foregroundStyle(.orange)
        }
    }

    private var todayRecordResults: some View {
        Group {
            if todayItems.isEmpty {
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
                VStack(spacing: 0) {
                    ForEach(Array(todayItems.enumerated()), id: \.element.id) { entry in
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

                        if entry.offset < todayItems.count - 1 {
                            Rectangle()
                                .fill(Color(uiColor: .separator).opacity(0.55))
                                .frame(height: 0.5)
                                .padding(.leading, 100)
                        }
                    }
                }
            }
        }
        .animation(recordListAnimation, value: todayItems.map(\.id))
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
    let value: Double?
    let unit: String

    var id: String { title }

    var formattedValue: String {
        guard let value, value.isFinite, value >= 0 else { return "—" }
        return value.formatted(.number.precision(.fractionLength(0...1)))
    }

    var spokenValue: String {
        guard value != nil else { return "暂无数据" }
        return "\(formattedValue) \(unit)"
    }
}

private struct TodayDrinkNutritionSummary: View {
    let summary: DailyNutritionSummary

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private var metrics: [DrinkNutritionMetric] {
        [
            DrinkNutritionMetric(title: "能量", value: summary.energyKcal.value, unit: "kcal"),
            DrinkNutritionMetric(title: "糖", value: summary.sugarGrams.value, unit: "g"),
            DrinkNutritionMetric(title: "咖啡因", value: summary.caffeineMilligrams.value, unit: "mg")
        ]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: GanfanSpacing.mediumSmall) {
            HStack {
                Label("今日饮品", systemImage: "cup.and.saucer.fill")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(GanfanPalette.forest)
                Spacer(minLength: 8)
                Text("\(summary.drinkCount) 杯")
                    .font(.subheadline.weight(.semibold).monospacedDigit())
                    .foregroundStyle(GanfanPalette.ink)
            }

            if summary.drinkCount == 0 {
                Text("记录饮品后显示摄入汇总")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: GanfanSpacing.small) {
                    ForEach(metrics) { metric in
                        metricRow(metric)
                    }
                }
            } else {
                HStack(alignment: .top, spacing: GanfanSpacing.small) {
                    ForEach(metrics) { metric in
                        metricColumn(metric)
                    }
                }
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

    private func metricColumn(_ metric: DrinkNutritionMetric) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(metric.title)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)

            metricAmount(metric, font: .title3.weight(.semibold))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(metric.title)，\(metric.spokenValue)")
    }

    private func metricRow(_ metric: DrinkNutritionMetric) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(metric.title)
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
    @AppStorage(BackupChangeTracker.generationKey) private var libraryChangeGeneration = 0
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
        .task { brandCatalog = JournalBrandLogoCatalog.loadBrands() }
        .onChange(of: libraryChangeGeneration) { _, _ in
            brandCatalog = JournalBrandLogoCatalog.loadBrands()
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

private struct InsightsView: View {
    @AppStorage(BackupChangeTracker.generationKey) private var libraryChangeGeneration = 0
    @Query(sort: \StoredJournalRecord.consumedAt, order: .reverse)
    private var storedRecords: [StoredJournalRecord]
    @State private var selectedDate = Date.now
    @State private var brandCatalog: [String: MenuBrand] = [:]

    private var itemsForDate: [TimelineItem] {
        let items = storedRecords.compactMap { storedRecord -> TimelineItem? in
            guard let record = try? storedRecord.decodeRecord(),
                  Calendar.current.isDate(record.consumedAt, inSameDayAs: selectedDate),
                  case .drink = record else { return nil }
            return TimelineItem(storedRecord: storedRecord, record: record)
        }
        return items.sorted(by: JournalRecordListFormatting.precedes)
    }

    private var summary: DailyNutritionSummary {
        .summarize(itemsForDate.map(\.record), on: selectedDate)
    }

    private var nutritionTitle: String {
        Calendar.current.isDateInToday(selectedDate)
            ? "今天的饮品"
            : "\(selectedDate.formatted(date: .abbreviated, time: .omitted)) 的饮品"
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                HStack {
                    Label("日期", systemImage: "calendar")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.secondary)
                    Spacer(minLength: 8)
                    DatePicker("日期", selection: $selectedDate, displayedComponents: .date)
                        .datePickerStyle(.compact)
                        .labelsHidden()
                }
                .padding(.bottom, 12)
                .overlay(alignment: .bottom) {
                    Rectangle()
                        .fill(Color(uiColor: .separator).opacity(0.55))
                        .frame(height: 0.5)
                }

                DailyNutritionHero(summary: summary, title: nutritionTitle)
                HStack(alignment: .firstTextBaseline) {
                    Text("饮品记录")
                        .font(.title3.weight(.bold))
                        .foregroundStyle(GanfanPalette.ink)
                    Spacer()
                    Text("\(itemsForDate.count) 条")
                        .font(.footnote.monospacedDigit())
                        .foregroundStyle(.secondary)
                }

                if itemsForDate.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        Label("这一天还没有饮品记录", systemImage: "cup.and.saucer")
                            .font(.headline)
                            .foregroundStyle(GanfanPalette.ink)
                        Text("回到“今日”记录饮品后，摄入信息会显示在这里。")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 8)
                } else {
                    VStack(spacing: 0) {
                        ForEach(Array(itemsForDate.enumerated()), id: \.element.id) { entry in
                            NavigationLink {
                                RecordDetailView(storedRecord: entry.element.storedRecord)
                            } label: {
                                VStack(alignment: .leading, spacing: 4) {
                                    JournalTimelineRow(record: entry.element.record, brandCatalog: brandCatalog)
                                    if case .drink(let drink) = entry.element.record {
                                        Text(nutritionDetail(drink.nutrition))
                                            .font(.footnote)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)

                            if entry.offset < itemsForDate.count - 1 {
                                Rectangle()
                                    .fill(Color(uiColor: .separator).opacity(0.55))
                                    .frame(height: 0.5)
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, GanfanSpacing.pageHorizontal)
            .padding(.vertical, 16)
            .frame(maxWidth: 680, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .background(GanfanPalette.canvas)
        .task { brandCatalog = JournalBrandLogoCatalog.loadBrands() }
        .onChange(of: libraryChangeGeneration) { _, _ in
            brandCatalog = JournalBrandLogoCatalog.loadBrands()
        }
        .navigationTitle("摄入洞察")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
    }

    private func nutritionDetail(_ nutrition: NutritionSnapshot?) -> String {
        guard let nutrition else { return "暂无营养数据" }
        let confidence = switch nutrition.confidence {
        case .official: "官方数据"
        case .estimated: "估算值"
        case .rough: "粗略估计"
        case .unavailable: "暂无数据"
        }
        let source = nutrition.source.isEmpty ? "" : " · \(nutrition.source)"
        return "\(confidence)\(source)"
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
            "食光记本机存储诊断",
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
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
            content
        }
        .padding(.vertical, 12)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(Color(uiColor: .separator).opacity(0.55))
                .frame(height: 0.5)
        }
    }
}

private struct RecordDetailView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

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
        .task { brandCatalog = JournalBrandLogoCatalog.loadBrands() }
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
            VStack(alignment: .leading, spacing: 16) {
                Label(record.consumedAt.formatted(date: .complete, time: .shortened), systemImage: "clock")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                switch record {
                case .drink(let drink):
                    let serving = DrinkServingSelection(
                        temperature: drink.temperature,
                        ice: drink.ice,
                        legacyServingOption: drink.temperature == nil && drink.ice == nil ? drink.servingOption : nil
                    )
                    VStack(alignment: .leading, spacing: 4) {
                        Text(drink.drinkName)
                            .font(.largeTitle.weight(.bold))
                            .foregroundStyle(GanfanPalette.ink)
                        if !drink.brandName.isEmpty {
                            HStack(spacing: 8) {
                                GanfanBrandLogoIcon(
                                    assetName: brandCatalog[drink.brandID]?.logoAssetName,
                                    symbol: brandCatalog[drink.brandID]?.logoSymbol,
                                    imageID: brandCatalog[drink.brandID]?.logoImageID,
                                    dimension: 20
                                )
                                Text(drink.brandName)
                                    .font(.title3)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }

                    if let photo = drink.photo {
                        Button {
                            activePhotoOverlay = .photoViewer(assets: [photo], labels: [drink.drinkName])
                        } label: {
                            RecordDetailPhoto(asset: photo)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("查看\(drink.drinkName)照片")
                    }

                    RecordDetailSection(title: "点单信息") {
                        VStack(alignment: .leading, spacing: 10) {
                            detailLine("杯型", drink.cupType)
                            detailLine("温度", serving.temperature)
                            detailLine("甜度", drink.sweetness)
                            detailLine("容量", drink.sizeML.map { "\($0) ml" } ?? "")
                            detailLine("冰量", serving.ice)
                        }
                    }

                    RecordDetailSection(title: "营养资料") {
                        VStack(alignment: .leading, spacing: 10) {
                            if let nutrition = drink.nutrition {
                                LabeledContent("营养状态", value: nutrition.confidence.displayName)
                                detailLine("能量", nutrition.energyKcal.map { "\($0.formatted(.number.precision(.fractionLength(0...1)))) kcal" } ?? "")
                                detailLine("糖", nutrition.sugarGrams.map { "\($0.formatted(.number.precision(.fractionLength(0...1)))) g" } ?? "")
                                detailLine("咖啡因", nutrition.caffeineMilligrams.map { "\($0.formatted(.number.precision(.fractionLength(0...1)))) mg" } ?? "")
                                detailLine("蛋白质" + (nutrition.metricSources["proteinGrams"] == "rough" ? "（粗估）" : ""), nutrition.proteinGrams.map { "\($0.formatted(.number.precision(.fractionLength(0...1)))) g" } ?? "")
                                detailLine("脂肪" + (nutrition.metricSources["fatGrams"] == "rough" ? "（粗估）" : ""), nutrition.fatGrams.map { "\($0.formatted(.number.precision(.fractionLength(0...1)))) g" } ?? "")
                                detailLine("碳水化合物" + (nutrition.metricSources["carbohydrateGrams"] == "rough" ? "（粗估）" : ""), nutrition.carbohydrateGrams.map { "\($0.formatted(.number.precision(.fractionLength(0...1)))) g" } ?? "")
                                detailLine("估算假设", nutrition.assumptions)
                                detailLine("营养来源", nutrition.source)
                                detailLine("来源链接", nutrition.sourceURL ?? "")
                            } else {
                                LabeledContent("营养状态", value: "暂无数据")
                            }
                        }
                    }

                    if !drink.locationName.isEmpty || !drink.locationAddress.isEmpty || drink.latitude != nil {
                        RecordDetailSection(title: "地点") {
                            VStack(alignment: .leading, spacing: 10) {
                                detailLine("地点", [drink.locationName, drink.locationAddress].filter { !$0.isEmpty }.joined(separator: " · "))
                                if let latitude = drink.latitude, let longitude = drink.longitude {
                                    StaticRecordLocationMap(
                                        name: drink.locationName,
                                        address: drink.locationAddress,
                                        latitude: latitude,
                                        longitude: longitude
                                    )
                                }
                            }
                        }
                    }

                    if !drink.notes.isEmpty {
                        RecordDetailSection(title: "备注") {
                            VStack(alignment: .leading, spacing: 6) {
                                Text(drink.notes)
                                    .font(.body)
                                    .foregroundStyle(GanfanPalette.ink)
                            }
                        }
                    }
                case .meal(let meal):
                    let photoEntries = meal.dishes.compactMap { dish in
                        dish.photo.map { (asset: $0, label: dish.name) }
                    }
                    Text(meal.storeName.isEmpty ? "用餐记录" : meal.storeName)
                        .font(.largeTitle.weight(.bold))
                        .foregroundStyle(GanfanPalette.ink)

                    if !meal.locationAddress.isEmpty || meal.latitude != nil {
                        RecordDetailSection(title: "地点") {
                            VStack(alignment: .leading, spacing: 10) {
                                detailLine("地址", meal.locationAddress)
                                if let latitude = meal.latitude, let longitude = meal.longitude {
                                    StaticRecordLocationMap(
                                        name: meal.storeName,
                                        address: meal.locationAddress,
                                        latitude: latitude,
                                        longitude: longitude
                                    )
                                }
                            }
                        }
                    }

                    if !meal.notes.isEmpty {
                        RecordDetailSection(title: "备注") {
                            VStack(alignment: .leading, spacing: 6) {
                                Text(meal.notes)
                                    .font(.body)
                            }
                        }
                    }

                    let mealNutrition = meal.dishes.map {
                        $0.nutrition ?? RoughNutritionEstimator.dish(name: $0.name)
                    }
                    RecordDetailSection(title: "本餐营养参考") {
                        VStack(alignment: .leading, spacing: 8) {
                            LabeledContent("能量", value: "约 \(Int(mealNutrition.compactMap(\.energyKcal).reduce(0, +))) kcal")
                            LabeledContent("蛋白质", value: "约 \(Int(mealNutrition.compactMap(\.proteinGrams).reduce(0, +))) g")
                            LabeledContent("脂肪", value: "约 \(Int(mealNutrition.compactMap(\.fatGrams).reduce(0, +))) g")
                            LabeledContent("碳水化合物", value: "约 \(Int(mealNutrition.compactMap(\.carbohydrateGrams).reduce(0, +))) g")
                            Text("包含离线粗估或 AI 辅助估算，实际份量与烹调用油可能造成较大误差。")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }

                    HStack(alignment: .firstTextBaseline) {
                        Text("菜品")
                            .font(.title2.weight(.bold))
                            .foregroundStyle(GanfanPalette.ink)
                        Spacer()
                        Text("\(meal.dishes.count) 道")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.top, 4)

                    ForEach(Array(meal.dishes.enumerated()), id: \.element.id) { item in
                        mealDishCard(
                            dish: item.element,
                            index: item.offset,
                            photoEntries: photoEntries
                        )
                    }
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
    private func mealDishCard(
        dish: MealDish,
        index: Int,
        photoEntries: [(asset: PhotoAsset, label: String)]
    ) -> some View {
        let row = HStack(spacing: 12) {
            if let photo = dish.photo {
                JournalPhotoThumbnail(asset: photo, dimension: 82)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            } else {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(GanfanPalette.paleLeaf)
                    .frame(width: 82, height: 82)
                    .overlay {
                        Image(systemName: "fork.knife")
                            .foregroundStyle(GanfanPalette.leaf)
                    }
            }
            VStack(alignment: .leading, spacing: 4) {
                Text("\(index + 1). \(dish.name)")
                    .font(.headline)
                    .foregroundStyle(GanfanPalette.ink)
                let nutrition = dish.nutrition ?? RoughNutritionEstimator.dish(name: dish.name)
                Text("\(nutrition.confidence.displayName) · 约 \(Int(nutrition.energyKcal ?? 0)) kcal")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if dish.photo != nil {
                    Text("查看菜品照片")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 0)
        }
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

    @ViewBuilder
    private func detailLine(_ title: String, _ value: String) -> some View {
        if !value.isEmpty {
            LabeledContent(title, value: value)
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
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(Color(uiColor: .separator).opacity(0.16), lineWidth: 1)
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
