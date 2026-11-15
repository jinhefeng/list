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
}

/// Owns the local catalog overlay. A future shared-list repository can replace this boundary without changing menu consumers.
public final class MenuCatalogRepository {
    private static let stateKey = "ganfan-handbook.catalog-user-state.v1"
    private static let cupSizeDefaultsMigrationKey = "ganfan-handbook.catalog-cup-size-defaults-migrated.v1"
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
    }

    public var savedStateByteCount: Int? {
        userDefaults.data(forKey: Self.stateKey)?.count
    }

    public func catalog(from bundled: MenuCatalog) throws -> MenuCatalog {
        let state = try loadUserState()
        return try NutritionUpdateRepository(store: userDefaults).catalog(from: bundled, userState: state)
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
