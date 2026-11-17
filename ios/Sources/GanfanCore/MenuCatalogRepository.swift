import Foundation

public enum MenuCatalogRepositoryError: Error, Equatable {
    case invalidSavedState
    case emptyBrandIdentifier
    case emptyDrinkIdentifier
    case emptyDrinkName
    case duplicateIdentifier(String)
    case invalidCupSize(String)
}

public struct MenuCatalogUserState: Codable, Equatable, Sendable {
    public let brands: [MenuBrand]
    public let drinks: [MenuDrink]
    public let deletedDrinkIDs: Set<String>
    public let globalCupSizes: [MenuCupSize]

    public init(
        brands: [MenuBrand] = [],
        drinks: [MenuDrink] = [],
        deletedDrinkIDs: Set<String> = [],
        globalCupSizes: [MenuCupSize] = Self.defaultCupSizes
    ) {
        self.brands = brands
        self.drinks = drinks
        self.deletedDrinkIDs = deletedDrinkIDs
        self.globalCupSizes = globalCupSizes
    }

    private enum CodingKeys: String, CodingKey {
        case brands, drinks, deletedDrinkIDs, globalCupSizes
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        brands = try container.decodeIfPresent([MenuBrand].self, forKey: .brands) ?? []
        drinks = try container.decodeIfPresent([MenuDrink].self, forKey: .drinks) ?? []
        deletedDrinkIDs = try container.decodeIfPresent(Set<String>.self, forKey: .deletedDrinkIDs) ?? []
        globalCupSizes = try container.decodeIfPresent([MenuCupSize].self, forKey: .globalCupSizes) ?? Self.defaultCupSizes
    }

    public static let defaultCupSizes = [
        MenuCupSize(cupType: "小杯", sizeML: 350),
        MenuCupSize(cupType: "中杯", sizeML: 500),
        MenuCupSize(cupType: "大杯", sizeML: 650),
        MenuCupSize(cupType: "超大杯", sizeML: 750)
    ]

    public func validate() throws {
        try MenuCatalogRepository.validate(self)
    }

    public static func restoredCatalogOverlay(
        from catalog: MenuCatalog,
        settings: MenuCatalogUserState?
    ) -> MenuCatalogUserState {
        let brands = catalog.brands.map { brand in
            MenuBrand(
                id: brand.id,
                name: brand.name,
                aliases: brand.aliases,
                category: brand.category,
                source: brand.source,
                sourceName: brand.sourceName,
                sourceURL: brand.sourceURL,
                updatedAt: brand.updatedAt,
                status: brand.status,
                active: brand.active,
                logoSymbol: brand.logoSymbol,
                logoAssetName: brand.logoAssetName,
                logoImageID: brand.logoImageID,
                logoIsOverridden: brand.logoIsOverridden,
                logoURL: brand.logoURL,
                logoSourceURL: brand.logoSourceURL,
                localOverride: true
            )
        }
        let drinks = catalog.drinks.map { drink in
            MenuDrink(
                id: drink.id,
                legacyIDs: drink.legacyIDs,
                brandID: drink.brandID,
                brandName: drink.brandName,
                name: drink.name,
                aliases: drink.aliases,
                category: drink.category,
                source: drink.source,
                sourceType: drink.sourceType,
                sourceName: drink.sourceName,
                sourceURL: drink.sourceURL,
                updatedAt: drink.updatedAt,
                status: drink.status,
                active: drink.active,
                cupTypes: drink.cupTypes,
                cupSizes: drink.cupSizes,
                sizesML: drink.sizesML,
                sweetnessOptions: drink.sweetnessOptions,
                servingOptions: drink.servingOptions,
                nutritionPerUnit: drink.nutritionPerUnit,
                nutritionVariants: drink.nutritionVariants,
                menuEntries: drink.menuEntries,
                localOverride: true,
                custom: drink.custom
            )
        }
        return MenuCatalogUserState(
            brands: brands,
            drinks: drinks,
            deletedDrinkIDs: settings?.deletedDrinkIDs ?? [],
            globalCupSizes: settings?.globalCupSizes ?? Self.defaultCupSizes
        )
    }

