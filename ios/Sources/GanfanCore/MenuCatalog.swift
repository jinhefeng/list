import Foundation

public struct MenuBrand: Codable, Equatable, Identifiable, Sendable {
    public let id: String
    public let name: String
    public let aliases: [String]
    public let category: String
    public let source: String
    public let sourceName: String
    public let sourceURL: String
    public let updatedAt: String
    public let status: String
    public let active: Bool
    public let localOverride: Bool

    public init(
        id: String,
        name: String,
        aliases: [String] = [],
        category: String = "",
        source: String = "",
        sourceName: String = "",
        sourceURL: String = "",
        updatedAt: String = "",
        status: String = "pending",
        active: Bool = true,
        localOverride: Bool = false
    ) {
        self.id = id
        self.name = name
        self.aliases = aliases
        self.category = category
        self.source = source
        self.sourceName = sourceName
        self.sourceURL = sourceURL
        self.updatedAt = updatedAt
        self.status = status
        self.active = active
        self.localOverride = localOverride
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, aliases, category, source, sourceName, updatedAt, status, active, localOverride
        case sourceURL = "sourceUrl"
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        aliases = try container.decodeIfPresent([String].self, forKey: .aliases) ?? []
        category = try container.decodeIfPresent(String.self, forKey: .category) ?? ""
        source = try container.decodeIfPresent(String.self, forKey: .source) ?? ""
        sourceName = try container.decodeIfPresent(String.self, forKey: .sourceName) ?? ""
        sourceURL = try container.decodeIfPresent(String.self, forKey: .sourceURL) ?? ""
        updatedAt = try container.decodeIfPresent(String.self, forKey: .updatedAt) ?? ""
        status = try container.decodeIfPresent(String.self, forKey: .status) ?? "pending"
        active = try container.decodeIfPresent(Bool.self, forKey: .active) ?? true
        localOverride = try container.decodeIfPresent(Bool.self, forKey: .localOverride) ?? false
    }
}

public struct MenuCupSize: Codable, Equatable, Sendable {
    public let cupType: String
    public let sizeML: Int?

    public init(cupType: String, sizeML: Int? = nil) {
        self.cupType = cupType
        self.sizeML = sizeML
    }

    private enum CodingKeys: String, CodingKey {
        case cupType
        case sizeML = "sizeMl"
    }
}

public struct MenuNutritionPerUnit: Codable, Equatable, Sendable {
    public let amount: Double
    public let unit: String
    public let energyKcal: Double?
    public let sugarG: Double?
    public let caffeineMg: Double?
    public let sourceType: String?
    public let source: String?
    public let updatedAt: String?

    public init(
        amount: Double,
        unit: String,
        energyKcal: Double? = nil,
        sugarG: Double? = nil,
        caffeineMg: Double? = nil,
        sourceType: String? = "estimated",
        source: String? = nil,
        updatedAt: String? = nil
    ) {
        self.amount = amount
        self.unit = unit
        self.energyKcal = energyKcal
        self.sugarG = sugarG
        self.caffeineMg = caffeineMg
        self.sourceType = sourceType
        self.source = source
        self.updatedAt = updatedAt
    }
}

public struct MenuNutritionVariant: Codable, Equatable, Sendable {
    public let cupType: String?
    public let sizeML: Int?
    public let sweetness: String?
    public let servingOption: String?
    public let temperature: String?
    public let ice: String?
    public let toppings: [String]?
    public let energyKcal: Double?
    public let sugarG: Double?
    public let caffeineMg: Double?
    public let sourceType: String?
    public let source: String?
    public let sourceURL: String?
    public let updatedAt: String?

    private enum CodingKeys: String, CodingKey {
        case cupType, sweetness, servingOption, temperature, ice, toppings
        case sizeML = "sizeMl"
        case energyKcal, sugarG, caffeineMg, sourceType, source, updatedAt
        case sourceURL = "sourceUrl"
    }

