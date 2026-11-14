import CoreLocation
import ImageIO
import PhotosUI
import SwiftData
import SwiftUI
import UIKit

private enum DrinkRecordFocusedField: Hashable {
    case drinkName
    case brandName
    case notes
}

private struct DrinkNameFieldFrameKey: PreferenceKey {
    static var defaultValue: CGRect { .zero }

    static func reduce(value: inout CGRect, nextValue: () -> CGRect) {
        value = nextValue()
    }
}

private struct PhotoCaptureMetadata {
    let date: Date?
    let latitude: Double?
    let longitude: Double?
}

private enum PhotoCaptureMetadataReader {
    static func read(from data: Data) -> PhotoCaptureMetadata? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [String: Any] else {
            return nil
        }

        let exif = properties[kCGImagePropertyExifDictionary as String] as? [String: Any] ?? [:]
        let tiff = properties[kCGImagePropertyTIFFDictionary as String] as? [String: Any] ?? [:]
        let gps = properties[kCGImagePropertyGPSDictionary as String] as? [String: Any] ?? [:]

        let dateTexts = [
            exif[kCGImagePropertyExifDateTimeOriginal as String] as? String,
            exif[kCGImagePropertyExifDateTimeDigitized as String] as? String,
            tiff[kCGImagePropertyTIFFDateTime as String] as? String
        ].compactMap { $0 }
        let offset = exif[kCGImagePropertyExifOffsetTimeOriginal as String] as? String
        let date = dateTexts.lazy.compactMap { parseDate($0, offset: offset) }.first

        let latitude = coordinate(
            gps[kCGImagePropertyGPSLatitude as String] as? NSNumber,
            reference: gps[kCGImagePropertyGPSLatitudeRef as String] as? String,
            negativeReference: "S",
            limit: 90
        )
        let longitude = coordinate(
            gps[kCGImagePropertyGPSLongitude as String] as? NSNumber,
            reference: gps[kCGImagePropertyGPSLongitudeRef as String] as? String,
            negativeReference: "W",
            limit: 180
        )

        guard date != nil || (latitude != nil && longitude != nil) else { return nil }
        return PhotoCaptureMetadata(date: date, latitude: latitude, longitude: longitude)
    }

    private static func coordinate(_ value: NSNumber?, reference: String?, negativeReference: String, limit: Double) -> Double? {
        guard let value else { return nil }
        var coordinate = value.doubleValue
        guard coordinate.isFinite, abs(coordinate) <= limit else { return nil }
        if reference?.uppercased() == negativeReference { coordinate = -abs(coordinate) }
        return coordinate
    }

    private static func parseDate(_ value: String, offset: String?) -> Date? {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.isLenient = false

        guard let offset = normalizedOffset(offset) else {
            formatter.dateFormat = "yyyy:MM:dd HH:mm:ss"
            formatter.timeZone = .current
            return formatter.date(from: value)
        }

        formatter.dateFormat = "yyyy:MM:dd HH:mm:ssXXXXX"
        formatter.timeZone = .current
        return formatter.date(from: value + offset)
    }

    private static func normalizedOffset(_ offset: String?) -> String? {
        guard let offset = offset?.trimmingCharacters(in: .whitespacesAndNewlines), !offset.isEmpty else { return nil }
        if offset == "Z" { return offset }
        let digits = offset.filter(\.isNumber)
        let sign = offset.hasPrefix("-") ? "-" : "+"
        switch digits.count {
        case 2:
            return "\(sign)\(digits):00"
        case 4:
            return "\(sign)\(digits.prefix(2)):\(digits.suffix(2))"
        default:
            return offset
        }
    }
}