    /// Reattaches older local records to uniquely matching packaged brands and menus.
    /// Exact IDs win; name matching is limited to the packaged display name and declared aliases.
    public func reconciled(to packaged: MenuCatalog) -> MenuCatalogUserState {
        var targetsByLocalBrandID: [String: MenuBrand] = [:]
        for brand in brands {
            if let exact = packaged.brands.first(where: { $0.id == brand.id }) {
                targetsByLocalBrandID[brand.id] = exact
                continue
            }
            let localNames = Set(([brand.name] + brand.aliases).map(Self.normalizedIdentity))
            let matches = packaged.brands.filter { candidate in
                !localNames.isDisjoint(with: Set(([candidate.name] + candidate.aliases).map(Self.normalizedIdentity)))
            }
            if matches.count == 1, let match = matches.first {
                targetsByLocalBrandID[brand.id] = match
            }
        }

        let brandTargets = Dictionary(uniqueKeysWithValues: targetsByLocalBrandID.map { ($0.key, $0.value.id) })
        let packagedBrandsByID = Dictionary(uniqueKeysWithValues: packaged.brands.map { ($0.id, $0) })
        var brandGroups: [String: [MenuBrand]] = [:]
        for brand in brands {
            let targetID = brandTargets[brand.id] ?? brand.id
            brandGroups[targetID, default: []].append(brand)
        }
        let reconciledBrands = brandGroups.keys.sorted().compactMap { targetID -> MenuBrand? in
            guard let group = brandGroups[targetID], let preferred = group.first(where: { $0.id == targetID }) ?? group.first else {
                return nil
            }
            guard let packagedBrand = packagedBrandsByID[targetID] else {
                return preferred
            }
            if group.count == 1, preferred.id == targetID {
                return preferred
            }

            let customLogoBrand = group.first(where: { $0.id == targetID && $0.logoIsOverridden && $0.logoImageID != nil })
                ?? group.first(where: { $0.logoIsOverridden && $0.logoImageID != nil })
            let aliases = Self.uniqueStrings(
                group.flatMap { [$0.name] + $0.aliases } + packagedBrand.aliases
            ).filter {
                Self.normalizedIdentity($0) != Self.normalizedIdentity(preferred.id == targetID ? preferred.name : packagedBrand.name)
            }
            return MenuBrand(
                id: targetID,
                name: preferred.id == targetID ? preferred.name : packagedBrand.name,
                aliases: aliases,
                category: preferred.category.isEmpty ? packagedBrand.category : preferred.category,
                source: preferred.source.isEmpty ? packagedBrand.source : preferred.source,
                sourceName: preferred.sourceName.isEmpty ? packagedBrand.sourceName : preferred.sourceName,
                sourceURL: preferred.sourceURL.isEmpty ? packagedBrand.sourceURL : preferred.sourceURL,
                updatedAt: preferred.updatedAt.isEmpty ? packagedBrand.updatedAt : preferred.updatedAt,
                status: preferred.status,
                active: preferred.active,
                logoSymbol: customLogoBrand == nil ? nil : customLogoBrand?.logoSymbol,
                logoAssetName: nil,
                logoImageID: customLogoBrand?.logoImageID,
                logoIsOverridden: customLogoBrand != nil,
                logoURL: customLogoBrand?.logoURL,
                logoSourceURL: customLogoBrand?.logoSourceURL ?? packagedBrand.logoSourceURL,
                localOverride: true
            )
        }

        let relevantLocalDrinks = drinks.filter { $0.localOverride || $0.custom }
        let irrelevantLocalDrinks = drinks.filter { !$0.localOverride && !$0.custom }
        var groupedLocalDrinks: [String: [MenuDrink]] = [:]
        for drink in relevantLocalDrinks {
            let targetBrandID = brandTargets[drink.brandID] ?? drink.brandID
            let key = Self.drinkIdentity(brandID: targetBrandID, name: drink.name)
            groupedLocalDrinks[key, default: []].append(MenuDrink(
                id: drink.id,
                legacyIDs: drink.legacyIDs,
                brandID: targetBrandID,
                brandName: packagedBrandsByID[targetBrandID]?.name ?? drink.brandName,
                name: drink.name,
                aliases: drink.aliases,
                category: drink.category,
                source: drink.source,
                sourceType: drink.sourceType,
                sourceName: drink.sourceName,
                sourceURL: drink.sourceURL,
                updatedAt: drink.updatedAt,
                status: drink.status,
                active: drink.active,
                cupTypes: drink.cupTypes,
                cupSizes: drink.cupSizes,
                sizesML: drink.sizesML,
                sweetnessOptions: drink.sweetnessOptions,
                servingOptions: drink.servingOptions,
                nutritionPerUnit: drink.nutritionPerUnit,
                nutritionVariants: drink.nutritionVariants,
                menuEntries: drink.menuEntries,
                localOverride: drink.localOverride,
                custom: drink.custom
            ))
        }

        let packagedDrinksByIdentity = Dictionary(grouping: packaged.drinks) {
            Self.drinkIdentity(brandID: $0.brandID, name: $0.name)
        }
        var reconciledDrinks: [MenuDrink] = []
        for key in groupedLocalDrinks.keys.sorted() {
            guard let localGroup = groupedLocalDrinks[key], var merged = localGroup.first else { continue }
            for localDuplicate in localGroup.dropFirst() {
                merged = Self.mergingDrink(merged, with: localDuplicate)
            }
            for packagedDrink in packagedDrinksByIdentity[key] ?? [] {
                merged = Self.mergingDrink(merged, with: packagedDrink)
            }
            reconciledDrinks.append(merged)
        }

        return MenuCatalogUserState(
            brands: reconciledBrands,
            drinks: reconciledDrinks + irrelevantLocalDrinks,
            deletedDrinkIDs: deletedDrinkIDs,
            globalCupSizes: globalCupSizes
        )
    }

