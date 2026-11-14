import PhotosUI
import SwiftData
import SwiftUI
import UIKit

struct DrinkRecordForm: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    private let storedRecord: StoredJournalRecord?
    private let originalRecord: DrinkRecord?
    private let onSave: (() -> Void)?

    @State private var drinkName: String
    @State private var brandName: String
    @State private var consumedAt: Date
    @State private var cupType: String
    @State private var sweetness: String
    @State private var temperature: String
    @State private var ice: String
    @State private var globalCupSizes: [MenuCupSize]
    @State private var locationName: String
    @State private var locationAddress: String
    @State private var locationLatitude: Double?
    @State private var locationLongitude: Double?
    @State private var confirmedMapAddress: String
    @State private var isSelectingLocation = false
    @State private var notes: String
    @State private var isSelectingMenuDrink = false
    @State private var selectedMenuDrink: MenuDrink?
    @State private var selectedPhoto: PhotosPickerItem?
    @State private var selectedPhotoData: Data?
    @State private var savedPhotoData: Data?
    @State private var photoExtension = "jpg"
    @State private var photoRemoved = false
    @State private var isSaving = false
    @State private var errorMessage: String?

    init(storedRecord: StoredJournalRecord? = nil, onSave: (() -> Void)? = nil) {
        self.storedRecord = storedRecord
        self.onSave = onSave
        let originalRecord = Self.decodeDrink(storedRecord)
        self.originalRecord = originalRecord
        let servingSelection = DrinkServingSelection(
            temperature: originalRecord?.temperature,
            ice: originalRecord?.ice,
            legacyServingOption: originalRecord?.temperature == nil && originalRecord?.ice == nil
                ? originalRecord?.servingOption
                : nil
        )

        _drinkName = State(initialValue: originalRecord?.drinkName ?? "")
        _brandName = State(initialValue: originalRecord?.brandName ?? "")
        _consumedAt = State(initialValue: originalRecord?.consumedAt ?? .now)
        _cupType = State(initialValue: originalRecord?.cupType ?? "")
        _sweetness = State(initialValue: originalRecord?.sweetness ?? "")
        _temperature = State(initialValue: servingSelection.temperature)
        _ice = State(initialValue: servingSelection.ice)
        _globalCupSizes = State(initialValue: Self.loadGlobalCupSizes())
        _selectedMenuDrink = State(initialValue: Self.catalogDrink(for: originalRecord?.drinkID))
        _locationName = State(initialValue: originalRecord?.locationName ?? "")
        _locationAddress = State(initialValue: originalRecord?.locationAddress ?? "")
        _locationLatitude = State(initialValue: originalRecord?.latitude)
        _locationLongitude = State(initialValue: originalRecord?.longitude)
        _confirmedMapAddress = State(initialValue: originalRecord?.latitude != nil ? originalRecord?.locationAddress ?? "" : "")
        _notes = State(initialValue: originalRecord?.notes ?? "")
    }

    var body: some View {
        let hasPhoto = selectedPhotoData != nil || savedPhotoData != nil

        Form {
            Section {
                PhotosPicker(selection: $selectedPhoto, matching: .images) {
                    Label(hasPhoto ? "更换饮品照片" : "添加饮品照片", systemImage: "photo")
                }

                if let image = previewImage {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                        .frame(maxHeight: 190)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                }

                if selectedPhotoData != nil || savedPhotoData != nil {
                    Button("移除照片", role: .destructive) {
                        photoRemoved = true
                        selectedPhotoData = nil
                        selectedPhoto = nil
                    }
                }
            } header: {
                Text("照片")
            } footer: {
                Text("照片可以稍后补上。")
            }

            Section("喝的是什么") {
                Button {
                    isSelectingMenuDrink = true
                } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(selectedMenuDrink == nil ? "从饮品目录选择" : "已选目录饮品")
                                .foregroundStyle(.primary)
                            if let selectedMenuDrink {
                                Text("\(selectedMenuDrink.brandName) · \(selectedMenuDrink.name)")
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            } else {
                                Text("也可以手动填写品牌和饮品名称")
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        Spacer(minLength: 8)
                        Image(systemName: "magnifyingglass")
                            .foregroundStyle(GanfanPalette.forest)
                    }
                }
                .buttonStyle(.plain)

                TextField("品牌 / 店铺", text: $brandName)
                    .textContentType(.organizationName)
                TextField("饮品名称", text: $drinkName)
                    .textContentType(.none)

                if let selectedMenuDrink {
                    LabeledContent("菜单状态", value: selectedMenuDrink.status == "verified" ? "已核验" : "待核验")
                }
            }

            Section("这一杯的细节") {
                Picker("杯型", selection: $cupType) {
                    Text("未选择").tag("")
                    ForEach(cupTypeOptions, id: \.self) { Text($0).tag($0) }
                }
                if !cupType.isEmpty {
                    LabeledContent("容量", value: cupSizeLabel)
                }
                OptionChipPicker(title: "甜度", options: [""] + sweetnessOptions, selection: $sweetness)
                OptionChipPicker(title: "温度", options: [""] + temperatureOptions, selection: $temperature)
                OptionChipPicker(title: "冰量", options: [""] + iceOptions, selection: $ice)
                    .disabled(temperature == "热饮" || temperature == "常温")
            }

            Section("营养快照") {
                DisclosureGroup("本次摄入") {
                    let nutrition = calculatedNutrition
                    LabeledContent("状态", value: nutrition.confidence.displayName)
                    nutritionValue("能量", amount: nutrition.energyKcal, unit: "kcal")
                    nutritionValue("糖", amount: nutrition.sugarGrams, unit: "g")
                    nutritionValue("咖啡因", amount: nutrition.caffeineMilligrams, unit: "mg")
                    nutritionValue("蛋白质", amount: nutrition.proteinGrams, unit: "g")
                    nutritionValue("脂肪", amount: nutrition.fatGrams, unit: "g")
                    nutritionValue("碳水化合物", amount: nutrition.carbohydrateGrams, unit: "g")
                    if !nutrition.assumptions.isEmpty {
                        Text(nutrition.assumptions).font(.caption).foregroundStyle(.secondary)
                    }
                    if !nutrition.source.isEmpty {
                        LabeledContent("来源", value: nutrition.source)
                    }
                    if let sourceURL = nutrition.sourceURL, !sourceURL.isEmpty {
                        LabeledContent("来源链接", value: sourceURL)
                    }
                }
            }

            Section("时间与地点") {
                DatePicker("饮用时间", selection: $consumedAt, displayedComponents: [.date, .hourAndMinute])
                TextField("店名或地点", text: $locationName)
                Button {
                    isSelectingLocation = true
                } label: {
                    Label(locationLatitude == nil ? "地图选地址" : "重新选择地图地址", systemImage: "map")
                }
                TextField("地址（地图不可用时可手填）", text: $locationAddress, axis: .vertical)
                    .onChange(of: locationAddress) { _, newValue in
                        if newValue != confirmedMapAddress {
                            locationLatitude = nil
                            locationLongitude = nil
                        }
                    }
                if locationLatitude != nil, locationLongitude != nil {
                    Label("已保存地图坐标", systemImage: "location.fill")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                TextField("备注（可选）", text: $notes, axis: .vertical)
                    .accessibilityHint("记录这杯饮品的口味或当时的心情")
            }
        }
        .scrollContentBackground(.hidden)
        .background(GanfanPalette.canvas)
        .tint(GanfanPalette.forest)
        .navigationTitle(storedRecord == nil ? "记录饮品" : "编辑饮品")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("取消") { dismiss() }
                    .disabled(isSaving)
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("保存", action: saveRecord)
                    .disabled(isSaving || drinkName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .task(id: selectedPhoto) {
            await loadSelectedPhoto()
        }
        .task {
            await loadSavedPhoto()
        }
        .onChange(of: temperature) { _, newValue in
            if newValue == "热饮" || newValue == "常温" {
                ice = ""
            }
        }
        .sheet(isPresented: $isSelectingMenuDrink) {
            NavigationStack {
                MenuPickerView(catalog: Self.loadBundledCatalog()) { drink in
                    selectedMenuDrink = drink
                    brandName = drink.brandName
                    drinkName = drink.name
                    if cupType.isEmpty, let menuCup = drink.cupTypes.first, cupTypeOptions.contains(menuCup) {
                        cupType = menuCup
                    }
                }
            }
        }
        .sheet(isPresented: $isSelectingLocation) {
            NavigationStack {
                MapLocationPickerView(
                    initialAddress: locationAddress,
                    initialLatitude: locationLatitude,
                    initialLongitude: locationLongitude
                ) { selection in
                    if locationName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        locationName = selection.storeName
                    }
                    confirmedMapAddress = selection.address
                    locationAddress = selection.address
                    locationLatitude = selection.latitude
                    locationLongitude = selection.longitude
                }
            }
        }
        .alert("未能保存饮品记录", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("好", role: .cancel) { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "请重试。")
        }
    }

    private var previewImage: UIImage? {
        guard !photoRemoved else { return nil }
        if let selectedPhotoData, let image = UIImage(data: selectedPhotoData) { return image }
        if let savedPhotoData { return UIImage(data: savedPhotoData) }
        return nil
    }

    private var cupTypeOptions: [String] {
        var options = globalCupSizes.reduce(into: [String]()) { options, item in
            guard !item.cupType.isEmpty, !options.contains(item.cupType) else { return }
            options.append(item.cupType)
        }
        if !cupType.isEmpty, !options.contains(cupType) {
            options.append(cupType)
        }
        return options
    }

    private var selectedCupSizeML: Int? {
        guard let selected = globalCupSizes.first(where: { $0.cupType == cupType })?.sizeML,
              selected > 0 else { return nil }
        return selected
    }

    private var recordSizeML: Int? {
        if originalRecord?.cupType == cupType, let originalSize = originalRecord?.sizeML {
            return originalSize
        }
        return selectedCupSizeML
    }

    private var cupSizeLabel: String {
        recordSizeML.map { "\($0) ml" } ?? "未设置"
    }

    private var sweetnessOptions: [String] {
        var options = selectedMenuDrink?.sweetnessOptions.filter { !$0.isEmpty } ?? []
        if options.isEmpty { options = ["无糖", "微糖", "三分糖", "五分糖", "七分糖", "全糖"] }
        if !sweetness.isEmpty, !options.contains(sweetness) { options.append(sweetness) }
        return options
    }

    private var temperatureOptions: [String] {
        let menuOptions = selectedMenuDrink?.servingOptions.filter {
            ["常温", "热", "热饮", "冰饮"].contains($0)
        } ?? []
        var options = menuOptions.isEmpty ? ["冰饮", "常温", "热饮"] : menuOptions.map { $0 == "热" ? "热饮" : $0 }
        if !temperature.isEmpty, !options.contains(temperature) { options.append(temperature) }
        return options
    }

    private var iceOptions: [String] {
        let menuOptions = selectedMenuDrink?.servingOptions.filter { $0.contains("冰") && $0 != "冰饮" } ?? []
        var options = menuOptions.isEmpty ? ["少冰", "正常冰", "多冰", "去冰"] : menuOptions
        if !ice.isEmpty, !options.contains(ice) { options.append(ice) }
        return options
    }

    private var calculatedNutrition: NutritionSnapshot {
        if let originalRecord,
           originalRecord.brandName == brandName,
           originalRecord.drinkName == drinkName,
           originalRecord.cupType == cupType,
           originalRecord.sizeML == recordSizeML,
           originalRecord.sweetness == sweetness {
            let originalServing = DrinkServingSelection(
                temperature: originalRecord.temperature,
                ice: originalRecord.ice,
                legacyServingOption: originalRecord.temperature == nil && originalRecord.ice == nil
                    ? originalRecord.servingOption
                    : nil
            )
            if originalServing.temperature == temperature, originalServing.ice == ice,
               let savedNutrition = originalRecord.nutrition, savedNutrition.confidence != .unavailable {
                return savedNutrition
            }
        }

        let selectedMenuIsCurrent = selectedMenuDrink?.brandName == brandName
            && selectedMenuDrink?.name == drinkName
        if selectedMenuIsCurrent {
            return DrinkNutritionCalculator.snapshot(
                for: selectedMenuDrink,
                cupType: cupType,
                sizeML: recordSizeML,
                sweetness: sweetness,
                temperature: temperature,
                ice: ice
            )
        }

        guard let originalRecord,
              originalRecord.brandName == brandName,
              originalRecord.drinkName == drinkName else {
            return RoughNutritionEstimator.drink(name: drinkName, sizeML: recordSizeML,
                                                  cupType: cupType, sweetness: sweetness,
                                                  temperature: temperature, ice: ice)
        }
        let originalServing = DrinkServingSelection(
            temperature: originalRecord.temperature,
            ice: originalRecord.ice,
            legacyServingOption: originalRecord.temperature == nil && originalRecord.ice == nil
                ? originalRecord.servingOption
                : nil
        )
        if originalRecord.cupType == cupType,
           originalRecord.sizeML == recordSizeML,
           originalRecord.sweetness == sweetness,
           originalServing.temperature == temperature,
           originalServing.ice == ice {
            if let existing = originalRecord.nutrition, existing.confidence != .unavailable {
                return existing
            }
            return RoughNutritionEstimator.drink(name: drinkName, sizeML: recordSizeML,
                                                 cupType: cupType, sweetness: sweetness,
                                                 temperature: temperature, ice: ice)
        }
        return RoughNutritionEstimator.drink(name: drinkName, sizeML: recordSizeML,
                                             cupType: cupType, sweetness: sweetness,
                                             temperature: temperature, ice: ice)
    }

    @ViewBuilder
    private func nutritionValue(_ title: String, amount: Double?, unit: String) -> some View {
        if let amount {
            LabeledContent(title, value: "\(amount.formatted(.number.precision(.fractionLength(0...1)))) \(unit)")
        } else {
            LabeledContent(title, value: "暂无数据")
        }
    }

    private func loadSelectedPhoto() async {
        guard let selectedPhoto else { return }
        do {
            selectedPhotoData = try await selectedPhoto.loadTransferable(type: Data.self)
            photoExtension = selectedPhoto.supportedContentTypes.first?.preferredFilenameExtension ?? "jpg"
            photoRemoved = false
        } catch {
            selectedPhotoData = nil
            PhotoStorageDiagnosticsStore().record(stage: .photoSelection, reason: PhotoStorageDiagnosticsStore.reason(for: error))
            errorMessage = "读取所选照片失败：\(error.localizedDescription)"
        }
    }

    private func recognizeFood() async {
        guard aiConfigured, AISettingsStore.isReady,
              let apiKey = AISettingsStore.apiKey(),
              let photo = draft.photoData ?? (draft.photoRemoved ? nil : savedPhotoData) else { return }
        isRecognizing = true
        defer { isRecognizing = false }
        do {
            let result = try await AIPhotoNutritionService().recognize(
                photo: photo, configuration: AISettingsStore.load(), apiKey: apiKey
            )
            let name = result.dishName.trimmingCharacters(in: .whitespacesAndNewlines)
            draft.name = name
            draft.nutritionName = name
            draft.nutrition = IngredientNutritionEstimator.calculate(
                dishName: name, ingredients: result.ingredients
            )
            errorMessage = nil
        } catch {
            errorMessage = "AI 识别失败：\(error.localizedDescription)。您仍可使用离线粗估。"
        }
    }

    private func loadSavedPhoto() async {
        guard let photo = originalRecord?.photo else { return }
        do {
            savedPhotoData = try AppStoragePaths.photoStore.load(photo)
        } catch {
            PhotoStorageDiagnosticsStore().record(stage: .photoRead, reason: PhotoStorageDiagnosticsStore.reason(for: error), byteCount: photo.byteCount)
            errorMessage = "读取本机照片失败：\(error.localizedDescription)"
        }
    }

    private func saveRecord() {
        guard !isSaving else { return }
        isSaving = true

        Task { @MainActor in
            var newAsset: PhotoAsset?
            do {
                let photo: PhotoAsset?
                if let selectedPhotoData {
                    let saved = try AppStoragePaths.photoStore.save(selectedPhotoData, fileExtension: photoExtension)
                    newAsset = saved
                    photo = saved
                } else if photoRemoved {
                    photo = nil
                } else {
                    photo = originalRecord?.photo
                }

                let selectedMenuIsCurrent = selectedMenuDrink?.brandName == brandName
                    && selectedMenuDrink?.name == drinkName
                let existingSelectionIsCurrent = originalRecord?.brandName == brandName
                    && originalRecord?.drinkName == drinkName
                let brandID = selectedMenuIsCurrent
                    ? selectedMenuDrink?.brandID ?? ""
                    : (existingSelectionIsCurrent ? originalRecord?.brandID ?? "" : "")
                let drinkID = selectedMenuIsCurrent
                    ? selectedMenuDrink?.id ?? ""
                    : (existingSelectionIsCurrent ? originalRecord?.drinkID ?? "" : "")
                let nutrition = calculatedNutrition
                let recordSize = recordSizeML

                let record = try DrinkRecord(
                    id: originalRecord?.id ?? UUID(),
                    consumedAt: consumedAt,
                    brandID: brandID,
                    brandName: brandName,
                    drinkID: drinkID,
                    drinkName: drinkName,
                    cupType: cupType,
                    sizeML: recordSize,
                    sweetness: sweetness,
                    servingOption: "",
                    temperature: temperature.isEmpty ? nil : temperature,
                    ice: ice.isEmpty ? nil : ice,
                    locationName: locationName,
                    locationAddress: locationAddress,
                    latitude: locationLatitude,
                    longitude: locationLongitude,
                    notes: notes,
                    photo: photo,
                    nutrition: nutrition
                )
                try persist(.drink(record), createdPhotoAssets: newAsset.map { [$0] } ?? [])

                if let oldPhoto = originalRecord?.photo, oldPhoto != photo {
                    try? AppStoragePaths.photoStore.remove(oldPhoto)
                }
                onSave?()
                dismiss()
            } catch {
                if let newAsset { try? AppStoragePaths.photoStore.remove(newAsset) }
                if selectedPhotoData != nil {
                    PhotoStorageDiagnosticsStore().record(
                        stage: .photoWrite,
                        reason: PhotoStorageDiagnosticsStore.reason(for: error),
                        byteCount: selectedPhotoData?.count
                    )
                }
                errorMessage = error.localizedDescription
                isSaving = false
            }
        }
    }

    private func persist(_ record: JournalRecord, createdPhotoAssets: [PhotoAsset]) throws {
        try JournalRecordCommitService.save(
            record,
            replacing: storedRecord,
            createdPhotoAssets: createdPhotoAssets,
            photoStore: AppStoragePaths.photoStore,
            into: modelContext
        )
    }

    private static func decodeDrink(_ storedRecord: StoredJournalRecord?) -> DrinkRecord? {
        guard let storedRecord, let decoded = try? storedRecord.decodeRecord(), case .drink(let drink) = decoded else {
            return nil
        }
        return drink
    }

    private static func loadBundledCatalog() -> MenuCatalog? {
        guard let url = Bundle.main.url(forResource: "catalog", withExtension: "json"),
              let data = try? Data(contentsOf: url) else {
            return nil
        }
        guard let bundled = try? MenuCatalog.decode(data) else { return nil }
        return try? MenuCatalogRepository().catalog(from: bundled)
    }

    private static func catalogDrink(for id: String?) -> MenuDrink? {
        guard let id, !id.isEmpty else { return nil }
        return loadBundledCatalog()?.drinks.first(where: { $0.id == id })
    }

    private static func loadGlobalCupSizes() -> [MenuCupSize] {
        (try? MenuCatalogRepository().loadUserState().globalCupSizes) ?? MenuCatalogUserState.defaultCupSizes
    }
}

