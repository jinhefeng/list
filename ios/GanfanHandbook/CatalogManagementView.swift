import SwiftData
import SwiftUI

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

struct CatalogManagementView: View {
    @Query private var storedRecords: [StoredJournalRecord]
    @State private var catalog: MenuCatalog?
    @State private var userState = MenuCatalogUserState()
    @State private var query = ""
    @State private var selectedBrandID = ""
    @State private var selectedCategory = ""
    @State private var isShowingEditor = false
    @State private var editingDrink: MenuDrink?
    @State private var selectedForDeletion: MenuDrink?
    @State private var isConfirmingDeletion = false
    @State private var errorMessage: String?

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

    private var referencedDrinkIDs: Set<String> {
        Set(storedRecords.compactMap { storedRecord -> String? in
            guard let record = try? storedRecord.decodeRecord(), case .drink(let drink) = record else { return nil }
            return drink.drinkID.isEmpty ? nil : drink.drinkID
        })
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
            }

            Section {
                NavigationLink {
                    CupSizeSettingsView(initial: userState.globalCupSizes, onSave: saveCupSizes)
                } label: {
                    Label("全局杯型与容量", systemImage: "cup.and.saucer")
                }
                LabeledContent("菜单版本", value: catalog?.version ?? "不可用")
            } header: {
                Text("目录设置")
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
                        editingDrink = drink
                        isShowingEditor = true
                    } label: {
                        CatalogDrinkRow(drink: drink)
                    }
                    .buttonStyle(.plain)
                    .contextMenu {
                        Button("编辑", systemImage: "pencil") {
                            editingDrink = drink
                            isShowingEditor = true
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
                    editingDrink = nil
                    isShowingEditor = true
                } label: {
                    Image(systemName: "plus")
                }
                .accessibilityLabel("添加饮品")
            }
        }
        .task { loadCatalog() }
        .sheet(isPresented: $isShowingEditor, onDismiss: loadCatalog) {
            NavigationStack {
                MenuDrinkEditor(drink: editingDrink, onSave: saveDrink)
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

    private func loadCatalog() {
        guard let url = Bundle.main.url(forResource: "catalog", withExtension: "json"),
              let data = try? Data(contentsOf: url) else {
            errorMessage = "内置菜单文件不可用；已保存的本地菜单数据未更改。"
            return
        }
        do {
            let bundled = try MenuCatalog.decode(data)
            userState = try repository.loadUserState()
            catalog = try repository.catalog(from: bundled)
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
                deletedDrinkIDs: userState.deletedDrinkIDs.subtracting([drinkID]),
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

    private func deleteSelectedDrink() {
        guard let drink = selectedForDeletion else { return }
        guard !referencedDrinkIDs.contains(drink.id) else {
            errorMessage = "历史记录正在引用这款饮品。先编辑相关记录，再删除菜单项目。"
            return
        }
        let state = MenuCatalogUserState(
            brands: userState.brands,
            drinks: userState.drinks.filter { $0.id != drink.id },
            deletedDrinkIDs: userState.deletedDrinkIDs.union([drink.id]),
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

private struct CatalogDrinkRow: View {
    let drink: MenuDrink

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text(drink.name).font(.headline).foregroundStyle(GanfanPalette.ink)
                Spacer(minLength: 8)
                Text(statusText)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(drink.status == "verified" ? GanfanPalette.forest : GanfanPalette.leaf)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(GanfanPalette.paleLeaf.opacity(0.72), in: Capsule())
            }
            Text([drink.brandName, drink.category].filter { !$0.isEmpty }.joined(separator: " · "))
                .font(.subheadline)
                .foregroundStyle(.secondary)
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
            Section("在线更新") {
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
            refresh()
            status = "已更新至 \(pack.version)：包含 \(pack.entries.count) 条远程营养数据。"
        } catch NutritionUpdateError.olderVersion {
            status = "已经是当前版本或远程版本更旧，没有覆盖本地数据。"
        } catch {
            status = "更新未完成：\(error.localizedDescription)"
        }
    }
}
