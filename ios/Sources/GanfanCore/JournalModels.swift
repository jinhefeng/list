import Foundation

public enum JournalModelError: Error, Equatable {
    case emptyDrinkName
    case emptyDishName
    case mealNeedsDish
    case invalidConsumptionTime
    case invalidSize
    case invalidCoordinate
    case invalidPhotoAsset
}

public struct PhotoAsset: Codable, Equatable, Hashable, Identifiable, Sendable {
    public let id: UUID
    public let fileName: String
    public let fileExtension: String
    public let byteCount: Int
    public let sha256: String

    public init(id: UUID, fileName: String, fileExtension: String, byteCount: Int, sha256: String) throws {
        guard Self.isSafeFileName(fileName, id: id, fileExtension: fileExtension),
              byteCount > 0,
              sha256.count == 64,
              sha256.allSatisfy({ $0.isHexDigit }) else {
            throw JournalModelError.invalidPhotoAsset
        }

        self.id = id
        self.fileName = fileName
        self.fileExtension = fileExtension.lowercased()
        self.byteCount = byteCount
        self.sha256 = sha256.lowercased()
    }

    static func isSafeFileName(_ fileName: String, id: UUID, fileExtension: String) -> Bool {
        let safeExtension = fileExtension.range(of: #"^[A-Za-z0-9]{1,10}$"#, options: .regularExpression) != nil
        return safeExtension && fileName == "\(id.uuidString).\(fileExtension.lowercased())"
    }

    public func validate() throws {
        _ = try PhotoAsset(
            id: id,
            fileName: fileName,
            fileExtension: fileExtension,
            byteCount: byteCount,
            sha256: sha256
        )
    }
}

public struct NutritionSnapshot: Codable, Equatable, Sendable {
    public enum Confidence: String, Codable, Sendable {
        case official
        case estimated
        case rough
        case unavailable

        public var displayName: String {
            switch self {
            case .official: "官方数据"
            case .estimated: "估算值"
            case .rough: "粗略估计"
            case .unavailable: "暂无数据"
            }
        }
    }

    public let energyKcal: Double?
    public let sugarGrams: Double?
    public let caffeineMilligrams: Double?
    public let confidence: Confidence
    public let source: String
    public let sourceURL: String?
    public let proteinGrams: Double?
    public let fatGrams: Double?
    public let carbohydrateGrams: Double?
    public let assumptions: String
    public let metricSources: [String: String]

    public init(
        energyKcal: Double?,
        sugarGrams: Double?,
        caffeineMilligrams: Double?,
        confidence: Confidence,
        source: String = "",
        sourceURL: String? = nil,
        proteinGrams: Double? = nil,
        fatGrams: Double? = nil,
        carbohydrateGrams: Double? = nil,
        assumptions: String = "",
        metricSources: [String: String] = [:]
    ) {
        self.energyKcal = energyKcal
        self.sugarGrams = sugarGrams
        self.caffeineMilligrams = caffeineMilligrams
        self.confidence = confidence
        self.source = source
        self.sourceURL = sourceURL
        self.proteinGrams = proteinGrams
        self.fatGrams = fatGrams
        self.carbohydrateGrams = carbohydrateGrams
        self.assumptions = assumptions
        self.metricSources = metricSources
    }

    private enum CodingKeys: String, CodingKey {
        case energyKcal, sugarGrams, caffeineMilligrams, confidence, source, sourceURL
        case proteinGrams, fatGrams, carbohydrateGrams, assumptions, metricSources
    }

    /// Older saved records have no macro fields or assumptions.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        energyKcal = try c.decodeIfPresent(Double.self, forKey: .energyKcal)
        sugarGrams = try c.decodeIfPresent(Double.self, forKey: .sugarGrams)
        caffeineMilligrams = try c.decodeIfPresent(Double.self, forKey: .caffeineMilligrams)
        confidence = try c.decode(Confidence.self, forKey: .confidence)
        source = try c.decodeIfPresent(String.self, forKey: .source) ?? ""
        sourceURL = try c.decodeIfPresent(String.self, forKey: .sourceURL)
        proteinGrams = try c.decodeIfPresent(Double.self, forKey: .proteinGrams)
        fatGrams = try c.decodeIfPresent(Double.self, forKey: .fatGrams)
        carbohydrateGrams = try c.decodeIfPresent(Double.self, forKey: .carbohydrateGrams)
        assumptions = try c.decodeIfPresent(String.self, forKey: .assumptions) ?? ""
        metricSources = try c.decodeIfPresent([String: String].self, forKey: .metricSources) ?? [:]
    }
}

