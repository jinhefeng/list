import PhotosUI
import Photos
import CoreLocation
import ImageIO
import UniformTypeIdentifiers
import SwiftUI
import UIKit

private enum DrinkRecordFocusedField: Hashable {
    case drinkName
    case brandName
    case notes
}

private enum DrinkRecordSheet: Identifiable {
    case menu
    case map

    var id: Self { self }
}

struct DrinkRecordForm: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.journalSQLiteStore) private var library
    @FocusState private var focusedField: DrinkRecordFocusedField?

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
    @State private var menuCatalog: MenuCatalog?
    @State private var locationName: String
    @State private var locationAddress: String
    @State private var locationLatitude: Double?
    @State private var locationLongitude: Double?
    @State private var activeSheet: DrinkRecordSheet?
    @State private var notes: String
    @State private var selectedMenuDrink: MenuDrink?
    @State private var selectedCatalogBrand: MenuBrand?
    @State private var selectedPhoto: PhotosPickerItem?
    @State private var selectedPhotoData: Data?
    @State private var selectedPhotoPreview: UIImage?
    @State private var savedPhotoData: Data?
    @State private var savedPhotoPreview: UIImage?
    @State private var photoImportMessage: String?
    @State private var isImportingPhoto = false
    @State private var isNutritionDetailsExpanded = false
    @State private var photoExtension = "jpg"
    @State private var photoRemoved = false
    @State private var isSaving = false
    @State private var errorMessage: String?

    init(record: DrinkRecord? = nil, onSave: (() -> Void)? = nil) {
        self.onSave = onSave
        let originalRecord = record
        self.originalRecord = originalRecord
        let servingSelection = DrinkServingSelection(
            temperature: originalRecord?.temperature,
            ice: originalRecord?.ice,
            legacyServingOption: originalRecord?.temperature == nil && originalRecord?.ice == nil
                ? originalRecord?.servingOption
                : nil
        )
        let menuCatalog = Self.loadBundledCatalog()
        let selectedMenuDrink: MenuDrink?
        if let drinkID = originalRecord?.drinkID, !drinkID.isEmpty {
            selectedMenuDrink = menuCatalog?.drink(for: drinkID)
        } else {
            selectedMenuDrink = nil
        }

        _drinkName = State(initialValue: originalRecord?.drinkName ?? "")
        _brandName = State(initialValue: originalRecord?.brandName ?? "")
        _consumedAt = State(initialValue: originalRecord?.consumedAt ?? .now)
        _cupType = State(initialValue: originalRecord?.cupType ?? "")
        _sweetness = State(initialValue: Self.normalizedSweetness(originalRecord?.sweetness ?? ""))
        _temperature = State(initialValue: servingSelection.temperature)
        _ice = State(initialValue: servingSelection.ice)
        _globalCupSizes = State(initialValue: Self.loadGlobalCupSizes())
        _menuCatalog = State(initialValue: menuCatalog)
        _selectedMenuDrink = State(initialValue: selectedMenuDrink)
        _locationName = State(initialValue: originalRecord?.locationName ?? "")
        _locationAddress = State(initialValue: originalRecord?.locationAddress ?? "")
        _locationLatitude = State(initialValue: originalRecord?.latitude)
        _locationLongitude = State(initialValue: originalRecord?.longitude)
        _notes = State(initialValue: originalRecord?.notes ?? "")
    }

    private func brandLogo(for brandID: String, dimension: CGFloat) -> some View {
        let brand = menuCatalog?.brands.first(where: { $0.id == brandID })
        return GanfanBrandLogoIcon(
            assetName: brand?.logoAssetName,
            symbol: brand?.logoSymbol,
            imageID: brand?.logoImageID,
            dimension: dimension
        )
    }

    @ViewBuilder
    private var selectedMenuBrandLabel: some View {
        if let selectedMenuDrink,
           !selectedMenuDrink.brandName.isEmpty {
            HStack(spacing: 4) {
                brandLogo(for: selectedMenuDrink.brandID, dimension: 16)
                Text(selectedMenuDrink.brandName)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
        }
    }

    var body: some View {
        Form {
            Section {
                PhotoPickerWell(
                    selection: $selectedPhoto,
                    image: previewImage,
                    title: previewImage == nil ? "添加饮品照片" : "更换饮品照片",
                    detail: "可选",
                    compact: false,
                    isLoading: isImportingPhoto,
                    showsRemove: !photoRemoved && (selectedPhotoData != nil || savedPhotoData != nil),
                    removeStyle: .drink,
                    statusMessage: photoImportMessage,
                    onRemove: removeDrinkPhoto
                )
            } header: {
                formSectionTitle("照片")
            }

            Section {
                VStack(alignment: .leading, spacing: 0) {
                    HStack(spacing: 8) {
                        TextField("输入名称，自动匹配目录", text: $drinkName)
                            .textContentType(.none)
                            .focused($focusedField, equals: .drinkName)
                            .onChange(of: drinkName) { _, newValue in
                                guard let selectedMenuDrink,
                                      newValue.trimmingCharacters(in: .whitespacesAndNewlines) != selectedMenuDrink.name else { return }
                                self.selectedMenuDrink = nil
                                brandName = ""
                            }

                        if !drinkName.isEmpty {
                            Button(action: clearDrinkSelection) {
                                Image(systemName: "xmark.circle.fill")
                                    .font(.body)
                                    .foregroundStyle(.tertiary)
                                    .frame(width: 44, height: 44)
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("清除饮品名称")
                        }
                    }

                    if let selectedMenuDrink {
                        HStack(spacing: 6) {
                            Label("菜单已关联", systemImage: "checkmark.circle.fill")
                                .lineLimit(1)
                                .truncationMode(.tail)
                            selectedMenuBrandLabel
                                .layoutPriority(1)
                            Spacer(minLength: 4)
                            Text(selectedMenuDrink.status == "verified" ? "已核验" : "待核验")
                                .lineLimit(1)
                                .fixedSize(horizontal: true, vertical: false)
                        }
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(GanfanPalette.forest)
                        .frame(maxWidth: .infinity, minHeight: 20, alignment: .leading)
                    }
                }
                .listRowInsets(EdgeInsets(top: 2, leading: 16, bottom: 2, trailing: 16))
                .listRowSeparator(.hidden)

                if selectedMenuDrink == nil,
                   focusedField == .drinkName,
                   !drinkName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    if drinkSuggestions.isEmpty {
                        Label("可直接记录为自定义饮品", systemImage: "pencil.and.outline")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        VStack(alignment: .leading, spacing: 0) {
                            Text("匹配的菜单饮品")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                                .padding(.bottom, 6)

                            ForEach(drinkSuggestions) { drink in
                                Button {
                                    chooseMenuDrink(drink)
                                } label: {
                                    HStack(alignment: .center, spacing: 10) {
                                        VStack(alignment: .leading, spacing: 3) {
                                            Text(drink.name)
                                                .font(.subheadline.weight(.semibold))
                                                .foregroundStyle(.primary)
                                            HStack(spacing: 4) {
                                                brandLogo(for: drink.brandID, dimension: 14)
                                                Text(drink.brandName)
                                                    .font(.footnote)
                                                    .foregroundStyle(.secondary)
                                            }
                                        }
                                        Spacer(minLength: 8)
                                        Text(drink.status == "verified" ? "已核验" : "菜单")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .contentShape(Rectangle())
                                    .padding(.vertical, 8)
                                }
                                .buttonStyle(.plain)
                                if drink.id != drinkSuggestions.last?.id {
                                    Divider()
                                }
                            }
                        }
                        .padding(12)
                        .background(GanfanPalette.card, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }
                }

                if selectedMenuDrink == nil {
                    VStack(alignment: .leading, spacing: 0) {
                        TextField("品牌（可选）", text: $brandName)
                            .textContentType(.organizationName)
                            .focused($focusedField, equals: .brandName)
                            .onChange(of: brandName) { _, newValue in
                                guard let selectedCatalogBrand,
                                      Self.normalizedCatalogValue(newValue) != Self.normalizedCatalogValue(selectedCatalogBrand.name) else { return }
                                self.selectedCatalogBrand = nil
                            }

                        if let selectedCatalogBrand,
                           Self.normalizedCatalogValue(brandName) == Self.normalizedCatalogValue(selectedCatalogBrand.name) {
                            HStack(spacing: 5) {
                                Image(systemName: "checkmark.circle.fill")
                                brandLogo(for: selectedCatalogBrand.id, dimension: 14)
                                Text("已匹配目录品牌：\(selectedCatalogBrand.name)")
                                    .lineLimit(1)
                                    .truncationMode(.tail)
                            }
                            .font(.caption)
                            .foregroundStyle(GanfanPalette.forest)
                            .padding(.top, 4)
                        } else if focusedField == .brandName,
                                  !brandName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            if brandSuggestions.isEmpty {
                                Label("未匹配目录，可按自定义品牌记录", systemImage: "pencil.and.outline")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .padding(.top, 6)
                            } else {
                                VStack(alignment: .leading, spacing: 0) {
                                    Text("匹配的品牌")
                                        .font(.caption.weight(.semibold))
                                        .foregroundStyle(.secondary)
                                        .padding(.bottom, 6)

                                    ForEach(brandSuggestions) { brand in
                                        Button {
                                            chooseCatalogBrand(brand)
                                        } label: {
                                            HStack(spacing: 8) {
                                                brandLogo(for: brand.id, dimension: 20)
                                                Text(brand.name)
                                                    .font(.subheadline)
                                                    .foregroundStyle(.primary)
                                                    .lineLimit(1)
                                                Spacer(minLength: 8)
                                                if !brand.category.isEmpty {
                                                    Text(brand.category)
                                                        .font(.caption)
                                                        .foregroundStyle(.secondary)
                                                        .lineLimit(1)
                                                }
                                            }
                                            .frame(maxWidth: .infinity, alignment: .leading)
                                            .contentShape(Rectangle())
                                            .padding(.vertical, 8)
                                        }
                                        .buttonStyle(.plain)

                                        if brand.id != brandSuggestions.last?.id {
                                            Divider()
                                        }
                                    }
                                }
                                .padding(12)
                                .background(GanfanPalette.card, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                                .padding(.top, 6)
                            }
                        }
                    }
                }

                Button("浏览完整饮品目录", systemImage: "list.bullet") {
                    focusedField = nil
                    activeSheet = .menu
                }
                .font(.subheadline)
            } header: {
                formSectionTitle("喝的是什么")
            }

            Section {
                OptionChipPicker(title: "杯型", options: [""] + cupTypeOptions, selection: $cupType, onSelect: dismissDrinkNameFocus)
                OptionChipPicker(
                    title: "温度",
                    options: [""] + Self.temperatureChoices,
                    selection: temperatureChoiceBinding,
                    onSelect: dismissDrinkNameFocus,
                    minimumChipWidth: 84
                )
                OptionChipPicker(title: "甜度", options: [""] + sweetnessOptions, selection: $sweetness, onSelect: dismissDrinkNameFocus, minimumChipWidth: 108)
            } header: {
                formSectionTitle("这一杯的细节")
            }

            Section {
                DrinkNutritionQuickView(
                    nutrition: calculatedNutrition,
                    isExpanded: $isNutritionDetailsExpanded
                )
            } header: {
                formSectionTitle("营养快照")
            }

            Section {
                DatePicker("饮用时间", selection: $consumedAt, displayedComponents: [.date, .hourAndMinute])
                Button {
                    focusedField = nil
                    activeSheet = .map
                } label: {
                    Label(locationLatitude == nil ? "地图选地址" : "重新选择地图地址", systemImage: "map")
                }
                if !locationName.isEmpty {
                    LabeledContent("地点", value: locationName)
                }
                if !locationAddress.isEmpty {
                    LabeledContent("地址", value: locationAddress)
                }
                TextField("备注（可选）", text: $notes, axis: .vertical)
                    .focused($focusedField, equals: .notes)
                    .accessibilityHint("记录这杯饮品的口味或当时的心情")
            } header: {
                formSectionTitle("时间与地点")
            }
        }
        .scrollContentBackground(.hidden)
        .background {
            GanfanPalette.canvas
                .onTapGesture(perform: dismissDrinkNameFocus)
        }
        .tint(GanfanPalette.forest)
        .navigationTitle(originalRecord == nil ? "记录饮品" : "编辑饮品")
        .navigationBarTitleDisplayMode(.inline)
        .scrollDismissesKeyboard(.interactively)
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
            if newValue != "冰饮" {
                ice = ""
            }
        }
        .sheet(item: $activeSheet) { sheet in
            switch sheet {
            case .menu:
                NavigationStack {
                    MenuPickerView(catalog: menuCatalog) { drink in
                        chooseMenuDrink(drink)
                    }
                }
            case .map:
                MapLocationPickerSheet { selection in
                    locationName = selection.storeName
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

    private func formSectionTitle(_ title: LocalizedStringKey) -> some View {
        Text(title)
            .font(.caption.weight(.semibold))
            .textCase(nil)
            .foregroundStyle(GanfanPalette.leaf)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .onTapGesture(perform: dismissDrinkNameFocus)
    }

    private func dismissDrinkNameFocus() {
        if focusedField == .drinkName {
            focusedField = nil
        }
    }

    private func clearDrinkSelection() {
        if selectedMenuDrink != nil {
            brandName = ""
        }
        selectedMenuDrink = nil
        drinkName = ""
        focusedField = .drinkName
    }

    private func removeDrinkPhoto() {
        photoRemoved = true
        selectedPhotoData = nil
        selectedPhotoPreview = nil
        selectedPhoto = nil
        photoImportMessage = nil
        isImportingPhoto = false
    }

    private var previewImage: UIImage? {
        guard !photoRemoved else { return nil }
        return selectedPhotoPreview ?? savedPhotoPreview
    }

    private var drinkSuggestions: [MenuDrink] {
        let query = drinkName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty, selectedMenuDrink == nil, let menuCatalog else { return [] }
        return Array(menuCatalog.searchDrinks(query: query).prefix(5))
    }

    private var brandSuggestions: [MenuBrand] {
        let query = brandName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty, selectedCatalogBrand == nil, selectedMenuDrink == nil,
              let menuCatalog else { return [] }
        return Array(menuCatalog.searchBrands(query).prefix(5))
    }

    private func matchingCatalogBrand(named name: String) -> MenuBrand? {
        let query = Self.normalizedCatalogValue(name)
        guard !query.isEmpty else { return nil }
        return menuCatalog?.brands.first { brand in
            ([brand.name] + brand.aliases).contains {
                Self.normalizedCatalogValue($0) == query
            }
        }
    }

    private func matchingCatalogDrink(name: String, brandID: String, brandName: String) -> MenuDrink? {
        let nameKey = Self.normalizedCatalogValue(name)
        guard !nameKey.isEmpty else { return nil }
        let brandNameKey = Self.normalizedCatalogValue(brandName)
        return menuCatalog?.drinks.first { drink in
            guard Self.normalizedCatalogValue(drink.name) == nameKey else { return false }
            if !brandID.isEmpty {
                return drink.brandID == brandID
            }
            return Self.normalizedCatalogValue(drink.brandName) == brandNameKey
        }
    }

    private static func normalizedCatalogValue(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .filter { !$0.isWhitespace && !$0.isPunctuation }
    }

    private func chooseMenuDrink(_ drink: MenuDrink) {
        focusedField = nil
        selectedCatalogBrand = nil
        selectedMenuDrink = drink
        brandName = drink.brandName
        drinkName = drink.name
        if cupType.isEmpty, let menuCup = drink.cupTypes.first, cupTypeOptions.contains(menuCup) {
            cupType = menuCup
        }
    }

    private func chooseCatalogBrand(_ brand: MenuBrand) {
        selectedCatalogBrand = brand
        brandName = brand.name
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

    private var sweetnessOptions: [String] {
        var options = selectedMenuDrink?.sweetnessOptions
            .filter { !$0.isEmpty }
            .map(Self.normalizedSweetness) ?? []
        if options.isEmpty { options = ["不另外加糖", "三分糖", "五分糖", "七分糖", "全糖"] }
        var seen = Set<String>()
        options = options.filter { seen.insert($0).inserted }
        if !sweetness.isEmpty, !options.contains(sweetness) { options.append(sweetness) }
        return options
    }

    private static func normalizedSweetness(_ value: String) -> String {
        switch value {
        case "无糖": return "不另外加糖"
        case "微糖": return "三分糖"
        default: return value
        }
    }

    private static let temperatureChoices = ["去冰", "少冰", "正常冰", "常温", "温饮", "热饮"]
    private static let iceChoices = ["去冰", "少冰", "正常冰"]
    private static let directTemperatureChoices = ["常温", "温饮", "热饮"]

    private var temperatureChoiceBinding: Binding<String> {
        Binding(
            get: {
                if Self.iceChoices.contains(ice) { return ice }
                if ice == "多冰" { return "正常冰" }
                if Self.directTemperatureChoices.contains(temperature) { return temperature }
                return temperature == "冰饮" ? "正常冰" : ""
            },
            set: { choice in
                if Self.iceChoices.contains(choice) {
                    temperature = "冰饮"
                    ice = choice
                } else if Self.directTemperatureChoices.contains(choice) {
                    temperature = choice
                    ice = ""
                } else {
                    temperature = ""
                    ice = ""
                }
            }
        )
    }

    private var calculatedNutrition: NutritionSnapshot {
        if let originalRecord,
           originalRecord.brandName == brandName,
           originalRecord.drinkName == drinkName,
           originalRecord.cupType == cupType,
           originalRecord.sizeML == recordSizeML,
           Self.normalizedSweetness(originalRecord.sweetness) == sweetness {
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
           Self.normalizedSweetness(originalRecord.sweetness) == sweetness,
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

    private func loadSelectedPhoto() async {
        guard let selectedPhoto else { return }
        isImportingPhoto = true
        defer {
            if self.selectedPhoto == selectedPhoto {
                isImportingPhoto = false
            }
        }
        photoImportMessage = nil
        do {
            guard let data = try await selectedPhoto.loadTransferable(type: Data.self) else {
                throw PhotoSelectionError.emptyData
            }
            guard !Task.isCancelled else { return }
            let itemIdentifier = selectedPhoto.itemIdentifier
            let result = await Task.detached(priority: .utility) {
                DrinkPhotoImportResult.prepare(from: data, itemIdentifier: itemIdentifier)
            }.value
            guard !Task.isCancelled else { return }
            selectedPhotoData = data
            selectedPhotoPreview = result.previewData.flatMap(UIImage.init(data:))
            photoExtension = selectedPhoto.supportedContentTypes.first?.preferredFilenameExtension ?? "jpg"
            photoRemoved = false
            isImportingPhoto = false
            await applyPhotoMetadata(result.metadata)
        } catch {
            guard !Task.isCancelled else { return }
            selectedPhotoData = nil
            selectedPhotoPreview = nil
            PhotoStorageDiagnosticsStore().record(stage: .photoSelection, reason: PhotoStorageDiagnosticsStore.reason(for: error))
            errorMessage = "读取所选照片失败：\(error.localizedDescription)"
        }
    }

    private func applyPhotoMetadata(_ metadata: DrinkPhotoMetadata) async {
        if let capturedAt = metadata.capturedAt {
            consumedAt = capturedAt
        }

        guard let latitude = metadata.latitude, let longitude = metadata.longitude else {
            photoImportMessage = metadata.capturedAt == nil ? nil : "拍摄时间已填入"
            return
        }

        locationLatitude = latitude
        locationLongitude = longitude
        locationName = ""
        locationAddress = ""
        do {
            let placemark = try await CLGeocoder().reverseGeocodeLocation(
                CLLocation(latitude: latitude, longitude: longitude)
            ).first
            guard !Task.isCancelled else { return }
            if let placemark {
                locationName = placemark.name ?? ""
                locationAddress = MapLocationPickerView.address(from: placemark)
            }
        } catch {
            guard !Task.isCancelled else { return }
        }

        let hasAddress = !locationAddress.isEmpty || !locationName.isEmpty
        let hasTime = metadata.capturedAt != nil
        photoImportMessage = hasAddress
            ? (hasTime ? "时间与地点已填入" : "地点已填入")
            : (hasTime ? "时间与照片坐标已读取" : "照片坐标已读取")
    }

    private func loadSavedPhoto() async {
        guard let photo = originalRecord?.photo else { return }
        do {
            let photoStore = AppStoragePaths.photoStore
            let loaded = try await Task.detached(priority: .utility) {
                let data = try photoStore.load(photo)
                return StoredPhotoPreview(data: data, previewData: DrinkPhotoPreview.thumbnailData(from: data))
            }.value
            savedPhotoData = loaded.data
            savedPhotoPreview = loaded.previewData.flatMap(UIImage.init(data:))
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
            var previousCatalogState: MenuCatalogUserState?
            do {
                let photo: PhotoAsset?
                if let selectedPhotoData {
                    let photoStore = AppStoragePaths.photoStore
                    let fileExtension = photoExtension
                    let saved = try await Task.detached(priority: .utility) {
                        try photoStore.save(selectedPhotoData, fileExtension: fileExtension)
                    }.value
                    newAsset = saved
                    photo = saved
                } else if photoRemoved {
                    photo = nil
                } else {
                    photo = originalRecord?.photo
                }

                let cleanedBrandName = brandName.trimmingCharacters(in: .whitespacesAndNewlines)
                let cleanedDrinkName = drinkName.trimmingCharacters(in: .whitespacesAndNewlines)
                let selectedMenuIsCurrent = selectedMenuDrink.map {
                    Self.normalizedCatalogValue($0.brandName) == Self.normalizedCatalogValue(cleanedBrandName)
                        && Self.normalizedCatalogValue($0.name) == Self.normalizedCatalogValue(cleanedDrinkName)
                } ?? false
                let selectedBrandIsCurrent = selectedCatalogBrand.map {
                    Self.normalizedCatalogValue($0.name) == Self.normalizedCatalogValue(cleanedBrandName)
                } ?? false
                let existingSelectionIsCurrent = originalRecord.map {
                    Self.normalizedCatalogValue($0.brandName) == Self.normalizedCatalogValue(cleanedBrandName)
                        && Self.normalizedCatalogValue($0.drinkName) == Self.normalizedCatalogValue(cleanedDrinkName)
                } ?? false
                let matchedBrand = selectedBrandIsCurrent
                    ? selectedCatalogBrand
                    : matchingCatalogBrand(named: cleanedBrandName)
                let inheritedBrandID = existingSelectionIsCurrent
                    ? originalRecord?.brandID.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                    : ""
                let newLocalBrandID = !cleanedBrandName.isEmpty && matchedBrand == nil && inheritedBrandID.isEmpty
                    ? "local-brand-\(UUID().uuidString)"
                    : ""
                let brandID = selectedMenuIsCurrent
                    ? selectedMenuDrink?.brandID ?? ""
                    : (selectedBrandIsCurrent
                        ? selectedCatalogBrand?.id ?? ""
                        : (!inheritedBrandID.isEmpty ? inheritedBrandID : (matchedBrand?.id ?? newLocalBrandID)))
                let resolvedBrandName = selectedMenuIsCurrent
                    ? selectedMenuDrink?.brandName ?? cleanedBrandName
                    : (matchedBrand?.name ?? cleanedBrandName)
                let matchingDrink = matchingCatalogDrink(
                    name: cleanedDrinkName,
                    brandID: brandID,
                    brandName: resolvedBrandName
                )
                let originalDrinkID = existingSelectionIsCurrent
                    ? originalRecord?.drinkID.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                    : ""
                let shouldSaveCustomDrink = (selectedMenuIsCurrent && selectedMenuDrink?.custom == true)
                    || (!selectedMenuIsCurrent && (matchingDrink == nil || matchingDrink?.custom == true))
                let drinkID: String
                if selectedMenuIsCurrent {
                    drinkID = selectedMenuDrink?.id ?? ""
                } else if let matchingDrink {
                    drinkID = matchingDrink.id
                } else if !originalDrinkID.isEmpty {
                    drinkID = originalDrinkID
                } else if shouldSaveCustomDrink {
                    drinkID = "local-drink-\(UUID().uuidString)"
                } else {
                    drinkID = ""
                }
                let nutrition = calculatedNutrition
                let recordSize = recordSizeML

                let record = try DrinkRecord(
                    id: originalRecord?.id ?? UUID(),
                    consumedAt: consumedAt,
                    brandID: brandID,
                    brandName: resolvedBrandName,
                    drinkID: drinkID,
                    drinkName: cleanedDrinkName,
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

                if shouldSaveCustomDrink {
                    previousCatalogState = try saveCustomDrinkToCatalog(
                        id: drinkID,
                        brandID: brandID,
                        brandName: resolvedBrandName,
                        name: cleanedDrinkName,
                        cupType: cupType,
                        sizeML: recordSize,
                        sweetness: sweetness
                    )
                }
                try persist(.drink(record), createdPhotoAssets: newAsset.map { [$0] } ?? [])
                if previousCatalogState != nil {
                    BackupChangeTracker().markChanged()
                }

                if let oldPhoto = originalRecord?.photo, oldPhoto != photo {
                    try? AppStoragePaths.photoStore.remove(oldPhoto)
                }
                onSave?()
                dismiss()
            } catch {
                if let previousCatalogState {
                    try? MenuCatalogRepository().saveUserState(previousCatalogState)
                    menuCatalog = Self.loadBundledCatalog()
                }
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

    private func saveCustomDrinkToCatalog(
        id: String,
        brandID: String,
        brandName: String,
        name: String,
        cupType: String,
        sizeML: Int?,
        sweetness: String
    ) throws -> MenuCatalogUserState {
        let repository = MenuCatalogRepository()
        let previousState = try repository.loadUserState()
        let previousDrink = menuCatalog?.drinks.first(where: { $0.id == id })
            ?? previousState.drinks.first(where: { $0.id == id })
        let currentBrand = menuCatalog?.brands.first(where: { $0.id == brandID })
            ?? previousState.brands.first(where: { $0.id == brandID })

        var brands = previousState.brands
        if !brandID.isEmpty,
           currentBrand == nil,
           !brandName.isEmpty,
           !brands.contains(where: { $0.id == brandID }) {
            brands.append(MenuBrand(
                id: brandID,
                name: brandName,
                category: "自定义",
                source: "用户记录",
                sourceName: "用户记录",
                updatedAt: Self.catalogToday,
                status: "pending",
                localOverride: true
            ))
        }

        let cleanedCupType = cupType.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanedSweetness = sweetness.trimmingCharacters(in: .whitespacesAndNewlines)
        let cupTypes = Self.uniqueCatalogValues((previousDrink?.cupTypes ?? []) + [cleanedCupType])
        let sweetnessOptions = Self.uniqueCatalogValues((previousDrink?.sweetnessOptions ?? []) + [cleanedSweetness])
        let sizesML = Array(Set((previousDrink?.sizesML ?? []) + (sizeML.map { [$0] } ?? []))).sorted()
        var cupSizes = previousDrink?.cupSizes ?? []
        if !cleanedCupType.isEmpty, let sizeML, sizeML > 0 {
            cupSizes.removeAll { $0.cupType == cleanedCupType }
            cupSizes.append(MenuCupSize(cupType: cleanedCupType, sizeML: sizeML))
        }

        let entry = MenuEntry(
            scope: "brand",
            status: previousDrink?.status ?? "pending",
            sourceType: "user_record",
            sourceName: "用户记录",
            cupTypes: cupTypes,
            cupSizes: cupSizes,
            sizesML: sizesML,
            sweetnessOptions: sweetnessOptions,
            servingOptions: previousDrink?.servingOptions ?? []
        )
        let updatedDrink = MenuDrink(
            id: id,
            legacyIDs: previousDrink?.legacyIDs ?? [],
            brandID: brandID,
            brandName: brandName,
            name: name,
            aliases: previousDrink?.aliases ?? [],
            category: previousDrink?.category ?? currentBrand?.category ?? "自定义饮品",
            source: "用户记录",
            sourceType: "user_record",
            sourceName: "用户记录",
            updatedAt: Self.catalogToday,
            status: previousDrink?.status ?? "pending",
            active: previousDrink?.active ?? true,
            cupTypes: cupTypes,
            cupSizes: cupSizes,
            sizesML: sizesML,
            sweetnessOptions: sweetnessOptions,
            servingOptions: previousDrink?.servingOptions ?? [],
            nutritionPerUnit: previousDrink?.nutritionPerUnit,
            nutritionVariants: previousDrink?.nutritionVariants ?? [],
            menuEntries: (previousDrink?.menuEntries.filter { $0.scope != "brand" } ?? []) + [entry],
            localOverride: true,
            custom: true
        )

        var drinks = previousState.drinks.filter { $0.id != id }
        drinks.append(updatedDrink)
        let updatedState = MenuCatalogUserState(
            brands: brands,
            drinks: drinks,
            deletedDrinkIDs: previousState.deletedDrinkIDs.subtracting([id] + (previousDrink?.legacyIDs ?? [])),
            globalCupSizes: previousState.globalCupSizes
        )
        try repository.saveUserState(updatedState)
        menuCatalog = Self.loadBundledCatalog()
        return previousState
    }

    private static var catalogToday: String {
        ISO8601DateFormatter().string(from: .now).prefix(10).description
    }

    private static func uniqueCatalogValues(_ values: [String]) -> [String] {
        var result: [String] = []
        for value in values {
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty, !result.contains(trimmed) else { continue }
            result.append(trimmed)
        }
        return result
    }

    private func persist(_ record: JournalRecord, createdPhotoAssets: [PhotoAsset]) throws {
        guard let library else { throw JournalSQLiteStoreError.cannotOpen("资料库尚未就绪") }
        try JournalRecordCommitService.save(
            record,
            replacing: originalRecord?.id,
            createdPhotoAssets: createdPhotoAssets,
            photoStore: AppStoragePaths.photoStore,
            into: library
        )
    }

    private static func loadBundledCatalog() -> MenuCatalog? {
        guard let url = Bundle.main.url(forResource: "catalog", withExtension: "json"),
              let data = try? Data(contentsOf: url) else {
            return nil
        }
        guard let bundled = try? MenuCatalog.decode(data) else { return nil }
        return try? MenuCatalogRepository().catalog(from: bundled)
    }

    private static func loadGlobalCupSizes() -> [MenuCupSize] {
        (try? MenuCatalogRepository().loadUserState().globalCupSizes) ?? MenuCatalogUserState.defaultCupSizes
    }

    private enum PhotoSelectionError: LocalizedError {
        case emptyData

        var errorDescription: String? { "照片没有返回图像数据。" }
    }
}

private struct DrinkPhotoMetadata: Sendable {
    let capturedAt: Date?
    let latitude: Double?
    let longitude: Double?

    static func read(from data: Data, itemIdentifier: String?) -> DrinkPhotoMetadata {
        var capturedAt: Date?
        var latitudeValue: Double?
        var longitudeValue: Double?

        if let source = CGImageSourceCreateWithData(data as CFData, nil),
           let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any] {
            let exif = properties[kCGImagePropertyExifDictionary] as? [CFString: Any] ?? [:]
            let tiff = properties[kCGImagePropertyTIFFDictionary] as? [CFString: Any] ?? [:]
            let dateString = (exif[kCGImagePropertyExifDateTimeOriginal] as? String)
                ?? (exif[kCGImagePropertyExifDateTimeDigitized] as? String)
                ?? (tiff[kCGImagePropertyTIFFDateTime] as? String)
            let offset = (exif[kCGImagePropertyExifOffsetTimeOriginal] as? String)
                ?? (exif[kCGImagePropertyExifOffsetTimeDigitized] as? String)
                ?? (exif[kCGImagePropertyExifOffsetTime] as? String)
            capturedAt = parseDate(dateString, offset: offset)

            if let gps = properties[kCGImagePropertyGPSDictionary] as? [CFString: Any],
               let latitude = (gps[kCGImagePropertyGPSLatitude] as? NSNumber)?.doubleValue,
               let longitude = (gps[kCGImagePropertyGPSLongitude] as? NSNumber)?.doubleValue {
                let latitudeRef = gps[kCGImagePropertyGPSLatitudeRef] as? String
                let longitudeRef = gps[kCGImagePropertyGPSLongitudeRef] as? String
                let signedLatitude = latitudeRef?.uppercased() == "S" ? -latitude : latitude
                let signedLongitude = longitudeRef?.uppercased() == "W" ? -longitude : longitude
                if CLLocationCoordinate2DIsValid(CLLocationCoordinate2D(latitude: signedLatitude, longitude: signedLongitude)) {
                    latitudeValue = signedLatitude
                    longitudeValue = signedLongitude
                }
            }
        }

        if let itemIdentifier,
           [.authorized, .limited].contains(PHPhotoLibrary.authorizationStatus(for: .readWrite)) {
            let assets = PHAsset.fetchAssets(withLocalIdentifiers: [itemIdentifier], options: nil)
            if let asset = assets.firstObject {
                capturedAt = capturedAt ?? asset.creationDate
                if latitudeValue == nil, let coordinate = asset.location?.coordinate {
                    latitudeValue = coordinate.latitude
                    longitudeValue = coordinate.longitude
                }
            }
        }

        return DrinkPhotoMetadata(capturedAt: capturedAt, latitude: latitudeValue, longitude: longitudeValue)
    }

    private static func parseDate(_ value: String?, offset: String?) -> Date? {
        guard let value else { return nil }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.dateFormat = "yyyy:MM:dd HH:mm:ss"
        if let secondsFromGMT = parseOffset(offset) {
            formatter.timeZone = TimeZone(secondsFromGMT: secondsFromGMT)
        } else {
            formatter.timeZone = .current
        }
        return formatter.date(from: value)
    }

    private static func parseOffset(_ value: String?) -> Int? {
        guard let value, !value.isEmpty else { return nil }
        if value == "Z" { return 0 }
        let compact = value.replacingOccurrences(of: ":", with: "")
        guard compact.count == 5,
              let hours = Int(compact.dropFirst().prefix(2)),
              let minutes = Int(compact.suffix(2)),
              (0...23).contains(hours),
              (0...59).contains(minutes) else { return nil }
        let direction = compact.first == "-" ? -1 : 1
        return direction * (hours * 3600 + minutes * 60)
    }
}

private struct DrinkPhotoImportResult: Sendable {
    let previewData: Data?
    let metadata: DrinkPhotoMetadata

    static func prepare(from data: Data, itemIdentifier: String?) -> DrinkPhotoImportResult {
        DrinkPhotoImportResult(
            previewData: DrinkPhotoPreview.thumbnailData(from: data),
            metadata: DrinkPhotoMetadata.read(from: data, itemIdentifier: itemIdentifier)
        )
    }
}

private struct StoredPhotoPreview: Sendable {
    let data: Data
    let previewData: Data?
}

private enum DrinkPhotoPreview {
    static func thumbnailData(from data: Data) -> Data? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: 1_200,
            kCGImageSourceShouldCacheImmediately: true
        ]
        guard let thumbnail = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            return nil
        }

        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            output as CFMutableData,
            UTType.jpeg.identifier as CFString,
            1,
            nil
        ) else {
            return nil
        }
        CGImageDestinationAddImage(
            destination,
            thumbnail,
            [kCGImageDestinationLossyCompressionQuality: 0.82] as CFDictionary
        )
        guard CGImageDestinationFinalize(destination) else { return nil }
        return output as Data
    }
}

struct MealRecordForm: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.journalSQLiteStore) private var library

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

    init(record: MealRecord? = nil, onSave: (() -> Void)? = nil) {
        self.onSave = onSave
        let originalRecord = record
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
                    MealDishEditorRow(draft: $dish) {
                        let removedID = dish.id
                        dishes.removeAll { $0.id == removedID }
                    }
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
        .navigationTitle(originalRecord == nil ? "记录用餐" : "编辑用餐")
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
            MapLocationPickerSheet { selection in
                if storeName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    storeName = selection.storeName
                }
                confirmedMapAddress = selection.address
                locationAddress = selection.address
                locationLatitude = selection.latitude
                locationLongitude = selection.longitude
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
        guard let library else { throw JournalSQLiteStoreError.cannotOpen("资料库尚未就绪") }
        try JournalRecordCommitService.save(
            record,
            replacing: originalRecord?.id,
            createdPhotoAssets: createdPhotoAssets,
            photoStore: AppStoragePaths.photoStore,
            into: library
        )
    }
}

private struct DrinkNutritionQuickView: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    let nutrition: NutritionSnapshot
    @Binding var isExpanded: Bool

    var body: some View {
        GanfanCard {
            VStack(alignment: .leading, spacing: GanfanSpacing.mediumSmall) {
                metrics

                Label(nutrition.confidence.displayName, systemImage: "info.circle")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Divider()
                    .overlay(GanfanPalette.leaf.opacity(0.14))

                DisclosureGroup(isExpanded: $isExpanded) {
                    detailContent
                } label: {
                    Text("详细数据与来源")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(GanfanPalette.ink)
                }
            }
        }
        .listRowBackground(Color.clear)
        .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 8, trailing: 0))
        .listRowSeparator(.hidden)
        .accessibilityElement(children: .contain)
    }

    @ViewBuilder
    private var metrics: some View {
        if dynamicTypeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: 14) {
                metric("能量", amount: nutrition.energyKcal, unit: "kcal")
                metric("糖", amount: nutrition.sugarGrams, unit: "g")
                metric("咖啡因", amount: nutrition.caffeineMilligrams, unit: "mg")
            }
        } else {
            HStack(alignment: .top, spacing: 10) {
                metric("能量", amount: nutrition.energyKcal, unit: "kcal")
                metric("糖", amount: nutrition.sugarGrams, unit: "g")
                metric("咖啡因", amount: nutrition.caffeineMilligrams, unit: "mg")
            }
        }
    }

    private func metric(_ title: String, amount: Double?, unit: String) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title)
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(displayValue(amount) ?? "—")
                    .font(.system(.title3, design: .rounded, weight: .semibold))
                    .monospacedDigit()
                    .foregroundStyle(GanfanPalette.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                if amount != nil {
                    Text(unit)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            .lineLimit(1)
            .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(title)，\(amount == nil ? "暂无数据" : "\(displayValue(amount) ?? "") \(unit)")")
    }

    private var detailContent: some View {
        VStack(alignment: .leading, spacing: 8) {
            nutritionValue("蛋白质" + roughSuffix(for: "proteinGrams"), amount: nutrition.proteinGrams, unit: "g")
            nutritionValue("脂肪" + roughSuffix(for: "fatGrams"), amount: nutrition.fatGrams, unit: "g")
            nutritionValue("碳水化合物" + roughSuffix(for: "carbohydrateGrams"), amount: nutrition.carbohydrateGrams, unit: "g")
            if !nutrition.assumptions.isEmpty {
                Text(nutrition.assumptions)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if !nutrition.source.isEmpty {
                Text("来源：\(nutrition.source)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let sourceURL = nutrition.sourceURL,
               let url = URL(string: sourceURL) {
                Link("查看来源链接", destination: url)
                    .font(.caption)
            }
        }
        .padding(.top, 8)
    }

    private func nutritionValue(_ title: String, amount: Double?, unit: String) -> some View {
        LabeledContent(title, value: amount.map {
            "\($0.formatted(.number.precision(.fractionLength(0...1)))) \(unit)"
        } ?? "暂无数据")
    }

    private func displayValue(_ amount: Double?) -> String? {
        amount?.formatted(.number.precision(.fractionLength(0...1)))
    }

    private func roughSuffix(for metric: String) -> String {
        nutrition.metricSources[metric] == "rough" ? "（粗估）" : ""
    }
}

private struct OptionChipPicker: View {
    let title: String
    let options: [String]
    @Binding var selection: String
    let onSelect: () -> Void
    var minimumChipWidth: CGFloat = 66
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private var columns: [GridItem] {
        let minimumWidth: CGFloat
        if dynamicTypeSize.isAccessibilitySize {
            minimumWidth = 180
        } else if dynamicTypeSize >= .xxLarge {
            minimumWidth = max(minimumChipWidth, 132)
        } else {
            minimumWidth = minimumChipWidth
        }
        return [GridItem(.adaptive(minimum: minimumWidth), alignment: .leading)]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(title)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.secondary)
                Spacer()
                if !selection.isEmpty {
                    Button("清除") {
                        selection = ""
                        onSelect()
                    }
                    .font(.caption)
                    .foregroundStyle(GanfanPalette.leaf)
                    .buttonStyle(.plain)
                }
            }

            LazyVGrid(columns: columns, alignment: .leading, spacing: 8) {
                ForEach(options.filter { !$0.isEmpty }, id: \.self) { option in
                    let isSelected = selection == option
                    Button {
                        selection = option
                        onSelect()
                    } label: {
                        Text(option)
                            .font(.subheadline.weight(isSelected ? .semibold : .regular))
                            .lineLimit(1)
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

private enum PhotoRemoveStyle {
    case drink
    case meal
}

private struct PhotoPickerWell: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var isShowingPicker = false
    @Binding var selection: PhotosPickerItem?
    let image: UIImage?
    let title: String
    let detail: String
    var compact = false
    var isLoading = false
    var showsRemove = false
    var removeStyle: PhotoRemoveStyle = .meal
    var statusMessage: String?
    var onRemove: (() -> Void)?

    private var usesCompactSquare: Bool {
        compact && !dynamicTypeSize.isAccessibilitySize
    }

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Button {
                isShowingPicker = true
            } label: {
                photoContent
                    .background(GanfanPalette.card)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay(alignment: .topLeading) {
                        if isLoading {
                            HStack(spacing: 6) {
                                ProgressView()
                                    .controlSize(.small)
                                Text("读取中")
                                    .font(.caption)
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 7)
                            .background(.regularMaterial, in: Capsule())
                            .padding(10)
                        }
                    }
                    .overlay(alignment: .bottomLeading) {
                        if let statusMessage {
                            Label(statusMessage, systemImage: "checkmark.circle.fill")
                                .font(.caption)
                                .lineLimit(1)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .background(.regularMaterial, in: Capsule())
                                .padding(10)
                        }
                    }
                    .overlay {
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .strokeBorder(
                                GanfanPalette.ink.opacity(0.18),
                                style: StrokeStyle(lineWidth: 1, dash: [5, 4])
                            )
                    }
                    .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
            .buttonStyle(.plain)
            .photosPicker(isPresented: $isShowingPicker, selection: $selection, matching: .images)
            .accessibilityLabel(title)
            .accessibilityHint(isLoading ? "正在读取照片" : detail)

            if showsRemove, let onRemove {
                Button(role: .destructive, action: onRemove) {
                    removeMark
                }
                .buttonStyle(.plain)
                .accessibilityLabel(removeAccessibilityLabel)
                .padding(4)
            }
        }
    }

    @ViewBuilder
    private var photoContent: some View {
        if let image {
            if usesCompactSquare {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 96, height: 96)
                    .clipped()
            } else {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: .infinity, maxHeight: 360)
                    .frame(minHeight: 190)
            }
        } else if usesCompactSquare {
            VStack(spacing: 5) {
                Image(systemName: "plus")
                    .font(.title3.weight(.medium))
                Text("添加照片")
                    .font(.caption.weight(.medium))
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(6)
            .frame(width: 96, height: 96)
        } else {
            fullWidthPlaceholder
        }
    }

    @ViewBuilder
    private var removeMark: some View {
        switch removeStyle {
        case .drink:
            Label("移除", systemImage: "xmark")
                .font(.caption.weight(.semibold))
                .foregroundStyle(Color(uiColor: .systemRed))
                .padding(.horizontal, 11)
                .frame(minHeight: 36)
                .background(.regularMaterial, in: Capsule())
                .overlay {
                    Capsule()
                        .strokeBorder(GanfanPalette.leaf.opacity(0.2), lineWidth: 1)
                }
                .frame(minWidth: 44, minHeight: 44)
                .contentShape(Capsule())
        case .meal:
            Image(systemName: "xmark")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(Color(uiColor: .systemRed))
                .frame(width: 27, height: 27)
                .background(GanfanPalette.card, in: Circle())
                .overlay {
                    Circle()
                        .strokeBorder(GanfanPalette.leaf.opacity(0.24), lineWidth: 1)
                }
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
    }

    private var removeAccessibilityLabel: String {
        switch removeStyle {
        case .drink: "移除饮品照片"
        case .meal: "移除菜品照片"
        }
    }

    private var fullWidthPlaceholder: some View {
        VStack(spacing: 8) {
            Image(systemName: "plus")
                .font(.title2.weight(.medium))
                .foregroundStyle(GanfanPalette.forest)
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.primary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity)
        .padding(16)
        .frame(minHeight: compact ? 150 : 190)
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
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Binding var draft: MealDishDraft
    let onRemove: () -> Void
    @State private var savedPhotoData: Data?
    @State private var errorMessage: String?
    @State private var aiConfigured = false
    @State private var isRecognizing = false
    @State private var showUploadConfirmation = false

    var body: some View {
        let imageData = draft.photoData ?? (draft.photoRemoved ? nil : savedPhotoData)
        let image = imageData.flatMap { UIImage(data: $0) }

        Group {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 10) {
                    photoPicker(image: image)
                    dishFields
                }
            } else {
                HStack(alignment: .top, spacing: 12) {
                    photoPicker(image: image)
                    dishFields
                }
            }
        }
        .task(id: draft.selectedPhoto) {
            await loadSelectedPhoto()
        }
        .task {
            await loadSavedPhoto()
        }
        .onAppear { aiConfigured = AISettingsStore.isReady }
        .confirmationDialog("将菜品照片发送给您配置的 AI 服务商？",
                            isPresented: $showUploadConfirmation, titleVisibility: .visible) {
            Button("发送照片并识别") { Task { await recognizeFood() } }
            Button("取消", role: .cancel) {}
        } message: {
            Text("仅本次发送处理后的照片，服务商可能收费。营养结果为估算值，您可以更正菜名。")
        }
    }

    private var hasPhoto: Bool {
        draft.photoData != nil || (!draft.photoRemoved && savedPhotoData != nil)
    }

    private var dishFields: some View {
        VStack(alignment: .leading, spacing: 8) {
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

            if aiConfigured && hasPhoto {
                Button {
                    showUploadConfirmation = true
                } label: {
                    Label(isRecognizing ? "正在分析照片…" : "AI 识别并估算营养", systemImage: "sparkles")
                }
                .disabled(isRecognizing)
            }

            if let errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
            Button("移除这道菜", role: .destructive, action: onRemove)
                .font(.footnote)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func photoPicker(image: UIImage?) -> some View {
        PhotoPickerWell(
            selection: $draft.selectedPhoto,
            image: image,
            title: image == nil ? "添加菜品照片" : "更换菜品照片",
            detail: "可选",
            compact: true,
            showsRemove: hasPhoto,
            removeStyle: .meal,
            onRemove: removeDishPhoto
        )
    }

    private func removeDishPhoto() {
        draft.photoRemoved = true
        draft.photoData = nil
        draft.selectedPhoto = nil
        draft.nutrition = nil
        draft.nutritionName = ""
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
        guard let originalPhoto = draft.originalPhoto else { return }
        do {
            savedPhotoData = try AppStoragePaths.photoStore.load(originalPhoto)
        } catch {
            PhotoStorageDiagnosticsStore().record(stage: .photoRead, reason: PhotoStorageDiagnosticsStore.reason(for: error), byteCount: originalPhoto.byteCount)
            errorMessage = "读取本机照片失败：\(error.localizedDescription)"
        }
    }
}