struct MealRecordForm: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    private let storedRecord: StoredJournalRecord?
    private let originalRecord: MealRecord?
    private let onSave: (() -> Void)?

    @State private var consumedAt: Date
    @State private var storeName: String
    @State private var locationAddress: String
    @State private var locationLatitude: Double?
    @State private var locationLongitude: Double?
    @State private var confirmedMapAddress: String
    @State private var isSelectingLocation = false
    @State private var notes: String
    @State private var dishes: [MealDishDraft]
    @State private var isSaving = false
    @State private var errorMessage: String?

    init(storedRecord: StoredJournalRecord? = nil, onSave: (() -> Void)? = nil) {
        self.storedRecord = storedRecord
        self.onSave = onSave
        let originalRecord = Self.decodeMeal(storedRecord)
        self.originalRecord = originalRecord

        _consumedAt = State(initialValue: originalRecord?.consumedAt ?? .now)
        _storeName = State(initialValue: originalRecord?.storeName ?? "")
        _locationAddress = State(initialValue: originalRecord?.locationAddress ?? "")
        _locationLatitude = State(initialValue: originalRecord?.latitude)
        _locationLongitude = State(initialValue: originalRecord?.longitude)
        _confirmedMapAddress = State(initialValue: originalRecord?.latitude != nil ? originalRecord?.locationAddress ?? "" : "")
        _notes = State(initialValue: originalRecord?.notes ?? "")
        _dishes = State(initialValue: originalRecord?.dishes.map(MealDishDraft.init(dish:)) ?? [MealDishDraft()])
    }

    var body: some View {
        Form {
            Section("用餐地点") {
                Button {
                    isSelectingLocation = true
                } label: {
                    Label(locationLatitude == nil ? "地图选地址" : "重新选择地图地址", systemImage: "map")
                }
                TextField("地址（地图不可用时可手填）", text: $locationAddress, axis: .vertical)
                    .onChange(of: locationAddress) { _, newValue in
                        if newValue != confirmedMapAddress {
                            locationLatitude = nil
                            locationLongitude = nil
                        }
                    }
                if locationLatitude != nil, locationLongitude != nil {
                    Label("已保存地图坐标", systemImage: "location.fill")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                TextField("店名（可选）", text: $storeName)
            }

            Section("用餐时间") {
                DatePicker("日期和时间", selection: $consumedAt, displayedComponents: [.date, .hourAndMinute])
            }

            Section {
                ForEach($dishes) { $dish in
                    MealDishEditorRow(draft: $dish)
                        .padding(.vertical, 6)
                        .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
                }
                .onDelete(perform: deleteDishes)
                .onMove(perform: moveDishes)

                Button {
                    dishes.append(MealDishDraft())
                } label: {
                    Label("添加一道菜", systemImage: "plus.circle")
                }
            } header: {
                HStack {
                    Text("菜品")
                    Spacer()
                    if !dishes.isEmpty {
                        EditButton()
                            .font(.caption.weight(.semibold))
                    }
                }
            }

            Section("备注") {
                TextField("口味、同行的人或当时的心情", text: $notes, axis: .vertical)
            }
        }
        .scrollContentBackground(.hidden)
        .background(GanfanPalette.canvas)
        .tint(GanfanPalette.forest)
        .navigationTitle(storedRecord == nil ? "记录用餐" : "编辑用餐")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("取消") { dismiss() }
                    .disabled(isSaving)
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("保存", action: saveRecord)
                    .disabled(isSaving || !dishes.contains { !$0.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty })
            }
        }
        .sheet(isPresented: $isSelectingLocation) {
            NavigationStack {
                MapLocationPickerView(
                    initialAddress: locationAddress,
                    initialLatitude: locationLatitude,
                    initialLongitude: locationLongitude
                ) { selection in
                    if storeName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        storeName = selection.storeName
                    }
                    confirmedMapAddress = selection.address
                    locationAddress = selection.address
                    locationLatitude = selection.latitude
                    locationLongitude = selection.longitude
                }
            }
        }
        .alert("未能保存用餐记录", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("好", role: .cancel) { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "请重试。")
        }
    }

    private func deleteDishes(at offsets: IndexSet) {
        dishes.remove(atOffsets: offsets)
    }

    private func moveDishes(from source: IndexSet, to destination: Int) {
        dishes.move(fromOffsets: source, toOffset: destination)
    }

    private func saveRecord() {
        guard !isSaving else { return }
        isSaving = true

        Task { @MainActor in
            var newAssets: [PhotoAsset] = []
            do {
                var savedDishes: [MealDish] = []
                for draft in dishes {
                    let normalizedName = draft.name.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !normalizedName.isEmpty else { continue }

                    let photo: PhotoAsset?
                    if let photoData = draft.photoData {
                        let asset = try AppStoragePaths.photoStore.save(photoData, fileExtension: draft.photoExtension)
                        newAssets.append(asset)
                        photo = asset
                    } else if draft.photoRemoved {
                        photo = nil
                    } else {
                        photo = draft.originalPhoto
                    }
                    let nutrition = draft.nutritionName == normalizedName
                        ? (draft.nutrition ?? RoughNutritionEstimator.dish(name: normalizedName))
                        : RoughNutritionEstimator.dish(name: normalizedName)
                    savedDishes.append(try MealDish(id: draft.id, name: normalizedName,
                                                    photo: photo, nutrition: nutrition))
                }

                let record = try MealRecord(
                    id: originalRecord?.id ?? UUID(),
                    consumedAt: consumedAt,
                    storeName: storeName,
                    locationAddress: locationAddress,
                    latitude: locationLatitude,
                    longitude: locationLongitude,
                    dishes: savedDishes,
                    notes: notes
                )
                try persist(.meal(record), createdPhotoAssets: newAssets)

                let retainedPhotoIDs = Set(savedDishes.compactMap(\.photo).map(\.id))
                for oldPhoto in originalRecord?.dishes.compactMap(\.photo) ?? [] where !retainedPhotoIDs.contains(oldPhoto.id) {
                    try? AppStoragePaths.photoStore.remove(oldPhoto)
                }
                onSave?()
                dismiss()
            } catch {
                newAssets.forEach { try? AppStoragePaths.photoStore.remove($0) }
                if !newAssets.isEmpty {
                    PhotoStorageDiagnosticsStore().record(
                        stage: .photoWrite,
                        reason: PhotoStorageDiagnosticsStore.reason(for: error),
                        byteCount: newAssets.reduce(0) { $0 + $1.byteCount }
                    )
                }
                errorMessage = error.localizedDescription
                isSaving = false
            }
        }
    }

    private func persist(_ record: JournalRecord, createdPhotoAssets: [PhotoAsset]) throws {
        try JournalRecordCommitService.save(
            record,
            replacing: storedRecord,
            createdPhotoAssets: createdPhotoAssets,
            photoStore: AppStoragePaths.photoStore,
            into: modelContext
        )
    }

    private static func decodeMeal(_ storedRecord: StoredJournalRecord?) -> MealRecord? {
        guard let storedRecord, let decoded = try? storedRecord.decodeRecord(), case .meal(let meal) = decoded else {
            return nil
        }
        return meal
    }
}