    private static func normalizedIdentity(_ value: String) -> String {
        value.precomposedStringWithCanonicalMapping
            .components(separatedBy: .whitespacesAndNewlines)
            .joined()
            .lowercased()
    }

    private static func drinkIdentity(brandID: String, name: String) -> String {
        "\(brandID)|\(normalizedIdentity(name))"
    }

    private static func uniqueStrings(_ values: [String]) -> [String] {
        var seen = Set<String>()
        return values.filter { value in
            let key = normalizedIdentity(value)
            return !key.isEmpty && seen.insert(key).inserted
        }
    }

    private static func mergedCupSizes(_ preferred: [MenuCupSize], _ fallback: [MenuCupSize]) -> [MenuCupSize] {
        var result = preferred
        for size in fallback {
            if let index = result.firstIndex(where: { normalizedIdentity($0.cupType) == normalizedIdentity(size.cupType) }) {
                if result[index].sizeML == nil, let sizeML = size.sizeML {
                    result[index] = MenuCupSize(cupType: result[index].cupType, sizeML: sizeML)
                }
            } else {
                result.append(size)
            }
        }
        return result
    }

    private static func mergingDrink(_ preferred: MenuDrink, with fallback: MenuDrink) -> MenuDrink {
        let primaryID = preferred.id
        let legacyIDs = uniqueStrings(
            preferred.legacyIDs + fallback.legacyIDs + (fallback.id == primaryID ? [] : [fallback.id])
        ).filter { $0 != primaryID }
        let nutritionVariants = mergeNutritionVariants(preferred.nutritionVariants, fallback.nutritionVariants)
        return MenuDrink(
            id: primaryID,
            legacyIDs: legacyIDs,
            brandID: preferred.brandID,
            brandName: preferred.brandName.isEmpty ? fallback.brandName : preferred.brandName,
            name: preferred.name.isEmpty ? fallback.name : preferred.name,
            aliases: uniqueStrings(preferred.aliases + fallback.aliases + (preferred.name == fallback.name ? [] : [fallback.name])),
            category: preferred.category.isEmpty ? fallback.category : preferred.category,
            source: preferred.source.isEmpty ? fallback.source : preferred.source,
            sourceType: preferred.sourceType.isEmpty ? fallback.sourceType : preferred.sourceType,
            sourceName: preferred.sourceName.isEmpty ? fallback.sourceName : preferred.sourceName,
            sourceURL: preferred.sourceURL.isEmpty ? fallback.sourceURL : preferred.sourceURL,
            updatedAt: preferred.updatedAt.isEmpty ? fallback.updatedAt : preferred.updatedAt,
            status: preferred.status.isEmpty ? fallback.status : preferred.status,
            active: preferred.active,
            cupTypes: uniqueStrings(preferred.cupTypes + fallback.cupTypes),
            cupSizes: mergedCupSizes(preferred.cupSizes, fallback.cupSizes),
            sizesML: uniqueIntegers(preferred.sizesML + fallback.sizesML),
            sweetnessOptions: uniqueStrings(preferred.sweetnessOptions + fallback.sweetnessOptions),
            servingOptions: uniqueStrings(preferred.servingOptions + fallback.servingOptions),
            nutritionPerUnit: mergeNutritionPerUnit(preferred.nutritionPerUnit, fallback.nutritionPerUnit),
            nutritionVariants: nutritionVariants,
            menuEntries: preferred.menuEntries + fallback.menuEntries.filter { !preferred.menuEntries.contains($0) },
            localOverride: preferred.localOverride || fallback.localOverride,
            custom: preferred.custom || fallback.custom
        )
    }