    public init(
        cupType: String? = nil,
        sizeML: Int? = nil,
        sweetness: String? = nil,
        servingOption: String? = nil,
        temperature: String? = nil,
        ice: String? = nil,
        toppings: [String]? = nil,
        energyKcal: Double? = nil,
        sugarG: Double? = nil,
        caffeineMg: Double? = nil,
        sourceType: String? = nil,
        source: String? = nil,
        sourceURL: String? = nil,
        updatedAt: String? = nil
    ) {
        self.cupType = cupType
        self.sizeML = sizeML
        self.sweetness = sweetness
        self.servingOption = servingOption
        self.temperature = temperature
        self.ice = ice
        self.toppings = toppings
        self.energyKcal = energyKcal
        self.sugarG = sugarG
        self.caffeineMg = caffeineMg
        self.sourceType = sourceType
        self.source = source
        self.sourceURL = sourceURL
        self.updatedAt = updatedAt
    }
}

public struct MenuEntry: Codable, Equatable, Sendable {
    public let scope: String
    public let city: String?
    public let storeID: String?
    public let storeName: String?
    public let status: String
    public let sourceType: String
    public let sourceName: String
    public let sourceURL: String
    public let checkedAt: String
    public let cupTypes: [String]
    public let cupSizes: [MenuCupSize]
    public let sizesML: [Int]
    public let sweetnessOptions: [String]
    public let servingOptions: [String]

    private enum CodingKeys: String, CodingKey {
        case scope, city, storeName, status, sourceType, sourceName, checkedAt
        case storeID = "storeId"
        case sourceURL = "sourceUrl"
        case cupTypes, cupSizes, sweetnessOptions, servingOptions
        case sizesML = "sizesMl"
    }

    public init(
        scope: String,
        city: String? = nil,
        storeID: String? = nil,
        storeName: String? = nil,
        status: String = "pending",
        sourceType: String = "pending",
        sourceName: String = "",
        sourceURL: String = "",
        checkedAt: String = "",
        cupTypes: [String] = [],
        cupSizes: [MenuCupSize] = [],
        sizesML: [Int] = [],
        sweetnessOptions: [String] = [],
        servingOptions: [String] = []
    ) {
        self.scope = scope
        self.city = city
        self.storeID = storeID
        self.storeName = storeName
        self.status = status
        self.sourceType = sourceType
        self.sourceName = sourceName
        self.sourceURL = sourceURL
        self.checkedAt = checkedAt
        self.cupTypes = cupTypes
        self.cupSizes = cupSizes
        self.sizesML = sizesML
        self.sweetnessOptions = sweetnessOptions
        self.servingOptions = servingOptions
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        scope = try container.decode(String.self, forKey: .scope)
        city = try container.decodeIfPresent(String.self, forKey: .city)
        storeID = try container.decodeIfPresent(String.self, forKey: .storeID)
        storeName = try container.decodeIfPresent(String.self, forKey: .storeName)
        status = try container.decodeIfPresent(String.self, forKey: .status) ?? "pending"
        sourceType = try container.decodeIfPresent(String.self, forKey: .sourceType) ?? "pending"
        sourceName = try container.decodeIfPresent(String.self, forKey: .sourceName) ?? ""
        sourceURL = try container.decodeIfPresent(String.self, forKey: .sourceURL) ?? ""
        checkedAt = try container.decodeIfPresent(String.self, forKey: .checkedAt) ?? ""
        cupTypes = try container.decodeIfPresent([String].self, forKey: .cupTypes) ?? []
        cupSizes = try container.decodeIfPresent([MenuCupSize].self, forKey: .cupSizes) ?? []
        sizesML = try container.decodeIfPresent([Int].self, forKey: .sizesML) ?? []
        sweetnessOptions = try container.decodeIfPresent([String].self, forKey: .sweetnessOptions) ?? []
        servingOptions = try container.decodeIfPresent([String].self, forKey: .servingOptions) ?? []
    }
}