public struct DrinkRecord: Codable, Equatable, Identifiable, Sendable {
    public let id: UUID
    public let consumedAt: Date
    public let brandID: String
    public let brandName: String
    public let drinkID: String
    public let drinkName: String
    public let cupType: String
    public let sizeML: Int?
    public let sweetness: String
    public let servingOption: String
    public let temperature: String?
    public let ice: String?
    public let locationName: String
    public let locationAddress: String
    public let latitude: Double?
    public let longitude: Double?
    public let notes: String
    public let photo: PhotoAsset?
    public let nutrition: NutritionSnapshot?

    public init(
        id: UUID = UUID(),
        consumedAt: Date = .now,
        brandID: String = "",
        brandName: String = "",
        drinkID: String = "",
        drinkName: String,
        cupType: String = "",
        sizeML: Int? = nil,
        sweetness: String = "",
        servingOption: String = "",
        temperature: String? = nil,
        ice: String? = nil,
        locationName: String = "",
        locationAddress: String = "",
        latitude: Double? = nil,
        longitude: Double? = nil,
        notes: String = "",
        photo: PhotoAsset? = nil,
        nutrition: NutritionSnapshot? = nil
    ) throws {
        guard !drinkName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw JournalModelError.emptyDrinkName
        }
        guard consumedAt.timeIntervalSince1970.isFinite else {
            throw JournalModelError.invalidConsumptionTime
        }
        if let sizeML, sizeML < 0 {
            throw JournalModelError.invalidSize
        }
        guard Self.validCoordinates(latitude: latitude, longitude: longitude) else {
            throw JournalModelError.invalidCoordinate
        }

        self.id = id
        self.consumedAt = consumedAt
        self.brandID = brandID.trimmingCharacters(in: .whitespacesAndNewlines)
        self.brandName = brandName.trimmingCharacters(in: .whitespacesAndNewlines)
        self.drinkID = drinkID.trimmingCharacters(in: .whitespacesAndNewlines)
        self.drinkName = drinkName.trimmingCharacters(in: .whitespacesAndNewlines)
        self.cupType = cupType.trimmingCharacters(in: .whitespacesAndNewlines)
        self.sizeML = sizeML
        self.sweetness = Self.canonicalSweetness(sweetness)
        self.servingOption = servingOption.trimmingCharacters(in: .whitespacesAndNewlines)
        self.temperature = Self.normalizedOptional(temperature)
        self.ice = Self.normalizedOptional(ice)
        self.locationName = locationName.trimmingCharacters(in: .whitespacesAndNewlines)
        self.locationAddress = locationAddress.trimmingCharacters(in: .whitespacesAndNewlines)
        self.latitude = latitude
        self.longitude = longitude
        self.notes = notes.trimmingCharacters(in: .whitespacesAndNewlines)
        self.photo = photo
        self.nutrition = nutrition
    }

    public func replacingSweetness(_ sweetness: String) throws -> DrinkRecord {
        try DrinkRecord(
            id: id,
            consumedAt: consumedAt,
            brandID: brandID,
            brandName: brandName,
            drinkID: drinkID,
            drinkName: drinkName,
            cupType: cupType,
            sizeML: sizeML,
            sweetness: sweetness,
            servingOption: servingOption,
            temperature: temperature,
            ice: ice,
            locationName: locationName,
            locationAddress: locationAddress,
            latitude: latitude,
            longitude: longitude,
            notes: notes,
            photo: photo,
            nutrition: nutrition
        )
    }

    private static func canonicalSweetness(_ value: String) -> String {
        let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return normalized == "微糖" ? "三分糖" : normalized
    }

    private static func validCoordinates(latitude: Double?, longitude: Double?) -> Bool {
        guard let latitude, let longitude else {
            return latitude == nil && longitude == nil
        }
        return latitude.isFinite && longitude.isFinite
            && (-90...90).contains(latitude)
            && (-180...180).contains(longitude)
    }

    private static func normalizedOptional(_ value: String?) -> String? {
        guard let value else { return nil }
        let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return normalized.isEmpty ? nil : normalized
    }
}

public struct MealDish: Codable, Equatable, Identifiable, Sendable {
    public let id: UUID
    public let name: String
    public let photo: PhotoAsset?
    public let nutrition: NutritionSnapshot?