    private static func mergeNutritionPerUnit(
        _ preferred: MenuNutritionPerUnit?,
        _ fallback: MenuNutritionPerUnit?
    ) -> MenuNutritionPerUnit? {
        guard let preferred else { return fallback }
        guard let fallback else { return preferred }
        guard preferred.amount == fallback.amount,
              normalizedIdentity(preferred.unit) == normalizedIdentity(fallback.unit) else {
            return preferred
        }
        return MenuNutritionPerUnit(
            amount: preferred.amount,
            unit: preferred.unit,
            energyKcal: preferred.energyKcal ?? fallback.energyKcal,
            sugarG: preferred.sugarG ?? fallback.sugarG,
            caffeineMg: preferred.caffeineMg ?? fallback.caffeineMg,
            proteinG: preferred.proteinG ?? fallback.proteinG,
            fatG: preferred.fatG ?? fallback.fatG,
            carbohydrateG: preferred.carbohydrateG ?? fallback.carbohydrateG,
            sourceType: preferred.sourceType ?? fallback.sourceType,
            source: preferred.source ?? fallback.source,
            updatedAt: preferred.updatedAt ?? fallback.updatedAt
        )
    }

    private static func uniqueIntegers(_ values: [Int]) -> [Int] {
        var seen = Set<Int>()
        return values.filter { seen.insert($0).inserted }
    }

    private static func mergeNutritionVariants(
        _ preferred: [MenuNutritionVariant],
        _ fallback: [MenuNutritionVariant]
    ) -> [MenuNutritionVariant] {
        var result = preferred
        for variant in fallback {
            let key = nutritionVariantIdentity(variant)
            if let index = result.firstIndex(where: { nutritionVariantIdentity($0) == key }) {
                let existing = result[index]
                result[index] = MenuNutritionVariant(
                    cupType: existing.cupType ?? variant.cupType,
                    sizeML: existing.sizeML ?? variant.sizeML,
                    sweetness: existing.sweetness ?? variant.sweetness,
                    servingOption: existing.servingOption ?? variant.servingOption,
                    temperature: existing.temperature ?? variant.temperature,
                    ice: existing.ice ?? variant.ice,
                    toppings: existing.toppings ?? variant.toppings,
                    energyKcal: existing.energyKcal ?? variant.energyKcal,
                    sugarG: existing.sugarG ?? variant.sugarG,
                    caffeineMg: existing.caffeineMg ?? variant.caffeineMg,
                    proteinG: existing.proteinG ?? variant.proteinG,
                    fatG: existing.fatG ?? variant.fatG,
                    carbohydrateG: existing.carbohydrateG ?? variant.carbohydrateG,
                    sourceType: existing.sourceType ?? variant.sourceType,
                    source: existing.source ?? variant.source,
                    sourceURL: existing.sourceURL ?? variant.sourceURL,
                    updatedAt: existing.updatedAt ?? variant.updatedAt
                )
            } else {
                result.append(variant)
            }
        }
        return result
    }

    private static func nutritionVariantIdentity(_ variant: MenuNutritionVariant) -> String {
        [variant.cupType ?? "", variant.sizeML.map(String.init) ?? "", variant.sweetness ?? "",
         variant.servingOption ?? "", variant.temperature ?? "", variant.ice ?? "",
         (variant.toppings ?? []).joined(separator: ",")]
            .map(normalizedIdentity)
            .joined(separator: "|")
    }
}