struct DrinkRecordForm: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @FocusState private var focusedField: DrinkRecordFocusedField?
    @State private var drinkNameFieldFrame = CGRect.zero

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
    @State private var menuCatalog: MenuCatalog?
    @State private var locationName: String
    @State private var locationAddress: String
    @State private var locationLatitude: Double?
    @State private var locationLongitude: Double?
    @State private var notes: String
    @State private var isSelectingMenuDrink = false
    @State private var selectedMenuDrink: MenuDrink?
    @State private var selectedPhoto: PhotosPickerItem?
    @State private var selectedPhotoData: Data?
    @State private var savedPhotoData: Data?
    @State private var photoMetadataMessage: String?
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
        let menuCatalog = Self.loadBundledCatalog()
        let selectedMenuDrink: MenuDrink?
        if let drinkID = originalRecord?.drinkID, !drinkID.isEmpty {
            selectedMenuDrink = menuCatalog?.drinks.first(where: { $0.id == drinkID })
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

    var body: some View {
        Form {
            Section {
                PhotoPickerWell(
                    selection: $selectedPhoto,
                    image: previewImage,
                    title: previewImage == nil ? "添加饮品照片" : "更换饮品照片",
                    detail: "留下一张这杯饮品的照片"
                )

                if selectedPhotoData != nil || savedPhotoData != nil {
                    Button("移除照片", role: .destructive) {
                        photoRemoved = true
                        selectedPhotoData = nil
                        selectedPhoto = nil
                        photoMetadataMessage = nil
                    }
                }
            } header: {
                Text("照片")
            } footer: {
                Text(photoMetadataMessage ?? "照片可以稍后补上。选择包含拍摄信息的照片时，会自动填入时间和地点。")
            }

            Section("喝的是什么") {
                TextField("输入名称，自动匹配目录", text: $drinkName)
                    .textContentType(.none)
                    .focused($focusedField, equals: .drinkName)
                    .background {
                        GeometryReader { geometry in
                            Color.clear.preference(
                                key: DrinkNameFieldFrameKey.self,
                                value: geometry.frame(in: .named("drinkRecordForm"))
                            )
                        }
                    }
                    .onChange(of: drinkName) { _, newValue in
                        guard let selectedMenuDrink,
                              newValue.trimmingCharacters(in: .whitespacesAndNewlines) != selectedMenuDrink.name else { return }
                        self.selectedMenuDrink = nil
                    }

                if let selectedMenuDrink {
                    Label("已关联菜单：\(selectedMenuDrink.brandName)", systemImage: "checkmark.circle.fill")
                        .font(.footnote)
                        .foregroundStyle(GanfanPalette.forest)
                        .fixedSize(horizontal: false, vertical: true)
                } else if focusedField == .drinkName,
                          !drinkName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    if drinkSuggestions.isEmpty {
                        Label("目录中没有匹配项，可直接按此名称记录自定义饮品", systemImage: "pencil.and.outline")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
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
                                            Text(drink.brandName)
                                                .font(.footnote)
                                                .foregroundStyle(.secondary)
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

                TextField("品牌（可选）", text: $brandName)
                    .textContentType(.organizationName)
                    .focused($focusedField, equals: .brandName)
                    .onChange(of: brandName) { _, newValue in
                        guard let selectedMenuDrink, newValue != selectedMenuDrink.brandName else { return }
                        self.selectedMenuDrink = nil
                    }

                if let selectedMenuDrink {
                    LabeledContent("菜单状态", value: selectedMenuDrink.status == "verified" ? "已核验" : "待核验")
                }

                Button("浏览完整饮品目录", systemImage: "list.bullet") {
                    focusedField = nil
                    isSelectingMenuDrink = true
                }
                .font(.subheadline)
            }

            Section("这一杯的细节") {
                OptionChipPicker(title: "杯型", options: [""] + cupTypeOptions, selection: $cupType)
                if !cupType.isEmpty {
                    LabeledContent("容量", value: cupSizeLabel)
                }
                OptionChipPicker(title: "甜度", options: [""] + sweetnessOptions, selection: $sweetness)
                OptionChipPicker(title: "温度", options: [""] + temperatureOptions, selection: $temperature)
                if temperature == "冰饮" {
                    OptionChipPicker(title: "冰量", options: [""] + iceOptions, selection: $ice)
                }
            }

            Section {
                DisclosureGroup("本次摄入") {
                    let nutrition = calculatedNutrition
                    LabeledContent("状态", value: nutrition.confidence.displayName)
                    nutritionValue("能量", amount: nutrition.energyKcal, unit: "kcal")
                    nutritionValue("糖", amount: nutrition.sugarGrams, unit: "g")
                    nutritionValue("咖啡因", amount: nutrition.caffeineMilligrams, unit: "mg")
                    if !nutrition.source.isEmpty {
                        LabeledContent("来源", value: nutrition.source)
                    }
                    if let sourceURL = nutrition.sourceURL, !sourceURL.isEmpty {
                        LabeledContent("来源链接", value: sourceURL)
                    }
                }
            } header: {
                Text("营养快照")
            } footer: {
                Text("营养资料随目录自动计算；自定义饮品可以先保存记录。")
            }

            Section("时间与地点") {
                DatePicker("饮用时间", selection: $consumedAt, displayedComponents: [.date, .hourAndMinute])
                NavigationLink {
                    MapLocationPickerView { selection in
                        locationName = selection.storeName
                        locationAddress = selection.address
                        locationLatitude = selection.latitude
                        locationLongitude = selection.longitude
                    }
                } label: {
                    Label(locationLatitude == nil ? "从地图选择地点" : "重新选择地图地点", systemImage: "map")
                }
                if !locationName.isEmpty {
                    LabeledContent("地点", value: locationName)
                }
                if !locationAddress.isEmpty {
                    LabeledContent("地址", value: locationAddress)
                }
                if locationLatitude != nil, locationLongitude != nil {
                    Label("已保存地图坐标", systemImage: "location.fill")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                TextField("备注（可选）", text: $notes, axis: .vertical)
                    .focused($focusedField, equals: .notes)
                    .accessibilityHint("记录这杯饮品的口味或当时的心情")
            }
        }
        .scrollContentBackground(.hidden)
        .background(GanfanPalette.canvas)
        .tint(GanfanPalette.forest)
        .navigationTitle(storedRecord == nil ? "记录饮品" : "编辑饮品")
        .navigationBarTitleDisplayMode(.inline)
        .scrollDismissesKeyboard(.interactively)
        .coordinateSpace(name: "drinkRecordForm")
        .onPreferenceChange(DrinkNameFieldFrameKey.self) { drinkNameFieldFrame = $0 }
        .simultaneousGesture(
            SpatialTapGesture().onEnded { value in
                if focusedField == .drinkName, !drinkNameFieldFrame.contains(value.location) {
                    focusedField = nil
                }
            }
        )
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
        .sheet(isPresented: $isSelectingMenuDrink) {
            NavigationStack {
                MenuPickerView(catalog: menuCatalog) { drink in
                    chooseMenuDrink(drink)
                }
            }
            .presentationDetents([.large])
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

    private var drinkSuggestions: [MenuDrink] {
        let query = drinkName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty, selectedMenuDrink == nil, let menuCatalog else { return [] }
        return Array(menuCatalog.searchDrinks(query: query).prefix(5))
    }

    private func chooseMenuDrink(_ drink: MenuDrink) {
        focusedField = nil
        selectedMenuDrink = drink
        brandName = drink.brandName
        drinkName = drink.name
        if cupType.isEmpty, let menuCup = drink.cupTypes.first, cupTypeOptions.contains(menuCup) {
            cupType = menuCup
        }
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
        var options = selectedMenuDrink?.sweetnessOptions
            .filter { !$0.isEmpty }
            .map(Self.normalizedSweetness) ?? []
        if options.isEmpty { options = ["不另外加糖", "微糖", "三分糖", "五分糖", "七分糖", "全糖"] }
        var seen = Set<String>()
        options = options.filter { seen.insert($0).inserted }
        if !sweetness.isEmpty, !options.contains(sweetness) { options.append(sweetness) }
        return options
    }

    private static func normalizedSweetness(_ value: String) -> String {
        value == "无糖" ? "不另外加糖" : value
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
           Self.normalizedSweetness(originalRecord.sweetness) == sweetness {
            let originalServing = DrinkServingSelection(
                temperature: originalRecord.temperature,
                ice: originalRecord.ice,
                legacyServingOption: originalRecord.temperature == nil && originalRecord.ice == nil
                    ? originalRecord.servingOption
                    : nil
            )
            if originalServing.temperature == temperature, originalServing.ice == ice,
               let savedNutrition = originalRecord.nutrition {
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
            return NutritionSnapshot(energyKcal: nil, sugarGrams: nil, caffeineMilligrams: nil, confidence: .unavailable)
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
            return originalRecord.nutrition ?? NutritionSnapshot(
                energyKcal: nil,
                sugarGrams: nil,
                caffeineMilligrams: nil,
                confidence: .unavailable
            )
        }
        return NutritionSnapshot(energyKcal: nil, sugarGrams: nil, caffeineMilligrams: nil, confidence: .unavailable)
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
            let data = try await selectedPhoto.loadTransferable(type: Data.self)
            guard !Task.isCancelled else { return }
            selectedPhotoData = data
            photoExtension = selectedPhoto.supportedContentTypes.first?.preferredFilenameExtension ?? "jpg"
            photoRemoved = false
            photoMetadataMessage = nil
            if let data, let metadata = PhotoCaptureMetadataReader.read(from: data) {
                await applyPhotoMetadata(metadata)
            }
        } catch {
            selectedPhotoData = nil
            PhotoStorageDiagnosticsStore().record(stage: .photoSelection, reason: PhotoStorageDiagnosticsStore.reason(for: error))
            errorMessage = "读取所选照片失败：\(error.localizedDescription)"
        }
    }

    private func applyPhotoMetadata(_ metadata: PhotoCaptureMetadata) async {
        var placemark: CLPlacemark?
        if let latitude = metadata.latitude, let longitude = metadata.longitude {
            let location = CLLocation(latitude: latitude, longitude: longitude)
            placemark = try? await CLGeocoder().reverseGeocodeLocation(location).first
        }
        guard !Task.isCancelled else { return }

        if let date = metadata.date {
            consumedAt = date
        }

        var locationWasResolved = false
        if let latitude = metadata.latitude, let longitude = metadata.longitude {
            locationLatitude = latitude
            locationLongitude = longitude
            if let placemark {
                locationName = placemark.name ?? placemark.locality ?? ""
                locationAddress = MapLocationPickerView.address(from: placemark)
                locationWasResolved = !locationAddress.isEmpty
            } else {
                locationName = ""
                locationAddress = ""
            }
        }

        if metadata.date != nil, metadata.latitude != nil {
            photoMetadataMessage = locationWasResolved
                ? "已从照片读取拍摄时间和地点，并填入记录。"
                : "已读取照片拍摄时间和坐标；地址暂时无法解析。"
        } else if metadata.date != nil {
            photoMetadataMessage = "已从照片读取拍摄时间，并填入记录。"
        } else if metadata.latitude != nil {
            photoMetadataMessage = locationWasResolved
                ? "已从照片读取拍摄地点，并填入记录。"
                : "已读取照片坐标；地址暂时无法解析。"
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
                MapLocationPickerView { selection in
                    if storeName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        storeName = selection.storeName
                    }
                    confirmedMapAddress = selection.address
                    locationAddress = selection.address
                    locationLatitude = selection.latitude
                    locationLongitude = selection.longitude
                }
            }
            .presentationDetents([.large])
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
                    savedDishes.append(try MealDish(id: draft.id, name: normalizedName, photo: photo))
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

private struct PhotoPickerWell: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Binding var selection: PhotosPickerItem?
    let image: UIImage?
    let title: String
    let detail: String
    var compact = false

    private var usesCompactSquare: Bool {
        compact && !dynamicTypeSize.isAccessibilitySize
    }

    var body: some View {
        PhotosPicker(selection: $selection, matching: .images) {
            photoContent
            .background(GanfanPalette.card)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
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
        .accessibilityLabel(title)
        .accessibilityHint(detail)
    }

    @ViewBuilder
    private var photoContent: some View {
        if let image {
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
                .frame(width: usesCompactSquare ? 96 : nil, height: imageHeight)
                .frame(maxWidth: usesCompactSquare ? 96 : .infinity)
                .clipped()
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

    private var imageHeight: CGFloat {
        if usesCompactSquare { return 96 }
        return compact ? 150 : 190
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
            Text(detail)
                .font(.footnote)
                .foregroundStyle(.secondary)
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

    init() {
        id = UUID()
        name = ""
        originalPhoto = nil
        selectedPhoto = nil
        photoData = nil
        photoExtension = "jpg"
        photoRemoved = false
    }

    init(dish: MealDish) {
        id = dish.id
        name = dish.name
        originalPhoto = dish.photo
        selectedPhoto = nil
        photoData = nil
        photoExtension = dish.photo?.fileExtension ?? "jpg"
        photoRemoved = false
    }
}

private struct MealDishEditorRow: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Binding var draft: MealDishDraft
    let onRemove: () -> Void
    @State private var savedPhotoData: Data?
    @State private var errorMessage: String?

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
    }

    private var dishFields: some View {
        VStack(alignment: .leading, spacing: 8) {
            TextField("菜品名称（必填）", text: $draft.name)
            if let errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
            if !draft.photoRemoved && (draft.photoData != nil || savedPhotoData != nil) {
                Button("移除照片", role: .destructive) {
                    draft.photoRemoved = true
                    draft.photoData = nil
                    draft.selectedPhoto = nil
                }
                .font(.footnote)
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
            compact: true
        )
    }

    private func loadSelectedPhoto() async {
        guard let selectedPhoto = draft.selectedPhoto else { return }
        do {
            draft.photoData = try await selectedPhoto.loadTransferable(type: Data.self)
            draft.photoExtension = selectedPhoto.supportedContentTypes.first?.preferredFilenameExtension ?? "jpg"
            draft.photoRemoved = false
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
