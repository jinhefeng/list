import PhotosUI
import ImageIO
import SwiftUI
import UniformTypeIdentifiers
import UIKit
import WebKit

struct MoreView: View {
    var body: some View {
        List {
            Section("饮品资料") {
                NavigationLink {
                    CatalogManagementView()
                } label: {
                    MoreDestinationRow(
                        title: "饮品目录",
                        detail: "维护品牌、饮品、杯型和营养资料",
                        symbol: "cup.and.saucer"
                    )
                }
            }

            Section("营养与智能识别") {
                NavigationLink {
                    NutritionUpdateSettingsView()
                } label: {
                    MoreDestinationRow(title: "营养数据库", detail: "查看内置数据及检查在线更新", symbol: "arrow.down.doc")
                }
                NavigationLink {
                    AINutritionSettingsView()
                } label: {
                    MoreDestinationRow(title: "AI 模型设置", detail: "配置自己的 API；未配置时不显示识别入口", symbol: "slider.horizontal.3")
                }
            }

            Section("数据管理") {
                NavigationLink {
                    StorageDiagnosticsView()
                } label: {
                    MoreDestinationRow(
                        title: "本机存储",
                        detail: "查看照片占用和诊断信息",
                        symbol: "externaldrive"
                    )
                }

                NavigationLink {
                    BackupSettingsView()
                } label: {
                    MoreDestinationRow(
                        title: "备份与恢复",
                        detail: "管理所选目录中的个人备份",
                        symbol: "icloud.and.arrow.up"
                    )
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(GanfanPalette.canvas)
        .tint(GanfanPalette.forest)
        .navigationTitle("更多")
        .navigationBarTitleDisplayMode(.large)
    }
}

private struct MoreDestinationRow: View {
    let title: String
    let detail: String
    let symbol: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: symbol)
                .font(.body.weight(.medium))
                .foregroundStyle(GanfanPalette.forest)
                .frame(width: 28)

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.body)
                    .foregroundStyle(.primary)
                Text(detail)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.vertical, 3)
        .contentShape(Rectangle())
    }
}

private enum CatalogDrinkEditorPresentation: Identifiable {
    case create
    case edit(MenuDrink)
    case createBrand

    var id: String {
        switch self {
        case .create:
            return "create"
        case .edit(let drink):
            return "edit-\(drink.id)"
        case .createBrand:
            return "create-brand"
        }
    }

    var drink: MenuDrink? {
        guard case .edit(let drink) = self else { return nil }
        return drink
    }
}

struct CatalogManagementView: View {
    @Environment(\.journalSQLiteStore) private var library
    @AppStorage(BackupChangeTracker.generationKey) private var libraryChangeGeneration = 0
    @State private var referencedDrinkIDs: Set<String> = []
    @State private var catalog: MenuCatalog?
    @State private var userState = MenuCatalogUserState()
    @State private var query = ""
    @State private var selectedBrandID = ""
    @State private var selectedCategory = ""
    @State private var editorPresentation: CatalogDrinkEditorPresentation?
    @State private var selectedForDeletion: MenuDrink?
    @State private var isConfirmingDeletion = false
    @State private var errorMessage: String?
    @State private var projectExportURL: URL?

    private let repository = MenuCatalogRepository()