public struct MenuDrink: Codable, Equatable, Identifiable, Sendable {
    public let id: String
    public let brandID: String
    public let brandName: String
    public let name: String
    public let aliases: [String]
    public let category: String
    public let source: String
    public let sourceType: String
    public let sourceName: String
    public let sourceURL: String
    public let updatedAt: String
    public let status: String
    public let active: Bool
    public let cupTypes: [String]
    public let cupSizes: [MenuCupSize]
    public let sizesML: [Int]
    public let sweetnessOptions: [String]
    public let servingOptions: [String]
    public let nutritionPerUnit: MenuNutritionPerUnit?
    public let nutritionVariants: [MenuNutritionVariant]
    public let menuEntries: [MenuEntry]
    public let localOverride: Bool
    public let custom: Bool

    public init(
        id: String,
        brandID: String,
        brandName: String,
        name: String,
        aliases: [String] = [],
        category: String = "",
        source: String = "",
        sourceType: String = "",
        sourceName: String = "",
        sourceURL: String = "",
        updatedAt: String = "",
        status: String = "pending",
        active: Bool = true,
        cupTypes: [String] = [],
        cupSizes: [MenuCupSize] = [],
        sizesML: [Int] = [],
        sweetnessOptions: [String] = [],
        servingOptions: [String] = [],
        nutritionPerUnit: MenuNutritionPerUnit? = nil,
        nutritionVariants: [MenuNutritionVariant] = [],
        menuEntries: [MenuEntry] = [],
        localOverride: Bool = false,
        custom: Bool = false
    ) {
        self.id = id
        self.brandID = brandID
        self.brandName = brandName
        self.name = name
        self.aliases = aliases
        self.category = category
        self.source = source
        self.sourceType = sourceType
        self.sourceName = sourceName
        self.sourceURL = sourceURL
        self.updatedAt = updatedAt
        self.status = status
        self.active = active
        self.cupTypes = cupTypes
        self.cupSizes = cupSizes
        self.sizesML = sizesML
        self.sweetnessOptions = sweetnessOptions
        self.servingOptions = servingOptions
        self.nutritionPerUnit = nutritionPerUnit
        self.nutritionVariants = nutritionVariants
        self.menuEntries = menuEntries
        self.localOverride = localOverride
        self.custom = custom
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, aliases, category, source, sourceType, sourceName, updatedAt, status, active
        case sourceURL = "sourceUrl"
        case brandID = "brandId"
        case brandName, cupTypes, cupSizes, sweetnessOptions, servingOptions
        case sizesML = "sizesMl"
        case nutritionPerUnit, nutritionVariants, menuEntries, localOverride, custom
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        brandID = try container.decode(String.self, forKey: .brandID)
        brandName = try container.decodeIfPresent(String.self, forKey: .brandName) ?? ""
        name = try container.decode(String.self, forKey: .name)
        aliases = try container.decodeIfPresent([String].self, forKey: .aliases) ?? []
        category = try container.decodeIfPresent(String.self, forKey: .category) ?? ""
        source = try container.decodeIfPresent(String.self, forKey: .source) ?? ""
        sourceType = try container.decodeIfPresent(String.self, forKey: .sourceType) ?? ""
        sourceName = try container.decodeIfPresent(String.self, forKey: .sourceName) ?? ""
        sourceURL = try container.decodeIfPresent(String.self, forKey: .sourceURL) ?? ""
        updatedAt = try container.decodeIfPresent(String.self, forKey: .updatedAt) ?? ""
        status = try container.decodeIfPresent(String.self, forKey: .status) ?? "pending"
        active = try container.decodeIfPresent(Bool.self, forKey: .active) ?? true
        cupTypes = try container.decodeIfPresent([String].self, forKey: .cupTypes) ?? []
        cupSizes = try container.decodeIfPresent([MenuCupSize].self, forKey: .cupSizes) ?? []
        sizesML = try container.decodeIfPresent([Int].self, forKey: .sizesML) ?? []
        sweetnessOptions = try container.decodeIfPresent([String].self, forKey: .sweetnessOptions) ?? []
        servingOptions = try container.decodeIfPresent([String].self, forKey: .servingOptions) ?? []
        nutritionPerUnit = try container.decodeIfPresent(MenuNutritionPerUnit.self, forKey: .nutritionPerUnit)
        nutritionVariants = try container.decodeIfPresent([MenuNutritionVariant].self, forKey: .nutritionVariants) ?? []
        menuEntries = try container.decodeIfPresent([MenuEntry].self, forKey: .menuEntries) ?? []
        localOverride = try container.decodeIfPresent(Bool.self, forKey: .localOverride) ?? false
        custom = try container.decodeIfPresent(Bool.self, forKey: .custom) ?? false
    }
}