/// Owns the local catalog overlay. A future shared-list repository can replace this boundary without changing menu consumers.
public final class MenuCatalogRepository {
    private static let stateKey = "ganfan-handbook.catalog-user-state.v1"
    private static let cupSizeDefaultsMigrationKey = "ganfan-handbook.catalog-cup-size-defaults-migrated.v1"
    public static let changeGenerationKey = "ganfan-handbook.catalog-change-generation.v1"
    private let userDefaults: UserDefaults

    public init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
    }

    public func loadUserState() throws -> MenuCatalogUserState {
        guard let data = userDefaults.data(forKey: Self.stateKey) else {
            let initialState = MenuCatalogUserState()
            try saveUserState(initialState)
            userDefaults.set(true, forKey: Self.cupSizeDefaultsMigrationKey)
            return initialState
        }

        let savedState: MenuCatalogUserState
        do {
            savedState = try JSONDecoder().decode(MenuCatalogUserState.self, from: data)
        } catch {
            throw MenuCatalogRepositoryError.invalidSavedState
        }

        guard !userDefaults.bool(forKey: Self.cupSizeDefaultsMigrationKey) else {
            return savedState
        }

        let migratedState = Self.initializingDefaultCupSizes(in: savedState)
        try saveUserState(migratedState)
        userDefaults.set(true, forKey: Self.cupSizeDefaultsMigrationKey)
        return migratedState
    }

    public func saveUserState(_ state: MenuCatalogUserState) throws {
        try Self.validate(state)
        userDefaults.set(try JSONEncoder().encode(state), forKey: Self.stateKey)
        let nextGeneration = userDefaults.integer(forKey: Self.changeGenerationKey) &+ 1
        userDefaults.set(nextGeneration, forKey: Self.changeGenerationKey)
    }

    public var savedStateByteCount: Int? {
        userDefaults.data(forKey: Self.stateKey)?.count
    }

    public func catalog(from bundled: MenuCatalog) throws -> MenuCatalog {
        let nutritionRepository = NutritionUpdateRepository(store: userDefaults)
        let baseCatalog = try nutritionRepository.baseCatalog(from: bundled)
        let oldState = try loadUserState()
        let state = oldState.reconciled(to: baseCatalog)
        if state != oldState { try saveUserState(state) }
        return baseCatalog.merging(localBrands: state.brands, localDrinks: state.drinks,
                                   deletedDrinkIDs: state.deletedDrinkIDs)
    }

    public static func validate(_ state: MenuCatalogUserState) throws {
        var brandIDs = Set<String>()
        for brand in state.brands {
            guard !brand.id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw MenuCatalogRepositoryError.emptyBrandIdentifier
            }
            guard brandIDs.insert(brand.id).inserted else {
                throw MenuCatalogRepositoryError.duplicateIdentifier(brand.id)
            }
        }

        var drinkIDs = Set<String>()
        for drink in state.drinks {
            guard !drink.id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw MenuCatalogRepositoryError.emptyDrinkIdentifier
            }
            guard !drink.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw MenuCatalogRepositoryError.emptyDrinkName
            }
            guard drinkIDs.insert(drink.id).inserted else {
                throw MenuCatalogRepositoryError.duplicateIdentifier(drink.id)
            }
        }

        for size in state.globalCupSizes {
            let type = size.cupType.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !type.isEmpty, size.sizeML == nil || size.sizeML! > 0 else {
                throw MenuCatalogRepositoryError.invalidCupSize(type)
            }
        }

    }

    private static func initializingDefaultCupSizes(in state: MenuCatalogUserState) -> MenuCatalogUserState {
        let cupSizes = state.globalCupSizes.map { configuredSize in
            guard configuredSize.sizeML == nil,
                  let defaultSize = MenuCatalogUserState.defaultCupSizes.first(where: { $0.cupType == configuredSize.cupType }) else {
                return configuredSize
            }
            return defaultSize
        }

        return MenuCatalogUserState(
            brands: state.brands,
            drinks: state.drinks,
            deletedDrinkIDs: state.deletedDrinkIDs,
            globalCupSizes: cupSizes
        )
    }
}