private struct OptionChipPicker: View {
    let title: String
    let options: [String]
    @Binding var selection: String
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private var columns: [GridItem] {
        let minimumWidth: CGFloat = dynamicTypeSize >= .xxLarge ? 132 : 66
        return [GridItem(.adaptive(minimum: minimumWidth), alignment: .leading)]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.secondary)

            LazyVGrid(columns: columns, alignment: .leading, spacing: 8) {
                ForEach(options, id: \.self) { option in
                    let isSelected = selection == option
                    Button {
                        selection = option
                    } label: {
                        Text(option.isEmpty ? "未记录" : option)
                            .font(.subheadline.weight(isSelected ? .semibold : .regular))
                            .foregroundStyle(isSelected ? Color.white : GanfanPalette.ink)
                            .frame(maxWidth: .infinity)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 9)
                            .background(
                                isSelected ? GanfanPalette.forest : GanfanPalette.paleLeaf.opacity(0.55),
                                in: Capsule()
                            )
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(isSelected ? .isSelected : [])
                }
            }
        }
        .padding(.vertical, 5)
        .sensoryFeedback(.selection, trigger: selection)
    }
}

private struct MealDishDraft: Identifiable {
    let id: UUID
    var name: String
    let originalPhoto: PhotoAsset?
    var selectedPhoto: PhotosPickerItem?
    var photoData: Data?
    var photoExtension: String
    var photoRemoved: Bool
    var nutrition: NutritionSnapshot?
    var nutritionName: String