    public init(id: UUID = UUID(), name: String, photo: PhotoAsset? = nil, nutrition: NutritionSnapshot? = nil) throws {
        let normalizedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedName.isEmpty else {
            throw JournalModelError.emptyDishName
        }
        self.id = id
        self.name = normalizedName
        self.photo = photo
        self.nutrition = nutrition
    }
}

public struct MealRecord: Codable, Equatable, Identifiable, Sendable {
    public let id: UUID
    public let consumedAt: Date
    public let storeName: String
    public let locationAddress: String
    public let latitude: Double?
    public let longitude: Double?
    public let dishes: [MealDish]
    public let notes: String

    public init(
        id: UUID = UUID(),
        consumedAt: Date = .now,
        storeName: String = "",
        locationAddress: String = "",
        latitude: Double? = nil,
        longitude: Double? = nil,
        dishes: [MealDish],
        notes: String = ""
    ) throws {
        guard consumedAt.timeIntervalSince1970.isFinite else {
            throw JournalModelError.invalidConsumptionTime
        }
        guard !dishes.isEmpty else {
            throw JournalModelError.mealNeedsDish
        }
        guard Self.validCoordinates(latitude: latitude, longitude: longitude) else {
            throw JournalModelError.invalidCoordinate
        }

        self.id = id
        self.consumedAt = consumedAt
        self.storeName = storeName.trimmingCharacters(in: .whitespacesAndNewlines)
        self.locationAddress = locationAddress.trimmingCharacters(in: .whitespacesAndNewlines)
        self.latitude = latitude
        self.longitude = longitude
        self.dishes = dishes
        self.notes = notes.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func validCoordinates(latitude: Double?, longitude: Double?) -> Bool {
        guard let latitude, let longitude else {
            return latitude == nil && longitude == nil
        }
        return latitude.isFinite && longitude.isFinite
            && (-90...90).contains(latitude)
            && (-180...180).contains(longitude)
    }
}

public enum JournalRecord: Codable, Equatable, Identifiable, Sendable {
    case drink(DrinkRecord)
    case meal(MealRecord)

    public var id: UUID {
        switch self {
        case .drink(let record): record.id
        case .meal(let record): record.id
        }
    }

    public var consumedAt: Date {
        switch self {
        case .drink(let record): record.consumedAt
        case .meal(let record): record.consumedAt
        }
    }

    public static func newestFirst(_ records: [JournalRecord]) -> [JournalRecord] {
        records.sorted {
            if $0.consumedAt != $1.consumedAt {
                return $0.consumedAt > $1.consumedAt
            }
            return $0.id.uuidString < $1.id.uuidString
        }
    }

    public func validate() throws {
        switch self {
        case .drink(let record):
            try record.photo?.validate()
            _ = try DrinkRecord(
                id: record.id,
                consumedAt: record.consumedAt,
                brandID: record.brandID,
                brandName: record.brandName,
                drinkID: record.drinkID,
                drinkName: record.drinkName,
                cupType: record.cupType,
                sizeML: record.sizeML,
                sweetness: record.sweetness,
                servingOption: record.servingOption,
                temperature: record.temperature,
                ice: record.ice,
                locationName: record.locationName,
                locationAddress: record.locationAddress,
                latitude: record.latitude,
                longitude: record.longitude,
                notes: record.notes,
                photo: record.photo,
                nutrition: record.nutrition
            )
        case .meal(let record):
            for dish in record.dishes {
                try dish.photo?.validate()
            }
            let dishes = try record.dishes.map { try MealDish(id: $0.id, name: $0.name, photo: $0.photo) }
            _ = try MealRecord(
                id: record.id,
                consumedAt: record.consumedAt,
                storeName: record.storeName,
                locationAddress: record.locationAddress,
                latitude: record.latitude,
                longitude: record.longitude,
                dishes: dishes,
                notes: record.notes
            )
        }
    }
}

public enum JournalRecordCodec {
    public static func encode(_ record: JournalRecord) throws -> Data {
        try record.validate()
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(record)
    }

    public static func decode(_ data: Data) throws -> JournalRecord {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decodedRecord = try decoder.decode(JournalRecord.self, from: data)
        let record: JournalRecord
        switch decodedRecord {
        case .drink(let drink) where drink.sweetness == "微糖":
            record = .drink(try drink.replacingSweetness("三分糖"))
        default:
            record = decodedRecord
        }
        try record.validate()
        return record
    }
}