    private var visibleDrinks: [MenuDrink] {
        let allDrinks = catalog?.drinks ?? []
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines)
        return allDrinks.filter { drink in
            (selectedBrandID.isEmpty || drink.brandID == selectedBrandID)
                && (selectedCategory.isEmpty || drink.category == selectedCategory)
                && (needle.isEmpty || ([drink.name, drink.brandName, drink.category] + drink.aliases)
                    .contains { $0.localizedCaseInsensitiveContains(needle) })
        }
    }

    private var categories: [String] {
        Array(Set(catalog?.drinks.map(\.category).filter { !$0.isEmpty } ?? [])).sorted()
    }

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 7) {
                    Text("维护常用饮品、容量和营养资料。")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Text("\(catalog?.brands.count ?? 0) 个品牌 · \(catalog?.drinks.count ?? 0) 款饮品")
                        .font(.footnote.weight(.medium).monospacedDigit())
                        .foregroundStyle(GanfanPalette.forest)
                }
                .padding(.vertical, 6)
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets(top: 12, leading: 20, bottom: 8, trailing: 20))

                Button {
                    editorPresentation = .createBrand
                } label: {
                    Label("新增品牌", systemImage: "plus.circle.fill")
                        .font(.body.weight(.semibold))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 5)
                }
                .tint(GanfanPalette.forest)
            }

            Section {
                NavigationLink {
                    CupSizeSettingsView(initial: userState.globalCupSizes, onSave: saveCupSizes)
                } label: {
                    Label("全局杯型与容量", systemImage: "cup.and.saucer")
                }
                NavigationLink {
                    BrandLogoManagementView(
                        brands: catalog?.brands ?? [],
                        onSaveLogo: { brand, data in saveBrandLogo(brand, with: data) },
                        onDeleteLogo: deleteBrandLogo
                    )
                } label: {
                    Label("品牌 Logo", systemImage: "photo")
                }
                LabeledContent("菜单版本", value: catalog?.version ?? "不可用")
            } header: {
                Text("目录设置")
            }

            Section("项目资料同步") {
                Button(action: exportPhoneCatalog) {
                    Label("导出手机维护的品牌资料", systemImage: "square.and.arrow.up")
                }
                if let projectExportURL {
                    ShareLink(item: projectExportURL) {
                        Label("发送资料包到项目电脑", systemImage: "airplayvideo")
                    }
                    Text("资料包只含本机新增或修改的品牌、饮品和 Logo，不含记录、照片或 API 设置。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Section {
                TextField("搜索饮品、品牌或别名", text: $query)
                Picker("品牌", selection: $selectedBrandID) {
                    Text("全部品牌").tag("")
                    ForEach(catalog?.brands ?? []) { brand in
                        Text(brand.name).tag(brand.id)
                    }
                }
                Picker("分类", selection: $selectedCategory) {
                    Text("全部分类").tag("")
                    ForEach(categories, id: \.self) { category in
                        Text(category).tag(category)
                    }
                }
                HStack {
                    Text("当前结果")
                    Spacer()
                    Text("\(visibleDrinks.count) 款")
                        .foregroundStyle(.secondary)
                }
            } header: {
                Text("筛选目录")
            }

            Section("饮品") {
                ForEach(visibleDrinks) { drink in
                    Button {
                        editorPresentation = .edit(drink)
                    } label: {
                        CatalogDrinkRow(
                            drink: drink,
                            brand: catalog?.brands.first(where: { $0.id == drink.brandID })
                        )
                    }
                    .buttonStyle(.plain)
                    .contextMenu {
                        Button("编辑", systemImage: "pencil") {
                            editorPresentation = .edit(drink)
                        }
                        Button("删除目录条目", systemImage: "trash", role: .destructive) {
                            selectedForDeletion = drink
                            isConfirmingDeletion = true
                        }
                    }
                }
            }

            if let errorMessage {
                Section {
                    Label(errorMessage, systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.orange)
                        .font(.footnote)
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(GanfanPalette.canvas)
        .tint(GanfanPalette.forest)
        .navigationTitle("饮品目录")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    editorPresentation = .create
                } label: {
                    Image(systemName: "plus")
                }
                .accessibilityLabel("添加饮品")
            }
        }
        .task { loadCatalog() }
        .task(id: libraryChangeGeneration) { await refreshRecordReferences() }
        .sheet(item: $editorPresentation, onDismiss: loadCatalog) { presentation in
            NavigationStack {
                switch presentation {
                case .createBrand:
                    BrandImportWizard(
                        existingBrands: catalog?.brands ?? [],
                        onSaveBrand: saveNewBrand,
                        onSaveLogo: { brand, data, sourceURL in
                            saveBrandLogo(brand, with: data, sourceURL: sourceURL)
                        }
                    )
                case .create, .edit:
                    MenuDrinkEditor(drink: presentation.drink, onSave: saveDrink)
                }
            }
        }
        .confirmationDialog("删除目录中的饮品？", isPresented: $isConfirmingDeletion, titleVisibility: .visible) {
            Button("删除", role: .destructive, action: deleteSelectedDrink)
            Button("取消", role: .cancel) { selectedForDeletion = nil }
        } message: {
            Text("历史记录不会被删除。此菜单项目会隐藏，并保留删除标记以防目录更新后重新出现。")
        }
        .alert("操作未完成", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("好", role: .cancel) { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "请重试。")
        }
    }

    private func refreshRecordReferences() async {
        guard let library else { return }
        do {
            referencedDrinkIDs = try await Task.detached(priority: .utility) {
                try library.referencedDrinkIDs()
            }.value
        } catch {
            referencedDrinkIDs = []
        }
    }

    private func loadCatalog() {
        guard let url = Bundle.main.url(forResource: "catalog", withExtension: "json"),
              let data = try? Data(contentsOf: url) else {
            errorMessage = "内置菜单文件不可用；已保存的本地菜单数据未更改。"
            return
        }
        do {
            let bundled = try MenuCatalog.decode(data)
            catalog = try repository.catalog(from: bundled)
            userState = try repository.loadUserState()
            errorMessage = nil
        } catch {
            errorMessage = "无法读取菜单或本地改动：\(error.localizedDescription)"
        }
    }

    private func saveDrink(_ draft: MenuDrinkDraft) -> Bool {
        guard let catalog else { return false }
        do {
            var brands = userState.brands
            let existingBrand = catalog.brands.first {
                $0.name.localizedCaseInsensitiveCompare(draft.brandName) == .orderedSame
            }
            let brandID = existingBrand?.id ?? draft.existingBrandID ?? "local-brand-\(UUID().uuidString)"
            if existingBrand == nil {
                brands.removeAll { $0.id == brandID }
                brands.append(MenuBrand(
                    id: brandID,
                    name: draft.brandName,
                    aliases: [],
                    category: draft.category,
                    source: draft.source,
                    sourceName: draft.sourceName,
                    sourceURL: draft.sourceURL,
                    updatedAt: Self.today,
                    status: draft.status,
                    localOverride: true
                ))
            }

            let drinkID = draft.id ?? "local-drink-\(UUID().uuidString)"
            let aliases = Self.splitList(draft.aliases)
            let cupTypes = Self.splitList(draft.cupTypes)
            let sweetnessOptions = Self.splitList(draft.sweetnessOptions)
            let servingOptions = Self.splitList(draft.servingOptions)
            let nutrition = draft.nutritionPerUnit
            let previous = catalog.drinks.first { $0.id == drinkID }
            let sourceType = draft.status == "pending" ? "user_report" : "manual_platform"
            let entry = MenuEntry(
                scope: "brand",
                status: draft.status,
                sourceType: sourceType,
                sourceName: draft.sourceName.isEmpty ? "用户维护" : draft.sourceName,
                sourceURL: draft.sourceURL,
                checkedAt: draft.status == "pending" ? "" : Self.today,
                cupTypes: cupTypes,
                cupSizes: previous?.cupSizes ?? [],
                sizesML: previous?.sizesML ?? [],
                sweetnessOptions: sweetnessOptions,
                servingOptions: servingOptions
            )
            let updatedDrink = MenuDrink(
                id: drinkID,
                legacyIDs: previous?.legacyIDs ?? [],
                brandID: brandID,
                brandName: draft.brandName,
                name: draft.name,
                aliases: aliases,
                category: draft.category,
                source: draft.source,
                sourceType: sourceType,
                sourceName: draft.sourceName,
                sourceURL: draft.sourceURL,
                updatedAt: Self.today,
                status: draft.status,
                active: draft.active,
                cupTypes: cupTypes,
                cupSizes: previous?.cupSizes ?? [],
                sizesML: previous?.sizesML ?? [],
                sweetnessOptions: sweetnessOptions,
                servingOptions: servingOptions,
                nutritionPerUnit: nutrition,
                nutritionVariants: previous?.nutritionVariants ?? [],
                menuEntries: (previous?.menuEntries.filter { $0.scope != "brand" } ?? []) + [entry],
                localOverride: true,
                custom: previous?.custom ?? (draft.id == nil)
            )
            var drinks = userState.drinks.filter { $0.id != drinkID }
            drinks.append(updatedDrink)
            let state = MenuCatalogUserState(
                brands: brands,
                drinks: drinks,
                deletedDrinkIDs: userState.deletedDrinkIDs.subtracting([drinkID] + (previous?.legacyIDs ?? [])),
                globalCupSizes: userState.globalCupSizes
            )
            try repository.saveUserState(state)
            BackupChangeTracker().markChanged()
            userState = state
            self.catalog = catalog.merging(localBrands: state.brands, localDrinks: state.drinks, deletedDrinkIDs: state.deletedDrinkIDs)
            errorMessage = nil
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    private func saveNewBrand(
        name: String,
        category: String,
        aliases: [String],
        sourceName: String,
        sourceURL: String,
        drinkNames: [String]
    ) -> BrandImportSaveResult? {
        guard let catalog else { return nil }
        let normalizedName = Self.normalizedCatalogValue(name)
        guard !normalizedName.isEmpty else {
            errorMessage = "品牌名称不能为空。"
            return nil
        }
        if let existing = catalog.brands.first(where: { Self.normalizedCatalogValue($0.name) == normalizedName }) {
            errorMessage = "“\(existing.name)”已在目录中；可以直接为它添加饮品或设置 Logo。"
            return nil
        }

        let brand = MenuBrand(
            id: "local-brand-\(UUID().uuidString)",
            name: name.trimmingCharacters(in: .whitespacesAndNewlines),
            aliases: aliases,
            category: category.trimmingCharacters(in: .whitespacesAndNewlines),
            source: sourceName.isEmpty ? "网页搜索候选，待核验" : sourceName,
            sourceName: sourceName,
            sourceURL: sourceURL,
            updatedAt: Self.today,
            status: "pending",
            active: true,
            localOverride: true
        )
        var brands = userState.brands.filter { $0.id != brand.id }
        brands.append(brand)
        let currentDrinkNames = Set(catalog.drinks
            .filter { $0.brandID == brand.id }
            .map { Self.normalizedCatalogValue($0.name) })
        var seenNames = Set<String>()
        let uniqueNames = drinkNames.compactMap { rawName -> String? in
            let value = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
            let key = Self.normalizedCatalogValue(value)
            guard !key.isEmpty, !currentDrinkNames.contains(key), seenNames.insert(key).inserted else { return nil }
            return value
        }
        let menuEntrySourceName = sourceName.isEmpty ? "用户维护" : sourceName
        let drinks = uniqueNames.map { drinkName in
            let entry = MenuEntry(
                scope: "brand",
                status: "pending",
                sourceType: "user_report",
                sourceName: menuEntrySourceName,
                sourceURL: sourceURL,
                checkedAt: "",
                cupTypes: [],
                sweetnessOptions: [],
                servingOptions: []
            )
            return MenuDrink(
                id: "local-drink-\(UUID().uuidString)",
                brandID: brand.id,
                brandName: brand.name,
                name: drinkName,
                category: brand.category,
                source: "网页提取候选，待核验",
                sourceType: "user_report",
                sourceName: menuEntrySourceName,
                sourceURL: sourceURL,
                updatedAt: Self.today,
                status: "pending",
                active: true,
                menuEntries: [entry],
                localOverride: true,
                custom: true
            )
        }
        let state = MenuCatalogUserState(
            brands: brands,
            drinks: userState.drinks + drinks,
            deletedDrinkIDs: userState.deletedDrinkIDs,
            globalCupSizes: userState.globalCupSizes
        )
        guard saveBrandState(state) else { return nil }
        return BrandImportSaveResult(brand: brand, drinkCount: drinks.count, skippedDrinkCount: drinkNames.count - drinks.count)
    }

    private func saveBrandLogo(_ brand: MenuBrand, with data: Data, sourceURL: String? = nil) -> MenuBrand? {
        do {
            let newAsset = try AppStoragePaths.brandLogoPhotoStore.save(data, fileExtension: "png")
            let updatedBrand = Self.brand(
                brand,
                imageID: newAsset.id,
                updatedAt: Self.today,
                logoSourceURL: sourceURL ?? brand.logoSourceURL
            )
            var brands = userState.brands.filter { $0.id != brand.id }
            brands.append(updatedBrand)
            let state = MenuCatalogUserState(
                brands: brands,
                drinks: userState.drinks,
                deletedDrinkIDs: userState.deletedDrinkIDs,
                globalCupSizes: userState.globalCupSizes
            )
            guard saveBrandState(state) else {
                try? AppStoragePaths.brandLogoPhotoStore.remove(newAsset)
                return nil
            }
            if let oldID = brand.logoImageID, oldID != newAsset.id {
                removeBrandLogoIfUnreferenced(oldID)
            }
            return updatedBrand
        } catch {
            errorMessage = "保存品牌 Logo 失败：\(error.localizedDescription)"
            return nil
        }
    }

    private func deleteBrandLogo(_ brand: MenuBrand) -> MenuBrand? {
        guard brand.logoAssetName != nil || brand.logoImageID != nil || brand.logoSymbol != nil else {
            return nil
        }
        let updatedBrand = Self.brand(brand, imageID: nil, updatedAt: Self.today)
        var brands = userState.brands.filter { $0.id != brand.id }
        brands.append(updatedBrand)
        let state = MenuCatalogUserState(
            brands: brands,
            drinks: userState.drinks,
            deletedDrinkIDs: userState.deletedDrinkIDs,
            globalCupSizes: userState.globalCupSizes
        )
        guard saveBrandState(state) else { return nil }
        if let oldID = brand.logoImageID {
            removeBrandLogoIfUnreferenced(oldID)
        }
        return updatedBrand
    }

    private func removeBrandLogoIfUnreferenced(_ imageID: UUID) {
        let referencedInCatalog = catalog?.brands.contains { $0.logoImageID == imageID } ?? false
        let referencedInOverrides = userState.brands.contains { $0.logoImageID == imageID }
        guard !referencedInCatalog, !referencedInOverrides else { return }
        try? AppStoragePaths.removeBrandLogo(imageID)
    }

    private func saveBrandState(_ state: MenuCatalogUserState) -> Bool {

        do {
            try repository.saveUserState(state)
            BackupChangeTracker().markChanged()
            userState = state
            if let catalog {
                self.catalog = catalog.merging(
                    localBrands: state.brands,
                    localDrinks: state.drinks,
                    deletedDrinkIDs: state.deletedDrinkIDs
                )
            }
            errorMessage = nil
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    private static func brand(
        _ brand: MenuBrand,
        imageID: UUID?,
        updatedAt: String,
        logoSourceURL: String? = nil
    ) -> MenuBrand {
        MenuBrand(
            id: brand.id,
            name: brand.name,
            aliases: brand.aliases,
            category: brand.category,
            source: brand.source,
            sourceName: brand.sourceName,
            sourceURL: brand.sourceURL,
            updatedAt: updatedAt,
            status: brand.status,
            active: brand.active,
            logoSymbol: nil,
            logoAssetName: nil,
            logoImageID: imageID,
            logoIsOverridden: true,
            logoURL: logoSourceURL,
            logoSourceURL: logoSourceURL,
            localOverride: true
        )
    }

    private func exportPhoneCatalog() {
        do {
            let brands = userState.brands.filter(\.localOverride)
            let drinks = userState.drinks.filter { $0.localOverride || $0.custom }
            let logoIDs = Set(brands.compactMap(\.logoImageID))
            let logoAssets = try logoIDs.sorted { $0.uuidString < $1.uuidString }.map { id -> PhoneCatalogLogoAsset in
                guard let data = AppStoragePaths.brandLogoImageData(for: id) else {
                    throw PhoneCatalogExportError.missingLogo(id)
                }
                return PhoneCatalogLogoAsset(id: id, data: data)
            }
            let transfer = PhoneCatalogProjectExport(
                schemaVersion: 1,
                createdAt: ISO8601DateFormatter().string(from: .now),
                brands: brands,
                drinks: drinks,
                logoAssets: logoAssets
            )
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(transfer)
            let filename = "吃吃喝喝-品牌资料-\(Self.today)-\(UUID().uuidString.prefix(8)).json"
            let destination = FileManager.default.temporaryDirectory.appendingPathComponent(filename)
            try data.write(to: destination, options: .atomic)
            projectExportURL = destination
            errorMessage = nil
        } catch {
            errorMessage = "无法导出手机品牌资料：\(error.localizedDescription)"
        }
    }

    private static func normalizedCatalogValue(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: " ", with: "")
            .lowercased()
    }

    private func deleteSelectedDrink() {
        guard let drink = selectedForDeletion else { return }
        let referencedIDs = Set([drink.id] + drink.legacyIDs)
        guard referencedIDs.isDisjoint(with: referencedDrinkIDs) else {
            errorMessage = "历史记录正在引用这款饮品。先编辑相关记录，再删除菜单项目。"
            return
        }
        let state = MenuCatalogUserState(
            brands: userState.brands,
            drinks: userState.drinks.filter { $0.id != drink.id },
            deletedDrinkIDs: userState.deletedDrinkIDs.union([drink.id] + drink.legacyIDs),
            globalCupSizes: userState.globalCupSizes
        )
        do {
            try repository.saveUserState(state)
            BackupChangeTracker().markChanged()
            userState = state
            loadCatalog()
        } catch {
            errorMessage = error.localizedDescription
        }
        selectedForDeletion = nil
    }

    private func saveCupSizes(_ sizes: [MenuCupSize]) {
        let state = MenuCatalogUserState(
            brands: userState.brands,
            drinks: userState.drinks,
            deletedDrinkIDs: userState.deletedDrinkIDs,
            globalCupSizes: sizes
        )
        do {
            try repository.saveUserState(state)
            BackupChangeTracker().markChanged()
            userState = state
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private static var today: String {
        ISO8601DateFormatter().string(from: .now).prefix(10).description
    }

    private static func splitList(_ input: String) -> [String] {
        input.split(whereSeparator: { ",，、".contains($0) })
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }
}

private struct BrandLogoManagementView: View {
    let brands: [MenuBrand]
    let onSaveLogo: (MenuBrand, Data) -> MenuBrand?
    let onDeleteLogo: (MenuBrand) -> MenuBrand?

    @State private var selectedBrand: MenuBrand?
    @State private var brandOverrides: [String: MenuBrand] = [:]

    var body: some View {
        List {
            Section {
                Text("每张 Logo 直接属于一个品牌。选择品牌即可添加、调整、替换或删除它的 Logo；图片标题使用品牌名称。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Section("品牌") {
                ForEach(brands) { sourceBrand in
                    let brand = brandOverrides[sourceBrand.id] ?? sourceBrand
                    Button {
                        selectedBrand = brand
                    } label: {
                        HStack(spacing: 12) {
                            GanfanBrandLogoIcon(
                                assetName: brand.logoAssetName,
                                symbol: brand.logoSymbol,
                                imageID: brand.logoImageID,
                                dimension: 32
                            )
                            VStack(alignment: .leading, spacing: 3) {
                                Text(brand.name)
                                    .font(.body)
                                    .foregroundStyle(GanfanPalette.ink)
                                Text(Self.hasLogo(brand) ? "已设置 Logo" : "未设置 Logo")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.tertiary)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(GanfanPalette.canvas)
        .navigationTitle("品牌 Logo")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $selectedBrand) { brand in
            NavigationStack {
                BrandLogoEditor(
                    brand: brand,
                    onSaveLogo: { sourceBrand, data in
                        guard let updatedBrand = onSaveLogo(sourceBrand, data) else { return nil }
                        brandOverrides[updatedBrand.id] = updatedBrand
                        return updatedBrand
                    },
                    onDeleteLogo: { sourceBrand in
                        guard let updatedBrand = onDeleteLogo(sourceBrand) else { return nil }
                        brandOverrides[updatedBrand.id] = updatedBrand
                        return updatedBrand
                    }
                )
            }
        }
    }

    private static func hasLogo(_ brand: MenuBrand) -> Bool {
        brand.logoAssetName != nil || brand.logoImageID != nil || brand.logoSymbol != nil
    }
}

private struct BrandLogoEditor: View {
    @Environment(\.dismiss) private var dismiss

    let onSaveLogo: (MenuBrand, Data) -> MenuBrand?
    let onDeleteLogo: (MenuBrand) -> MenuBrand?

    @State private var currentBrand: MenuBrand
    @State private var selectedPhoto: PhotosPickerItem?
    @State private var cropRequest: BrandLogoCropRequest?
    @State private var isConfirmingDeletion = false
    @State private var isLoadingPhoto = false
    @State private var errorMessage: String?

    init(
        brand: MenuBrand,
        onSaveLogo: @escaping (MenuBrand, Data) -> MenuBrand?,
        onDeleteLogo: @escaping (MenuBrand) -> MenuBrand?
    ) {
        self.onSaveLogo = onSaveLogo
        self.onDeleteLogo = onDeleteLogo
        _currentBrand = State(initialValue: brand)
    }

    private var hasLogo: Bool {
        currentBrand.logoAssetName != nil || currentBrand.logoImageID != nil || currentBrand.logoSymbol != nil
    }

    private var previewSection: some View {
        Section("品牌") {
            HStack(spacing: 12) {
                GanfanBrandLogoIcon(
                    assetName: currentBrand.logoAssetName,
                    symbol: currentBrand.logoSymbol,
                    imageID: currentBrand.logoImageID,
                    dimension: 44
                )
                VStack(alignment: .leading, spacing: 4) {
                    Text(currentBrand.name)
                        .font(.headline)
                        .foregroundStyle(GanfanPalette.ink)
                    Text(hasLogo ? "当前品牌 Logo" : "尚未设置 Logo")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding(.vertical, 4)
            Text("这张图片会直接设置为“\(currentBrand.name)”的 Logo。")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    private var logoActionsSection: some View {
        let hasCurrentLogo = hasLogo
        return Section {
            PhotosPicker(
                selection: $selectedPhoto,
                matching: .images,
                photoLibrary: .shared(),
                label: {
                    Label(hasCurrentLogo ? "替换 Logo 图片" : "添加 Logo 图片", systemImage: hasCurrentLogo ? "arrow.triangle.2.circlepath" : "plus")
                }
            )

            if hasLogo, currentLogoImage() != nil {
                Button {
                    editCurrentLogo()
                } label: {
                    Label("调整裁切", systemImage: "crop")
                }
            }

            if hasLogo {
                Button("删除此品牌的 Logo", systemImage: "trash", role: .destructive) {
                    isConfirmingDeletion = true
                }
            }

            if isLoadingPhoto {
                HStack(spacing: 8) {
                    ProgressView()
                    Text("正在读取图片…")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
        } header: {
            Text("Logo 图片")
        } footer: {
            Text("新增或替换后会裁切为 256 × 256 像素 PNG，并直接保存到当前品牌。")
        }
    }

    var body: some View {
        Form {
            previewSection
            logoActionsSection
        }
        .scrollContentBackground(.hidden)
        .background(GanfanPalette.canvas)
        .navigationTitle(currentBrand.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("完成") { dismiss() }
            }
        }
        .task(id: selectedPhoto) {
            await loadSelectedPhoto()
        }
        .sheet(item: $cropRequest) { request in
            NavigationStack {
                BrandLogoCropEditor(
                    image: request.image,
                    brandName: currentBrand.name,
                    onSave: { data in onSaveLogo(currentBrand, data) },
                    onComplete: { updatedBrand in currentBrand = updatedBrand }
                )
            }
        }
        .confirmationDialog("删除\(currentBrand.name)的 Logo？", isPresented: $isConfirmingDeletion, titleVisibility: .visible) {
            Button("删除 Logo", role: .destructive, action: deleteLogo)
            Button("取消", role: .cancel) {}
        } message: {
            Text("删除自定义图片后会优先恢复软件内置图案；如果品牌没有内置图案，则显示通用狮子图标。")
        }
        .alert("图片处理失败", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("好", role: .cancel) { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "请重试。")
        }
    }

    private func currentLogoImage() -> UIImage? {
        if let imageID = currentBrand.logoImageID {
            return AppStoragePaths.brandLogoImageData(for: imageID).flatMap(UIImage.init(data:))
        }
        if let assetName = currentBrand.logoAssetName {
            return UIImage(named: assetName)
        }
        return nil
    }

    private func editCurrentLogo() {
        guard let image = currentLogoImage() else {
            errorMessage = "无法打开当前品牌的 Logo。"
            return
        }
        cropRequest = BrandLogoCropRequest(image: image)
    }

    private func loadSelectedPhoto() async {
        guard let selectedPhoto else { return }
        isLoadingPhoto = true
        defer {
            isLoadingPhoto = false
            if self.selectedPhoto == selectedPhoto { self.selectedPhoto = nil }
        }
        do {
            guard let data = try await selectedPhoto.loadTransferable(type: Data.self) else {
                throw BrandLogoImageError.emptyImage
            }
            guard let preparedData = await Task.detached(priority: .utility, operation: {
                BrandLogoImageProcessor.downsampledPNG(from: data)
            }).value,
            let image = UIImage(data: preparedData) else {
                throw BrandLogoImageError.invalidImage
            }
            cropRequest = BrandLogoCropRequest(image: image)
        } catch {
            errorMessage = "无法读取所选图片：\(error.localizedDescription)"
        }
    }

    private func deleteLogo() {
        guard let updatedBrand = onDeleteLogo(currentBrand) else {
            errorMessage = "删除未完成，请检查本机存储后重试。"
            return
        }
        currentBrand = updatedBrand
    }
}

private struct BrandLogoCropRequest: Identifiable {
    let id = UUID()
    let image: UIImage
}

private enum BrandLogoImageError: LocalizedError {
    case emptyImage
    case invalidImage
    case exportFailed
    case saveFailed

    var errorDescription: String? {
        switch self {
        case .emptyImage: "没有读取到图片内容。"
        case .invalidImage: "所选文件无法作为图片打开。"
        case .exportFailed: "无法生成 256 × 256 图案。"
        case .saveFailed: "图案文件保存失败。"
        }
    }
}

private enum BrandLogoImageProcessor {
    static func downsampledPNG(from data: Data) -> Data? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let image = CGImageSourceCreateThumbnailAtIndex(
                source,
                0,
                [
                    kCGImageSourceCreateThumbnailFromImageAlways: true,
                    kCGImageSourceCreateThumbnailWithTransform: true,
                    kCGImageSourceThumbnailMaxPixelSize: 2048
                ] as CFDictionary
              ) else {
            return nil
        }
        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(output, UTType.png.identifier as CFString, 1, nil) else {
            return nil
        }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return output as Data
    }
}

private struct BrandLogoCropEditor: View {
    @Environment(\.dismiss) private var dismiss

    let image: UIImage
    let brandName: String
    let onSave: (Data) -> MenuBrand?
    let onComplete: (MenuBrand) -> Void

    @State private var zoom: CGFloat = 1
    @State private var committedZoom: CGFloat = 1
    @State private var offset: CGSize = .zero
    @State private var committedOffset: CGSize = .zero
    @State private var errorMessage: String?
    @State private var isSaving = false

    private let viewportSide: CGFloat = 280

    var body: some View {
        VStack(spacing: 18) {
            Text("拖动图片调整位置，双指缩放查看裁切效果。")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)

            Text("此图片会直接设置为“\(brandName)”的 Logo。")
                .font(.footnote.weight(.medium))
                .foregroundStyle(GanfanPalette.forest)
                .multilineTextAlignment(.center)
                .padding(.horizontal)

            ZStack {
                GanfanPalette.card
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(width: viewportSide, height: viewportSide)
                    .scaleEffect(zoom)
                    .offset(offset)
                    .clipped()
                cropGuides
            }
            .frame(width: viewportSide, height: viewportSide)
            .clipShape(Rectangle())
            .overlay(Rectangle().stroke(GanfanPalette.forest.opacity(0.6), lineWidth: 1))
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        offset = clampedOffset(
                            CGSize(
                                width: committedOffset.width + value.translation.width,
                                height: committedOffset.height + value.translation.height
                            ),
                            zoom: zoom
                        )
                    }
                    .onEnded { _ in committedOffset = offset }
            )
            .simultaneousGesture(
                MagnificationGesture()
                    .onChanged { value in
                        zoom = min(6, max(1, committedZoom * value))
                        offset = clampedOffset(committedOffset, zoom: zoom)
                    }
                    .onEnded { _ in
                        committedZoom = zoom
                        committedOffset = offset
                    }
            )
            .accessibilityLabel("Logo 裁切预览，可拖动或双指缩放")

            HStack(spacing: 12) {
                Label("256 × 256", systemImage: "square.dashed")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(GanfanPalette.forest)
                Spacer()
                Button("重置位置") {
                    withAnimation(.easeInOut(duration: 0.18)) {
                        zoom = 1
                        committedZoom = 1
                        offset = .zero
                        committedOffset = .zero
                    }
                }
                .font(.caption.weight(.medium))
            }
            .padding(.horizontal, 24)
            Spacer(minLength: 0)
        }
        .padding(.top, 24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(GanfanPalette.canvas)
        .navigationTitle("裁切 Logo")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("取消") { dismiss() }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("保存") { save() }
                    .disabled(isSaving)
            }
        }
        .alert("图片处理失败", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("好", role: .cancel) { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "请重试。")
        }
    }

    private var cropGuides: some View {
        GeometryReader { geometry in
            Path { path in
                for fraction in [CGFloat(1) / 3, CGFloat(2) / 3] {
                    let position = geometry.size.width * fraction
                    path.move(to: CGPoint(x: position, y: 0))
                    path.addLine(to: CGPoint(x: position, y: geometry.size.height))
                    path.move(to: CGPoint(x: 0, y: position))
                    path.addLine(to: CGPoint(x: geometry.size.width, y: position))
                }
            }
            .stroke(Color.white.opacity(0.65), lineWidth: 0.6)
        }
        .allowsHitTesting(false)
    }

    private func clampedOffset(_ proposed: CGSize, zoom: CGFloat) -> CGSize {
        let coverScale = max(viewportSide / image.size.width, viewportSide / image.size.height)
        let renderedWidth = image.size.width * coverScale * zoom
        let renderedHeight = image.size.height * coverScale * zoom
        let maximumX = max(0, (renderedWidth - viewportSide) / 2)
        let maximumY = max(0, (renderedHeight - viewportSide) / 2)
        return CGSize(
            width: min(max(proposed.width, -maximumX), maximumX),
            height: min(max(proposed.height, -maximumY), maximumY)
        )
    }

    private func save() {
        let outputSide: CGFloat = 256
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = false
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: outputSide, height: outputSide), format: format)
        let outputImage = renderer.image { _ in
            let coverScale = max(outputSide / image.size.width, outputSide / image.size.height)
            let renderedWidth = image.size.width * coverScale * zoom
            let renderedHeight = image.size.height * coverScale * zoom
            let outputOffsetScale = outputSide / viewportSide
            let outputX = (outputSide - renderedWidth) / 2 + offset.width * outputOffsetScale
            let outputY = (outputSide - renderedHeight) / 2 + offset.height * outputOffsetScale
            image.draw(in: CGRect(x: outputX, y: outputY, width: renderedWidth, height: renderedHeight))
        }
        guard let pngData = outputImage.pngData() else {
            errorMessage = BrandLogoImageError.exportFailed.localizedDescription
            return
        }
        isSaving = true
        let updatedBrand = onSave(pngData)
        isSaving = false
        guard let updatedBrand else {
            errorMessage = BrandLogoImageError.saveFailed.localizedDescription
            return
        }
        onComplete(updatedBrand)
        dismiss()
    }
}

private struct CatalogDrinkRow: View {
    let drink: MenuDrink
    let brand: MenuBrand?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .center, spacing: 9) {
                Text(drink.name).font(.headline).foregroundStyle(GanfanPalette.ink)
                Spacer(minLength: 8)
                Text(statusText)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(drink.status == "verified" ? GanfanPalette.forest : GanfanPalette.leaf)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(GanfanPalette.paleLeaf.opacity(0.72), in: Capsule())
            }
            HStack(spacing: 6) {
                GanfanBrandLogoIcon(
                    assetName: brand?.logoAssetName,
                    symbol: brand?.logoSymbol,
                    imageID: brand?.logoImageID,
                    dimension: 16
                )
                Text(drink.brandName)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                if !drink.category.isEmpty {
                    Text("· \(drink.category)")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            if let nutrition = drink.nutritionPerUnit {
                Text("每 \(Int(nutrition.amount))\(nutrition.unit)：\(nutrition.sugarG.map { "\($0)g 糖" } ?? "糖暂无") · \(nutrition.sourceType ?? "未标注")")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if !drink.source.isEmpty {
                Text(drink.source).font(.caption2).foregroundStyle(.tertiary).lineLimit(2)
            }
        }
        .padding(.vertical, 4)
    }

    private var statusText: String {
        switch drink.status {
        case "verified": "已核验"
        case "unavailable": "暂不供应"
        default: "待核验"
        }
    }
}

private struct MenuDrinkDraft {
    let id: String?
    let existingBrandID: String?
    let name: String
    let brandName: String
    let category: String
    let aliases: String
    let status: String
    let active: Bool
    let cupTypes: String
    let sweetnessOptions: String
    let servingOptions: String
    let sourceName: String
    let sourceURL: String
    let source: String
    let nutritionPerUnit: MenuNutritionPerUnit?
}

private struct MenuDrinkEditor: View {
    @Environment(\.dismiss) private var dismiss
    let drink: MenuDrink?
    let onSave: (MenuDrinkDraft) -> Bool

    @State private var name: String
    @State private var brandName: String
    @State private var category: String
    @State private var aliases: String
    @State private var status: String
    @State private var active: Bool
    @State private var cupTypes: String
    @State private var sweetnessOptions: String
    @State private var servingOptions: String
    @State private var sourceName: String
    @State private var sourceURL: String
    @State private var source: String
    @State private var energy: String
    @State private var sugar: String
    @State private var caffeine: String
    @State private var nutritionSourceType: String
    @State private var validationMessage: String?

    init(drink: MenuDrink?, onSave: @escaping (MenuDrinkDraft) -> Bool) {
        self.drink = drink
        self.onSave = onSave
        _name = State(initialValue: drink?.name ?? "")
        _brandName = State(initialValue: drink?.brandName ?? "")
        _category = State(initialValue: drink?.category ?? "")
        _aliases = State(initialValue: drink?.aliases.joined(separator: "，") ?? "")
        _status = State(initialValue: drink?.status ?? "pending")
        _active = State(initialValue: drink?.active ?? true)
        _cupTypes = State(initialValue: drink?.cupTypes.joined(separator: "，") ?? "")
        _sweetnessOptions = State(initialValue: drink?.sweetnessOptions.joined(separator: "，") ?? "")
        _servingOptions = State(initialValue: drink?.servingOptions.joined(separator: "，") ?? "")
        _sourceName = State(initialValue: drink?.sourceName ?? "")
        _sourceURL = State(initialValue: drink?.sourceURL ?? "")
        _source = State(initialValue: drink?.source ?? "")
        _energy = State(initialValue: drink?.nutritionPerUnit?.energyKcal.map { String($0) } ?? "")
        _sugar = State(initialValue: drink?.nutritionPerUnit?.sugarG.map { String($0) } ?? "")
        _caffeine = State(initialValue: drink?.nutritionPerUnit?.caffeineMg.map { String($0) } ?? "")
        _nutritionSourceType = State(initialValue: drink?.nutritionPerUnit?.sourceType ?? "estimated")
    }

    var body: some View {
        Form {
            Section("饮品信息") {
                TextField("饮品名称", text: $name)
                TextField("品牌", text: $brandName)
                TextField("分类", text: $category)
                TextField("别名（逗号分隔）", text: $aliases)
                Toggle("在目录中使用", isOn: $active)
                Picker("菜单状态", selection: $status) {
                    Text("待核验").tag("pending")
                    Text("已核验").tag("verified")
                    Text("暂不供应").tag("unavailable")
                }
            }

            Section("规格选项") {
                TextField("杯型（逗号分隔）", text: $cupTypes)
                TextField("甜度选项（逗号分隔）", text: $sweetnessOptions)
                TextField("温度 / 冰量（逗号分隔）", text: $servingOptions)
                Text("小料不作为饮品记录选项。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Section("营养基准（每 100 ml）") {
                TextField("能量（kcal）", text: $energy).keyboardType(.decimalPad)
                TextField("糖（g）", text: $sugar).keyboardType(.decimalPad)
                TextField("咖啡因（mg）", text: $caffeine).keyboardType(.decimalPad)
                Picker("数据类型", selection: $nutritionSourceType) {
                    Text("估算值").tag("estimated")
                    Text("官方数据").tag("official")
                }
            }

            Section("来源") {
                TextField("来源名称", text: $sourceName)
                TextField("来源链接", text: $sourceURL).textInputAutocapitalization(.never).keyboardType(.URL)
                TextField("说明", text: $source, axis: .vertical)
                if status == "verified" && sourceName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && sourceURL.isEmpty {
                    Text("已核验项目需要填写来源名称或链接。")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(GanfanPalette.canvas)
        .navigationTitle(drink == nil ? "添加饮品" : "编辑饮品")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
            ToolbarItem(placement: .confirmationAction) { Button("保存", action: save) }
        }
        .alert("无法保存", isPresented: Binding(
            get: { validationMessage != nil },
            set: { if !$0 { validationMessage = nil } }
        )) {
            Button("好", role: .cancel) { validationMessage = nil }
        } message: {
            Text(validationMessage ?? "请检查填写内容。")
        }
    }

    private func save() {
        let normalizedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedBrand = brandName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedName.isEmpty, !normalizedBrand.isEmpty else {
            validationMessage = "饮品名称和品牌不能为空。"
            return
        }
        guard status != "verified" || !sourceName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !sourceURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            validationMessage = "已核验项目需要填写来源名称或链接。"
            return
        }
        let values = [energy, sugar, caffeine].map(Self.optionalNonnegativeNumber)
        guard values.allSatisfy({ $0.valid }) else {
            validationMessage = "营养数值需为空或大于等于 0 的数字。"
            return
        }
        let hasNutrition = values.contains { $0.value != nil }
        let nutrition = hasNutrition ? MenuNutritionPerUnit(
            amount: 100,
            unit: "ml",
            energyKcal: values[0].value,
            sugarG: values[1].value,
            caffeineMg: values[2].value,
            sourceType: nutritionSourceType,
            source: source.isEmpty ? sourceName : source,
            updatedAt: ISO8601DateFormatter().string(from: .now).prefix(10).description
        ) : nil
        let saved = onSave(MenuDrinkDraft(
            id: drink?.id,
            existingBrandID: drink?.brandID,
            name: normalizedName,
            brandName: normalizedBrand,
            category: category.trimmingCharacters(in: .whitespacesAndNewlines),
            aliases: aliases,
            status: status,
            active: active,
            cupTypes: cupTypes,
            sweetnessOptions: sweetnessOptions,
            servingOptions: servingOptions,
            sourceName: sourceName.trimmingCharacters(in: .whitespacesAndNewlines),
            sourceURL: sourceURL.trimmingCharacters(in: .whitespacesAndNewlines),
            source: source.trimmingCharacters(in: .whitespacesAndNewlines),
            nutritionPerUnit: nutrition
        ))
        if saved { dismiss() }
    }

    private static func optionalNonnegativeNumber(_ text: String) -> (valid: Bool, value: Double?) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return (true, nil) }
        guard let value = Double(trimmed), value.isFinite, value >= 0 else { return (false, nil) }
        return (true, value)
    }
}

private struct CupSizeDraft: Identifiable {
    let id = UUID()
    var cupType: String
    var sizeText: String
}

private struct CupSizeSettingsView: View {
    @Environment(\.dismiss) private var dismiss
    let onSave: ([MenuCupSize]) -> Void
    @State private var rows: [CupSizeDraft]
    @State private var errorMessage: String?

    init(initial: [MenuCupSize], onSave: @escaping ([MenuCupSize]) -> Void) {
        self.onSave = onSave
        _rows = State(initialValue: initial.map { CupSizeDraft(cupType: $0.cupType, sizeText: $0.sizeML.map { String($0) } ?? "") })
    }

    var body: some View {
        List {
            Section {
                ForEach($rows) { $row in
                    HStack {
                        TextField("杯型", text: $row.cupType)
                        TextField("容量 ml（可空）", text: $row.sizeText)
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.trailing)
                    }
                }
                .onDelete { rows.remove(atOffsets: $0) }
                Button("添加杯型", systemImage: "plus") {
                    rows.append(CupSizeDraft(cupType: "", sizeText: ""))
                }
            } footer: {
                Text("容量为空时仍可记录杯型，但营养换算会显示数据不足。")
            }
        }
        .scrollContentBackground(.hidden)
        .background(GanfanPalette.canvas)
        .navigationTitle("全局杯型与容量")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) { Button("保存", action: save) }
        }
        .alert("无法保存杯型", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("好", role: .cancel) { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "请检查杯型设置。")
        }
    }

    private func save() {
        let cupSizes = rows.map { row -> MenuCupSize? in
            let name = row.cupType.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty else { return nil }
            let value = row.sizeText.trimmingCharacters(in: .whitespacesAndNewlines)
            if value.isEmpty { return MenuCupSize(cupType: name) }
            guard let size = Int(value), size > 0 else { return nil }
            return MenuCupSize(cupType: name, sizeML: size)
        }
        guard cupSizes.allSatisfy({ $0 != nil }) else {
            errorMessage = "杯型名称不能为空，容量需为空或正整数。"
            return
        }
        let result = cupSizes.compactMap { $0 }
        guard Set(result.map { $0.cupType.lowercased() }).count == result.count else {
            errorMessage = "杯型名称不能重复。"
            return
        }
        onSave(result)
        dismiss()
    }
}


/// Data updates are downloaded only after an explicit user action.
struct NutritionUpdateSettingsView: View {
    @AppStorage("ganfan.nutrition.updateURL.v1") private var updateURL = ""
    @State private var currentVersion = "仅内置"
    @State private var currentCount = 0
    @State private var status = ""
    @State private var isUpdating = false

    var body: some View {
        Form {
            Section("当前营养资料") {
                LabeledContent("在线数据版本", value: currentVersion)
                LabeledContent("已安装远程记录", value: "\(currentCount) 条")
                Text("App 随安装包提供内置营养数据；更新成功后存储在本机。用户手动维护的饮品资料优先于远程版本，历史记录不会被修改。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            Section {
                TextField("HTTPS JSON 文件地址", text: $updateURL)
                    .keyboardType(.URL)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                Button {
                    Task { await update() }
                } label: {
                    HStack {
                        Text("检查并更新营养数据")
                        if isUpdating { Spacer(); ProgressView() }
                    }
                }
                .disabled(isUpdating || updateURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            } header: {
                Text("在线更新")
            } footer: {
                Text("远程文件由您自行托管；仅支持 HTTPS 和版本化营养数据包。更新异常时保留之前的本机数据。")
            }
            if !status.isEmpty {
                Section("更新结果") {
                    Text(status).font(.footnote)
                }
            }
        }
        .navigationTitle("营养数据库")
        .navigationBarTitleDisplayMode(.inline)
        .scrollContentBackground(.hidden)
        .background(GanfanPalette.canvas)
        .onAppear(perform: refresh)
    }

    private func refresh() {
        let pack = NutritionUpdateRepository().load()
        currentVersion = pack?.version ?? "仅内置"
        currentCount = pack?.entries.count ?? 0
    }

    private func update() async {
        guard let url = URL(string: updateURL.trimmingCharacters(in: .whitespacesAndNewlines)) else {
            status = "请输入合法的 HTTPS JSON 地址。"
            return
        }
        isUpdating = true
        defer { isUpdating = false }
        do {
            guard let catalogURL = Bundle.main.url(forResource: "catalog", withExtension: "json") else {
                status = "内置菜单不可用。"
                return
            }
            let bundled = try MenuCatalog.decode(Data(contentsOf: catalogURL))
            let bytes = try await NutritionUpdateClient().fetch(from: url)
            let pack = try NutritionUpdateRepository().install(bytes, bundled: bundled)
            BackupChangeTracker().markChanged()
            refresh()
            status = "已更新至 \(pack.version)：包含 \(pack.entries.count) 条远程营养数据。"
        } catch NutritionUpdateError.olderVersion {
            status = "已经是当前版本或远程版本更旧，没有覆盖本地数据。"
        } catch {
            status = "更新未完成：\(error.localizedDescription)"
        }
    }
}

private struct BrandImportSaveResult {
    let brand: MenuBrand
    let drinkCount: Int
    let skippedDrinkCount: Int
}

private struct PhoneCatalogProjectExport: Codable {
    let schemaVersion: Int
    let createdAt: String
    let brands: [MenuBrand]
    let drinks: [MenuDrink]
    let logoAssets: [PhoneCatalogLogoAsset]
}

private struct PhoneCatalogLogoAsset: Codable {
    let id: UUID
    let data: Data
}

private enum PhoneCatalogExportError: LocalizedError {
    case missingLogo(UUID)

    var errorDescription: String? {
        switch self {
        case .missingLogo(let id): "找不到品牌 Logo 文件（\(id.uuidString)）。请先检查本机存储。"
        }
    }
}

private enum BrandResearchPurpose: String, Identifiable, Equatable {
    case menu
    case logo

    var id: String { rawValue }

    func defaultQuery(for brandName: String) -> String {
        switch self {
        case .menu: "\(brandName) 官方 菜单 饮品"
        case .logo: "\(brandName) 官方 Logo"
        }
    }

    var title: String {
        switch self {
        case .menu: "搜索菜单来源"
        case .logo: "搜索品牌 Logo"
        }
    }
}

private enum BrandSearchEngine: String, CaseIterable, Identifiable {
    case baidu
    case bing

    var id: String { rawValue }

    var title: String {
        switch self {
        case .baidu: "百度"
        case .bing: "Bing"
        }
    }

    func searchURL(for query: String) -> URL? {
        var components: URLComponents?
        switch self {
        case .baidu:
            components = URLComponents(string: "https://www.baidu.com/s")
            components?.queryItems = [URLQueryItem(name: "wd", value: query)]
        case .bing:
            components = URLComponents(string: "https://www.bing.com/search")
            components?.queryItems = [URLQueryItem(name: "q", value: query)]
        }
        return components?.url
    }
}

private struct BrandLogoCandidate: Identifiable, Hashable {
    let url: String
    let alt: String
    let width: Int
    let height: Int

    var id: String { url }
}

private struct BrandWebPageCapture {
    let title: String
    let url: String
    let structuredNames: [String]
    let listNames: [String]
    let logoCandidates: [BrandLogoCandidate]

    var extractedDrinkNames: [String] {
        let sourceNames = structuredNames.isEmpty ? listNames : structuredNames
        var seen = Set<String>()
        return sourceNames.compactMap { rawValue in
            let value = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
                .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            let key = value.replacingOccurrences(of: " ", with: "").lowercased()
            guard value.count >= 2, value.count <= 48,
                  !["更多", "了解更多", "首页", "品牌故事", "联系我们", "在线客服", "立即购买", "立即下单"].contains(value),
                  !value.contains("http://"), !value.contains("https://"),
                  seen.insert(key).inserted else { return nil }
            return value
        }
        .prefix(120)
        .map { $0 }
    }
}

private enum BrandImportWizardSheet: Identifiable {
    case research(BrandResearchPurpose)
    case crop(BrandLogoCropRequest)

    var id: String {
        switch self {
        case .research(let purpose): "research-\(purpose.id)"
        case .crop(let request): "crop-\(request.id.uuidString)"
        }
    }
}

private struct BrandImportWizard: View {
    @Environment(\.dismiss) private var dismiss

    let existingBrands: [MenuBrand]
    let onSaveBrand: (String, String, [String], String, String, [String]) -> BrandImportSaveResult?
    let onSaveLogo: (MenuBrand, Data, String?) -> MenuBrand?

    @State private var brandName = ""
    @State private var category = ""
    @State private var aliases = ""
    @State private var sourceName = ""
    @State private var sourceURL = ""
    @State private var drinkNamesText = ""
    @State private var logoCandidates: [BrandLogoCandidate] = []
    @State private var selectedLogoData: Data?
    @State private var selectedLogoSourceURL: String?
    @State private var isLoadingLogo = false
    @State private var validationMessage: String?
    @State private var savedResult: BrandImportSaveResult?
    @State private var activeSheet: BrandImportWizardSheet?

    var body: some View {
        Form {
            if let savedResult {
                Section("已添加到饮品目录") {
                    Label(savedResult.brand.name, systemImage: "checkmark.circle.fill")
                        .foregroundStyle(GanfanPalette.forest)
                    Text("新增 \(savedResult.drinkCount) 款菜单候选\(savedResult.skippedDrinkCount == 0 ? "" : "，跳过重复项 \(savedResult.skippedDrinkCount) 款")。候选均标记为待核验，来源已保留。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    if savedResult.brand.logoImageID == nil {
                        Text("没有选择 Logo；之后仍可在“品牌 Logo”中添加或替换。")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
            } else {
                brandSection
                researchSection
                menuDraftSection
                logoCandidatesSection
            }

            if let validationMessage {
                Section {
                    Label(validationMessage, systemImage: "exclamationmark.triangle")
                        .font(.footnote)
                        .foregroundStyle(.orange)
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(GanfanPalette.canvas)
        .tint(GanfanPalette.forest)
        .navigationTitle(savedResult == nil ? "新增品牌" : "品牌已保存")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button(savedResult == nil ? "取消" : "完成") { dismiss() }
            }
            if savedResult == nil {
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") { save() }
                        .disabled(brandName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
        .sheet(item: $activeSheet) { sheet in
            NavigationStack {
                switch sheet {
                case .research(let purpose):
                    BrandWebResearchSheet(brandName: brandName, purpose: purpose) { capture in
                        accept(capture, for: purpose)
                    }
                case .crop(let request):
                    BrandLogoCropEditor(
                        image: request.image,
                        brandName: savedResult?.brand.name ?? brandName,
                        onSave: { data in
                            guard let brand = savedResult?.brand else { return nil }
                            return onSaveLogo(brand, data, selectedLogoSourceURL)
                        },
                        onComplete: { updatedBrand in
                            guard let result = savedResult else { return }
                            savedResult = BrandImportSaveResult(
                                brand: updatedBrand,
                                drinkCount: result.drinkCount,
                                skippedDrinkCount: result.skippedDrinkCount
                            )
                        }
                    )
                }
            }
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
        }
    }

    private var brandSection: some View {
        Section("品牌信息") {
            TextField("品牌名称", text: $brandName)
                .textInputAutocapitalization(.never)
            TextField("分类（可选，如茶饮、咖啡）", text: $category)
            TextField("别名（用逗号分隔，可选）", text: $aliases)
            Text("新品牌和从网页整理出的饮品都会先标记为待核验。")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    private var researchSection: some View {
        Section {
            Button {
                activeSheet = .research(.menu)
            } label: {
                Label("搜索菜单和饮品", systemImage: "magnifyingglass")
            }
            Button {
                activeSheet = .research(.logo)
            } label: {
                Label("搜索品牌 Logo", systemImage: "photo.magnifyingglass")
            }
            if !sourceURL.isEmpty {
                Label(sourceName.isEmpty ? sourceURL : sourceName, systemImage: "link")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                Text(sourceURL)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .textSelection(.enabled)
                    .lineLimit(2)
            }
        } header: {
            Text("网页资料")
        } footer: {
            Text("网页由百度或 Bing 直接打开；内容只在本机按网页结构提取，不发送给 AI。")
        }
    }

    private var menuDraftSection: some View {
        Section("菜单草稿") {
            TextEditor(text: $drinkNamesText)
                .frame(minHeight: 150)
                .accessibilityLabel("每行一个饮品名称")
            Text("从网页识别到的名称会填在这里。可编辑、删除或补充；每行一款。保存后保留页面来源并标记为待核验。")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    private var logoCandidatesSection: some View {
        Section {
            if let selectedLogoData, let image = UIImage(data: selectedLogoData) {
                HStack(spacing: 12) {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 52, height: 52)
                        .background(.white, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    VStack(alignment: .leading, spacing: 3) {
                        Text("已选择 Logo 图片")
                            .font(.subheadline.weight(.medium))
                        Text("保存后可继续调整裁切")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("清除") {
                        self.selectedLogoData = nil
                        selectedLogoSourceURL = nil
                    }
                    .font(.caption)
                }
            }
            if logoCandidates.isEmpty {
                Text("先搜索 Logo 网页，再点“读取当前网页”采集图片候选。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 76), spacing: 10)], spacing: 10) {
                    ForEach(logoCandidates.prefix(18)) { candidate in
                        BrandLogoCandidateTile(
                            candidate: candidate,
                            selected: selectedLogoSourceURL == candidate.url,
                            onSelect: { downloadLogo(candidate) }
                        )
                    }
                }
            }
            if isLoadingLogo {
                HStack(spacing: 8) {
                    ProgressView()
                    Text("正在读取图片…")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
        } header: {
            Text("Logo 候选")
        } footer: {
            Text("选定后可在保存前预览并调整裁切；图片会下载到本机，之后离线显示。")
        }
    }

    private func accept(_ capture: BrandWebPageCapture, for purpose: BrandResearchPurpose) {
        validationMessage = nil
        if purpose == .menu {
            sourceName = capture.title
            sourceURL = capture.url
            if !capture.extractedDrinkNames.isEmpty {
                drinkNamesText = capture.extractedDrinkNames.joined(separator: "\n")
            }
        }
        if !capture.logoCandidates.isEmpty {
            logoCandidates = capture.logoCandidates
        } else if purpose == .logo {
            validationMessage = "当前页面没有可识别的图片。可以继续浏览到品牌官网或产品页后再读取。"
        }
    }

    private func downloadLogo(_ candidate: BrandLogoCandidate) {
        guard let url = URL(string: candidate.url), url.scheme?.lowercased() == "https" else {
            validationMessage = "Logo 图片必须来自 HTTPS 网页。"
            return
        }
        isLoadingLogo = true
        validationMessage = nil
        Task {
            defer { isLoadingLogo = false }
            do {
                var request = URLRequest(url: url)
                request.timeoutInterval = 25
                request.setValue("image/*", forHTTPHeaderField: "Accept")
                let (data, response) = try await URLSession.shared.data(for: request)
                guard data.count <= 20_000_000,
                      (response as? HTTPURLResponse).map({ (200..<300).contains($0.statusCode) }) == true,
                      UIImage(data: data) != nil,
                      let prepared = await Task.detached(priority: .utility, operation: {
                          BrandLogoImageProcessor.downsampledPNG(from: data)
                      }).value else {
                    throw BrandLogoImageError.invalidImage
                }
                selectedLogoData = prepared
                selectedLogoSourceURL = candidate.url
            } catch {
                validationMessage = "无法读取这张图片：\(error.localizedDescription)"
            }
        }
    }

    private func save() {
        let name = brandName.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedName = Self.normalize(name)
        guard !normalizedName.isEmpty else {
            validationMessage = "请先填写品牌名称。"
            return
        }
        guard !existingBrands.contains(where: { Self.normalize($0.name) == normalizedName }) else {
            validationMessage = "这个品牌已经在目录中，可以直接从“品牌 Logo”添加图片，或在饮品目录中添加饮品。"
            return
        }
        let names = drinkNamesText.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        let aliasValues = aliases.split(whereSeparator: { ",，、".contains($0) })
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        guard let result = onSaveBrand(
            name,
            category,
            Array(Set(aliasValues)),
            sourceName,
            sourceURL,
            names
        ) else {
            validationMessage = "品牌资料没有保存成功；请检查目录状态后重试。"
            return
        }
        savedResult = result
        if let selectedLogoData, let image = UIImage(data: selectedLogoData) {
            activeSheet = .crop(BrandLogoCropRequest(image: image))
        } else {
            dismiss()
        }
    }

    private static func normalize(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: " ", with: "")
            .lowercased()
    }
}

private struct BrandLogoCandidateTile: View {
    let candidate: BrandLogoCandidate
    let selected: Bool
    let onSelect: () -> Void

    private var imagePreview: some View {
        AsyncImage(url: URL(string: candidate.url)) { phase in
            if let image = phase.image {
                image.resizable().scaledToFit()
            } else if phase.error != nil {
                Image(systemName: "photo.badge.exclamationmark")
                    .resizable()
                    .scaledToFit()
                    .padding(18)
            } else {
                ProgressView()
            }
        }
        .frame(width: 76, height: 76)
        .background(.white, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    var body: some View {
        Button(action: onSelect) {
            VStack(spacing: 4) {
                imagePreview
                Text(candidate.alt.isEmpty ? "网页图片" : candidate.alt)
                    .font(.caption2)
                    .lineLimit(2)
                    .foregroundStyle(.secondary)
            }
            .padding(4)
            .overlay {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(selected ? GanfanPalette.forest : .clear, lineWidth: 2)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("选择 Logo：\(candidate.alt.isEmpty ? "网页图片" : candidate.alt)")
    }
}

private struct BrandWebResearchSheet: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var browser: BrandResearchBrowser
    @State private var query: String
    @State private var engine: BrandSearchEngine = .baidu
    @State private var errorMessage: String?
    @State private var isCapturing = false

    let purpose: BrandResearchPurpose
    let onUsePage: (BrandWebPageCapture) -> Void

    init(brandName: String, purpose: BrandResearchPurpose, onUsePage: @escaping (BrandWebPageCapture) -> Void) {
        self.purpose = purpose
        self.onUsePage = onUsePage
        _query = State(initialValue: purpose.defaultQuery(for: brandName))
        _browser = StateObject(wrappedValue: BrandResearchBrowser())
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                TextField("搜索品牌或菜单", text: $query)
                    .textInputAutocapitalization(.never)
                    .submitLabel(.search)
                    .onSubmit(search)
                    .padding(.horizontal, 12)
                    .frame(height: 42)
                    .background(GanfanPalette.card, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                Button("搜索", action: search)
                    .buttonStyle(.borderedProminent)
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 8)

            HStack {
                Picker("搜索引擎", selection: $engine) {
                    ForEach(BrandSearchEngine.allCases) { option in
                        Text(option.title).tag(option)
                    }
                }
                .pickerStyle(.segmented)
                Spacer()
                if browser.isLoading { ProgressView().controlSize(.small) }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 8)

            BrandResearchWebView(browser: browser)
                .background(.white)
                .overlay(alignment: .top) {
                    if let errorMessage {
                        Text(errorMessage)
                            .font(.footnote)
                            .foregroundStyle(.orange)
                            .padding(8)
                            .frame(maxWidth: .infinity)
                            .background(.regularMaterial)
                    }
                }

            HStack(spacing: 14) {
                Button { browser.goBack() } label: { Image(systemName: "chevron.backward") }
                    .disabled(!browser.canGoBack)
                    .accessibilityLabel("后退")
                Button { browser.goForward() } label: { Image(systemName: "chevron.forward") }
                    .disabled(!browser.canGoForward)
                    .accessibilityLabel("前进")
                Button { browser.reload() } label: { Image(systemName: "arrow.clockwise") }
                    .accessibilityLabel("重新载入")
                Spacer(minLength: 6)
                Button {
                    capturePage()
                } label: {
                    if isCapturing {
                        ProgressView().controlSize(.small)
                    } else {
                        Label("读取当前网页", systemImage: "text.viewfinder")
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(isCapturing || browser.currentURL == nil)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(GanfanPalette.canvas)
        }
        .navigationTitle(purpose.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("返回") { dismiss() }
            }
        }
        .onAppear(perform: search)
    }

    private func search() {
        errorMessage = nil
        browser.search(query: query, engine: engine)
    }

    private func capturePage() {
        isCapturing = true
        errorMessage = nil
        Task {
            defer { isCapturing = false }
            do {
                let capture = try await browser.captureCurrentPage()
                onUsePage(capture)
                dismiss()
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
}

private struct BrandResearchWebView: UIViewRepresentable {
    @ObservedObject var browser: BrandResearchBrowser

    func makeUIView(context: Context) -> WKWebView { browser.webView }
    func updateUIView(_ uiView: WKWebView, context: Context) {}
}

@MainActor
private final class BrandResearchBrowser: NSObject, ObservableObject, WKNavigationDelegate {
    @Published private(set) var isLoading = false
    @Published private(set) var currentURL: URL?
    @Published private(set) var canGoBack = false
    @Published private(set) var canGoForward = false

    let webView: WKWebView

    override init() {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        webView = WKWebView(frame: .zero, configuration: configuration)
        super.init()
        webView.navigationDelegate = self
        webView.allowsBackForwardNavigationGestures = true
    }

    func search(query: String, engine: BrandSearchEngine) {
        guard let url = engine.searchURL(for: query.trimmingCharacters(in: .whitespacesAndNewlines)),
              !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        webView.load(URLRequest(url: url))
        refreshState()
    }

    func goBack() { if webView.canGoBack { webView.goBack() } }
    func goForward() { if webView.canGoForward { webView.goForward() } }
    func reload() { webView.reload() }

    func captureCurrentPage() async throws -> BrandWebPageCapture {
        guard let pageURL = webView.url,
              ["https", "http"].contains(pageURL.scheme?.lowercased() ?? "") else {
            throw BrandResearchBrowserError.noPage
        }
        let script = #"""
        (() => {
          const clean = value => String(value || '').replace(/\s+/g, ' ').trim();
          const absolute = raw => { try { return new URL(raw, location.href).href; } catch { return ''; } };
          const names = [];
          const visit = value => {
            if (Array.isArray(value)) { value.forEach(visit); return; }
            if (!value || typeof value !== 'object') return;
            const types = Array.isArray(value['@type']) ? value['@type'] : [value['@type'] || ''];
            const name = clean(value.name || value.headline);
            if (name && types.some(type => ['MenuItem', 'Product', 'ProductGroup'].includes(String(type)))) names.push(name);
            Object.values(value).forEach(visit);
          };
          document.querySelectorAll('script[type="application/ld+json"]').forEach(script => {
            try { visit(JSON.parse(script.textContent || 'null')); } catch {}
          });
          const visible = element => {
            const style = getComputedStyle(element);
            return style.display !== 'none' && style.visibility !== 'hidden' && (element.offsetWidth || element.offsetHeight);
          };
          const listNames = Array.from(document.querySelectorAll(
            'main li, article li, [role="main"] li, [class*="menu" i] li, [class*="product" i] [class*="name" i], [itemprop="name"], main h2, main h3'
          )).filter(visible).map(element => clean(element.innerText || element.getAttribute('aria-label') || element.title)).filter(Boolean);
          const images = [];
          const addImage = (raw, alt, width = 0, height = 0) => {
            const url = absolute(raw);
            if (!url || !/^https:\/\//i.test(url)) return;
            if (!images.some(image => image.url === url)) images.push({ url, alt: clean(alt), width: Number(width) || 0, height: Number(height) || 0 });
          };
          addImage(document.querySelector('meta[property="og:image"]')?.content || document.querySelector('meta[name="twitter:image"]')?.content, '网页分享图');
          Array.from(document.images).filter(image => visible(image) && Math.max(image.naturalWidth, image.naturalHeight, image.width, image.height) >= 72)
            .forEach(image => addImage(image.currentSrc || image.src, image.alt, image.naturalWidth || image.width, image.naturalHeight || image.height));
          document.querySelectorAll('link[rel~="icon"]').forEach(icon => addImage(icon.href, '网站图标'));
          return {
            title: clean(document.title || document.querySelector('h1')?.innerText),
            url: location.href,
            structuredNames: Array.from(new Set(names)).slice(0, 150),
            listNames: Array.from(new Set(listNames)).slice(0, 200),
            logoCandidates: images.slice(0, 24)
          };
        })()
        """#
        guard let result = try await webView.evaluateJavaScript(script) as? [String: Any] else {
            throw BrandResearchBrowserError.pageReadFailed
        }
        let candidates = (result["logoCandidates"] as? [[String: Any]] ?? []).compactMap { item -> BrandLogoCandidate? in
            guard let url = item["url"] as? String, !url.isEmpty else { return nil }
            return BrandLogoCandidate(
                url: url,
                alt: item["alt"] as? String ?? "",
                width: item["width"] as? Int ?? 0,
                height: item["height"] as? Int ?? 0
            )
        }
        return BrandWebPageCapture(
            title: result["title"] as? String ?? webView.title ?? pageURL.host ?? "网页来源",
            url: result["url"] as? String ?? pageURL.absoluteString,
            structuredNames: result["structuredNames"] as? [String] ?? [],
            listNames: result["listNames"] as? [String] ?? [],
            logoCandidates: candidates
        )
    }

    func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
        isLoading = true
        refreshState()
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        isLoading = false
        refreshState()
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        isLoading = false
        refreshState()
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        isLoading = false
        refreshState()
    }

    func webView(
        _ webView: WKWebView,
        decidePolicyFor navigationAction: WKNavigationAction
    ) async -> WKNavigationActionPolicy {
        guard let scheme = navigationAction.request.url?.scheme?.lowercased(),
              ["https", "http"].contains(scheme) else {
            return .cancel
        }
        return .allow
    }

    private func refreshState() {
        currentURL = webView.url
        canGoBack = webView.canGoBack
        canGoForward = webView.canGoForward
    }
}

private enum BrandResearchBrowserError: LocalizedError {
    case noPage
    case pageReadFailed

    var errorDescription: String? {
        switch self {
        case .noPage: "请先打开一个网页，再读取页面内容。"
        case .pageReadFailed: "网页暂时无法读取；可以继续浏览，也可以手动粘贴饮品名称。"
        }
    }
}
