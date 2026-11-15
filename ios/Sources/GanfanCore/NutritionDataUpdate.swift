import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public enum NutritionUpdateError: Error, LocalizedError, Equatable {
    case invalidURL
    case invalidResponse
    case fileTooLarge
    case invalidSchema
    case invalidVersion
    case duplicateID
    case incompleteNewDrink(String)
    case invalidNutrient(String)
    case olderVersion

    public var errorDescription: String? {
        switch self {
        case .invalidURL: "请使用有效的 HTTPS 营养数据地址。"
        case .invalidResponse: "远程营养文件下载失败。"
        case .fileTooLarge: "营养数据文件超过 5 MB 限制。"
        case .invalidSchema: "数据格式版本不受支持。"
        case .invalidVersion: "营养数据版本号应为数字和点号。"
        case .duplicateID: "营养数据包存在重复的饮品 ID。"
        case .incompleteNewDrink(let id): "新增饮品 \(id) 缺少品牌或名称。"
        case .invalidNutrient(let id): "饮品 \(id) 含有无效的营养数值。"
        case .olderVersion: "远程数据版本不比本地新。"
        }
    }
}

public struct NutritionUpdateEntry: Codable, Equatable, Sendable {
    public let id: String
    public let brandID: String?
    public let brandName: String?
    public let name: String?
    public let category: String?
    public let nutritionPerUnit: MenuNutritionPerUnit?
    public let nutritionVariants: [MenuNutritionVariant]?

    public init(
        id: String, brandID: String? = nil, brandName: String? = nil,
        name: String? = nil, category: String? = nil,
        nutritionPerUnit: MenuNutritionPerUnit? = nil,
        nutritionVariants: [MenuNutritionVariant]? = nil
    ) {
        self.id = id
        self.brandID = brandID
        self.brandName = brandName
        self.name = name
        self.category = category
        self.nutritionPerUnit = nutritionPerUnit
        self.nutritionVariants = nutritionVariants
    }
}

public struct NutritionDataPack: Codable, Equatable, Sendable {
    public let schemaVersion: Int
    public let version: String
    public let generatedAt: String
    public let brands: [MenuBrand]
    public let entries: [NutritionUpdateEntry]

    public init(schemaVersion: Int = 1, version: String, generatedAt: String,
                brands: [MenuBrand] = [], entries: [NutritionUpdateEntry]) {
        self.schemaVersion = schemaVersion
        self.version = version
        self.generatedAt = generatedAt
        self.brands = brands
        self.entries = entries
    }

    private enum CodingKeys: String, CodingKey {
        case schemaVersion, version, generatedAt, brands, entries
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try c.decode(Int.self, forKey: .schemaVersion)
        version = try c.decode(String.self, forKey: .version)
        generatedAt = try c.decode(String.self, forKey: .generatedAt)
        brands = try c.decodeIfPresent([MenuBrand].self, forKey: .brands) ?? []
        entries = try c.decode([NutritionUpdateEntry].self, forKey: .entries)
    }

    public func validate() throws {
        guard schemaVersion == 1 else { throw NutritionUpdateError.invalidSchema }
        guard Self.versionParts(version) != nil else { throw NutritionUpdateError.invalidVersion }
        var ids = Set<String>()
        for entry in entries {
            guard !entry.id.isEmpty, ids.insert(entry.id).inserted else { throw NutritionUpdateError.duplicateID }
            let fields = [entry.nutritionPerUnit?.energyKcal, entry.nutritionPerUnit?.sugarG,
                          entry.nutritionPerUnit?.caffeineMg, entry.nutritionPerUnit?.proteinG,
                          entry.nutritionPerUnit?.fatG, entry.nutritionPerUnit?.carbohydrateG]
                + (entry.nutritionVariants ?? []).flatMap {
                    [$0.energyKcal, $0.sugarG, $0.caffeineMg, $0.proteinG, $0.fatG, $0.carbohydrateG]
                }
            guard fields.compactMap({ $0 }).allSatisfy({ $0.isFinite && $0 >= 0 }) else {
                throw NutritionUpdateError.invalidNutrient(entry.id)
            }
            if let unit = entry.nutritionPerUnit {
                guard unit.amount.isFinite, unit.amount > 0, ["ml", "杯"].contains(unit.unit) else {
                    throw NutritionUpdateError.invalidNutrient(entry.id)
                }
            }
            for variant in entry.nutritionVariants ?? [] {
                if let size = variant.sizeML, !(0...3000).contains(size) {
                    throw NutritionUpdateError.invalidNutrient(entry.id)
                }
            }
        }
        var brandIDs = Set<String>()
        for brand in brands {
            guard !brand.id.isEmpty, brandIDs.insert(brand.id).inserted else {
                throw NutritionUpdateError.duplicateID
            }
        }
    }

    public static func isNewer(_ candidate: String, than previous: String) -> Bool {
        guard let a = versionParts(candidate), let b = versionParts(previous) else { return false }
        for index in 0..<max(a.count, b.count) {
            let x = index < a.count ? a[index] : 0
            let y = index < b.count ? b[index] : 0
            if x != y { return x > y }
        }
        return false
    }

    private static func versionParts(_ value: String) -> [Int]? {
        let parts = value.split(separator: ".", omittingEmptySubsequences: false)
        guard !parts.isEmpty, parts.count <= 8 else { return nil }
        let values = parts.compactMap { Int($0) }
        return values.count == parts.count && values.allSatisfy { $0 >= 0 } ? values : nil
    }