    init() {
        id = UUID()
        name = ""
        originalPhoto = nil
        selectedPhoto = nil
        photoData = nil
        photoExtension = "jpg"
        photoRemoved = false
        nutrition = nil
        nutritionName = ""
    }

    init(dish: MealDish) {
        id = dish.id
        name = dish.name
        originalPhoto = dish.photo
        selectedPhoto = nil
        photoData = nil
        photoExtension = dish.photo?.fileExtension ?? "jpg"
        photoRemoved = false
        nutrition = dish.nutrition
        nutritionName = dish.name
    }
}

private struct MealDishEditorRow: View {
    @Binding var draft: MealDishDraft
    @State private var savedPhotoData: Data?
    @State private var errorMessage: String?
    @State private var aiConfigured = false
    @State private var isRecognizing = false
    @State private var showUploadConfirmation = false

    var body: some View {
        let hasPhoto = draft.photoData != nil || (!draft.photoRemoved && savedPhotoData != nil)

        VStack(alignment: .leading, spacing: 8) {
            if let previewData = draft.photoData ?? (draft.photoRemoved ? nil : savedPhotoData),
               let image = UIImage(data: previewData) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(maxHeight: 150)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
            }

            PhotosPicker(selection: $draft.selectedPhoto, matching: .images) {
                Label(hasPhoto ? "更换菜品照片" : "添加菜品照片", systemImage: "photo")
            }

            TextField("菜品名称（必填）", text: $draft.name)

            if !draft.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                let nutrition = draft.nutritionName == draft.name && draft.nutrition != nil
                    ? draft.nutrition!
                    : RoughNutritionEstimator.dish(name: draft.name)
                VStack(alignment: .leading, spacing: 4) {
                    Text("\(nutrition.confidence.displayName) · \(Int(nutrition.energyKcal ?? 0)) kcal")
                        .font(.subheadline.weight(.semibold))
                    Text("蛋白质 \(Int(nutrition.proteinGrams ?? 0))g · 脂肪 \(Int(nutrition.fatGrams ?? 0))g · 碳水 \(Int(nutrition.carbohydrateGrams ?? 0))g")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(nutrition.assumptions)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            // Deliberately remove the entire entry point when AI is not configured.
            if aiConfigured && hasPhoto {
                Button {
                    showUploadConfirmation = true
                } label: {
                    Label(isRecognizing ? "正在分析照片…" : "AI 识别并估算营养", systemImage: "sparkles")
                }
                .disabled(isRecognizing)
            }

            if errorMessage != nil {
                Text(errorMessage ?? "")
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            if draft.photoData != nil || savedPhotoData != nil {
                Button("移除这张照片", role: .destructive) {
                    draft.photoRemoved = true
                    draft.photoData = nil
                    draft.selectedPhoto = nil
                    draft.nutrition = nil
                    draft.nutritionName = ""
                }
                .font(.caption)
            }
        }
        .onAppear { aiConfigured = AISettingsStore.isReady }
        .confirmationDialog("将菜品照片发送给您配置的 AI 服务商？",
                            isPresented: $showUploadConfirmation, titleVisibility: .visible) {
            Button("发送照片并识别") { Task { await recognizeFood() } }
            Button("取消", role: .cancel) {}
        } message: {
            Text("仅本次发送处理后的照片，服务商可能收费。营养结果为估算值，您可以更正菜名。")
        }
        .task(id: draft.selectedPhoto) {
            await loadSelectedPhoto()
        }
        .task {
            await loadSavedPhoto()
        }
    }

    private func loadSelectedPhoto() async {
        guard let selectedPhoto = draft.selectedPhoto else { return }
        do {
            draft.photoData = try await selectedPhoto.loadTransferable(type: Data.self)
            draft.photoExtension = selectedPhoto.supportedContentTypes.first?.preferredFilenameExtension ?? "jpg"
            draft.photoRemoved = false
            draft.nutrition = nil
            draft.nutritionName = ""
            errorMessage = nil
        } catch {
            draft.photoData = nil
            PhotoStorageDiagnosticsStore().record(stage: .photoSelection, reason: PhotoStorageDiagnosticsStore.reason(for: error))
            errorMessage = "读取照片失败：\(error.localizedDescription)"
        }
    }

    private func loadSavedPhoto() async {
        guard let originalPhoto = draft.originalPhoto else { return }
        do {
            savedPhotoData = try AppStoragePaths.photoStore.load(originalPhoto)
        } catch {
            PhotoStorageDiagnosticsStore().record(stage: .photoRead, reason: PhotoStorageDiagnosticsStore.reason(for: error), byteCount: originalPhoto.byteCount)
            errorMessage = "读取本机照片失败：\(error.localizedDescription)"
        }
    }
}