public struct MenuCatalog: Codable, Equatable, Sendable {
    public let version: String
    public let updatedAt: String
    public let brands: [MenuBrand]
    public let drinks: [MenuDrink]

    public init(version: String, updatedAt: String, brands: [MenuBrand], drinks: [MenuDrink]) {
        self.version = version
        self.updatedAt = updatedAt
        self.brands = brands
        self.drinks = drinks
    }

    private enum CodingKeys: String, CodingKey {
        case version, updatedAt, brands, drinks
    }

    private enum LegacyCodingKeys: String, CodingKey {
        case generatedAt
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        version = try container.decode(String.self, forKey: .version)
        if let bundledDate = try container.decodeIfPresent(String.self, forKey: .updatedAt) {
            updatedAt = bundledDate
        } else {
            let legacy = try decoder.container(keyedBy: LegacyCodingKeys.self)
            updatedAt = try legacy.decodeIfPresent(String.self, forKey: .generatedAt) ?? ""
        }
        brands = try container.decodeIfPresent([MenuBrand].self, forKey: .brands) ?? []
        drinks = try container.decodeIfPresent([MenuDrink].self, forKey: .drinks) ?? []
    }

    public static func decode(_ data: Data) throws -> MenuCatalog {
        try JSONDecoder().decode(MenuCatalog.self, from: data)
    }

    public func merging(
        localBrands: [MenuBrand],
        localDrinks: [MenuDrink],
        deletedDrinkIDs: Set<String>
    ) -> MenuCatalog {
        let brandOverrides = Dictionary(
            localBrands.filter(\.localOverride).map { ($0.id, $0) },
            uniquingKeysWith: { _, latest in latest }
        )
        var mergedBrands = brands.map { brandOverrides[$0.id] ?? $0 }
        let existingBrandIDs = Set(mergedBrands.map(\.id))
        mergedBrands.append(contentsOf: localBrands.filter { $0.localOverride && !existingBrandIDs.contains($0.id) })

        let drinkOverrides = Dictionary(
            localDrinks.filter { $0.localOverride || $0.custom }.map { ($0.id, $0) },
            uniquingKeysWith: { _, latest in latest }
        )
        var mergedDrinks = drinks
            .filter { !deletedDrinkIDs.contains($0.id) }
            .map { drinkOverrides[$0.id] ?? $0 }
        let bundledIDs = Set(drinks.map(\.id))
        let existingDrinkIDs = Set(mergedDrinks.map(\.id))
        mergedDrinks.append(contentsOf: localDrinks.filter {
            ($0.localOverride || $0.custom)
                && !deletedDrinkIDs.contains($0.id)
                && !bundledIDs.contains($0.id)
                && !existingDrinkIDs.contains($0.id)
        })

        return MenuCatalog(version: version, updatedAt: updatedAt, brands: mergedBrands, drinks: mergedDrinks)
    }

    public func searchBrands(_ query: String) -> [MenuBrand] {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines)
        return brands.filter { brand in
            brand.active && Self.matches(needle, values: [brand.name] + brand.aliases)
        }
    }

    public func searchDrinks(brandID: String? = nil, query: String) -> [MenuDrink] {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let matchingBrandIDs = Set(
            brands
                .filter { $0.active && Self.matches(needle, values: [$0.name] + $0.aliases) }
                .map(\.id)
        )
        return drinks.filter { drink in
            drink.active
                && (brandID == nil || drink.brandID == brandID)
                && (Self.matches(needle, values: [drink.name, drink.brandName] + drink.aliases)
                    || matchingBrandIDs.contains(drink.brandID))
        }
    }

    private static func matches(_ query: String, values: [String]) -> Bool {
        query.isEmpty || values.contains { $0.localizedCaseInsensitiveContains(query) }
    }
}