    public func merging(into bundled: MenuCatalog) throws -> MenuCatalog {
        try validate()
        var drinks = bundled.drinks
        var lookup: [String: Int] = [:]
        for (index, drink) in drinks.enumerated() { lookup[drink.id] = index }
        for entry in entries {
            if let index = lookup[entry.id] {
                drinks[index] = Self.update(drinks[index], with: entry)
            } else {
                guard let brandID = entry.brandID, !brandID.isEmpty,
                      let brandName = entry.brandName, !brandName.isEmpty,
                      let name = entry.name, !name.isEmpty else {
                    throw NutritionUpdateError.incompleteNewDrink(entry.id)
                }
                lookup[entry.id] = drinks.count
                drinks.append(MenuDrink(id: entry.id, brandID: brandID, brandName: brandName,
                                       name: name, category: entry.category ?? "",
                                       source: "远程营养数据包", sourceType: "nutrition_update",
                                       status: "pending",
                                       nutritionPerUnit: entry.nutritionPerUnit,
                                       nutritionVariants: entry.nutritionVariants ?? []))
            }
        }
        var brands = bundled.brands
        let existing = Set(brands.map(\.id))
        brands.append(contentsOf: self.brands.filter { !existing.contains($0.id) })
        return MenuCatalog(version: version, updatedAt: generatedAt, brands: brands, drinks: drinks)
    }

    private static func update(_ old: MenuDrink, with entry: NutritionUpdateEntry) -> MenuDrink {
        let variants: [MenuNutritionVariant]
        if let incoming = entry.nutritionVariants {
            var merged = old.nutritionVariants
            for value in incoming {
                if let index = merged.firstIndex(where: { variantKey($0) == variantKey(value) }) {
                    merged[index] = value
                } else { merged.append(value) }
            }
            variants = merged
        } else { variants = old.nutritionVariants }
        return MenuDrink(
            id: old.id, brandID: old.brandID, brandName: old.brandName, name: old.name,
            aliases: old.aliases, category: old.category, source: old.source,
            sourceType: old.sourceType, sourceName: old.sourceName, sourceURL: old.sourceURL,
            updatedAt: old.updatedAt, status: old.status, active: old.active,
            cupTypes: old.cupTypes, cupSizes: old.cupSizes, sizesML: old.sizesML,
            sweetnessOptions: old.sweetnessOptions, servingOptions: old.servingOptions,
            nutritionPerUnit: entry.nutritionPerUnit ?? old.nutritionPerUnit,
            nutritionVariants: variants, menuEntries: old.menuEntries,
            localOverride: old.localOverride, custom: old.custom
        )
    }

    private static func variantKey(_ value: MenuNutritionVariant) -> String {
        let parts = [value.cupType ?? "", value.sizeML.map(String.init) ?? "",
                     value.sweetness ?? "", value.servingOption ?? "",
                     value.temperature ?? "", value.ice ?? ""]
        return (parts + (value.toppings ?? []).sorted()).joined(separator: "|")
    }
}

public final class NutritionUpdateRepository {
    private let store: UserDefaults
    private static let dataKey = "ganfan-handbook.nutrition-data-pack.v1"

    public init(store: UserDefaults = .standard) { self.store = store }

    public func load() -> NutritionDataPack? {
        guard let data = store.data(forKey: Self.dataKey),
              let pack = try? JSONDecoder().decode(NutritionDataPack.self, from: data),
              (try? pack.validate()) != nil else { return nil }
        return pack
    }

    /// Restores a previously backed-up nutrition pack without applying the version-update gate.
    public func restore(_ pack: NutritionDataPack?) throws {
        guard let pack else {
            store.removeObject(forKey: Self.dataKey)
            return
        }
        try pack.validate()
        store.set(try JSONEncoder().encode(pack), forKey: Self.dataKey)
    }

    /// Validates before persisting; the previous valid pack survives failed updates.
    @discardableResult
    public func install(_ data: Data, bundled: MenuCatalog) throws -> NutritionDataPack {
        guard data.count <= 5_000_000 else { throw NutritionUpdateError.fileTooLarge }
        let pack = try JSONDecoder().decode(NutritionDataPack.self, from: data)
        try pack.validate()
        _ = try pack.merging(into: bundled)
        if let current = load(), !NutritionDataPack.isNewer(pack.version, than: current.version) {
            throw NutritionUpdateError.olderVersion
        }
        store.set(data, forKey: Self.dataKey)
        return pack
    }

    public func catalog(from bundled: MenuCatalog, userState: MenuCatalogUserState) throws -> MenuCatalog {
        let resolved = try load()?.merging(into: bundled) ?? bundled
        return resolved.merging(localBrands: userState.brands, localDrinks: userState.drinks,
                                deletedDrinkIDs: userState.deletedDrinkIDs)
    }
}

public struct NutritionUpdateClient {
    public init() {}

    public func fetch(from url: URL) async throws -> Data {
        guard url.scheme == "https", url.host != nil, url.user == nil, url.password == nil else {
            throw NutritionUpdateError.invalidURL
        }
        var request = URLRequest(url: url)
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.timeoutInterval = 25
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200,
              http.url?.scheme == "https" else { throw NutritionUpdateError.invalidResponse }
        guard data.count <= 5_000_000 else { throw NutritionUpdateError.fileTooLarge }
        return data
    }
}
