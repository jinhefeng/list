import Foundation

public struct DrinkServingSelection: Equatable, Sendable {
    public let temperature: String
    public let ice: String

    public init(
        temperature: String? = nil,
        ice: String? = nil,
        legacyServingOption: String? = nil
    ) {
        let legacy = legacyServingOption?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !legacy.isEmpty {
            switch legacy {
            case "常温":
                self.temperature = "常温"
                self.ice = ""
            case "热", "热饮":
                self.temperature = "热饮"
                self.ice = ""
            case "冰饮":
                self.temperature = "冰饮"
                self.ice = ""
            case _ where legacy.contains("冰"):
                self.temperature = "冰饮"
                self.ice = legacy
            default:
                self.temperature = legacy
                self.ice = ""
            }
            return
        }

        let suppliedTemperature = temperature?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        var suppliedIce = ice?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if suppliedTemperature.isEmpty, ["常温", "热", "热饮"].contains(suppliedIce) {
            self.temperature = suppliedIce == "热" ? "热饮" : suppliedIce
            self.ice = ""
            return
        }
        self.temperature = suppliedTemperature == "热" ? "热饮" : (suppliedTemperature.isEmpty && !suppliedIce.isEmpty ? "冰饮" : suppliedTemperature)
        if self.temperature == "热饮" || self.temperature == "常温", suppliedIce == "去冰" {
            suppliedIce = ""
        }
        self.ice = suppliedIce
    }

    public var displayLabel: String {
        if temperature == "冰饮" {
            return ice.isEmpty ? "冰饮" : ice
        }
        return temperature
    }
}

public enum DrinkNutritionCalculator {
    public enum Nutrient: String, CaseIterable, Sendable {
        case energy = "energyKcal"
        case sugar = "sugarGrams"
        case caffeine = "caffeineMilligrams"
        case protein = "proteinGrams"
        case fat = "fatGrams"
        case carbohydrate = "carbohydrateGrams"

        public var title: String {
            switch self {
            case .energy: "能量"
            case .sugar: "糖"
            case .caffeine: "咖啡因"
            case .protein: "蛋白质"
            case .fat: "脂肪"
            case .carbohydrate: "碳水化合物"
            }
        }

        public var unit: String {
            switch self {
            case .energy: "kcal"
            case .caffeine: "mg"
            default: "g"
            }
        }

        public func value(in snapshot: NutritionSnapshot) -> Double? {
            switch self {
            case .energy: snapshot.energyKcal
            case .sugar: snapshot.sugarGrams
            case .caffeine: snapshot.caffeineMilligrams
            case .protein: snapshot.proteinGrams
            case .fat: snapshot.fatGrams
            case .carbohydrate: snapshot.carbohydrateGrams
            }
        }

        fileprivate var variantValue: (MenuNutritionVariant) -> Double? {
            switch self {
            case .energy: { $0.energyKcal }
            case .sugar: { $0.sugarG }
            case .caffeine: { $0.caffeineMg }
            case .protein: { $0.proteinG }
            case .fat: { $0.fatG }
            case .carbohydrate: { $0.carbohydrateG }
            }
        }

        fileprivate var unitValue: (MenuNutritionPerUnit) -> Double? {
            switch self {
            case .energy: { $0.energyKcal }
            case .sugar: { $0.sugarG }
            case .caffeine: { $0.caffeineMg }
            case .protein: { $0.proteinG }
            case .fat: { $0.fatG }
            case .carbohydrate: { $0.carbohydrateG }
            }
        }

        fileprivate func needsEstimate(in snapshot: NutritionSnapshot) -> Bool {
            guard let value = value(in: snapshot), value.isFinite, value >= 0 else { return true }
            let confidence = snapshot.confidence(for: rawValue)
            return confidence == .rough || confidence == .unavailable
        }
    }

    private struct ValueWithSource {
        let value: Double
        let confidence: NutritionSnapshot.Confidence
        let source: String
        let sourceURL: String
    }

    private static let headlineNutrients: [Nutrient] = [.energy, .sugar, .caffeine]

    public static func snapshot(
        for drink: MenuDrink?,
        cupType: String = "",
        sizeML: Int? = nil,
        sweetness: String = "",
        temperature: String = "",
        ice: String = ""
    ) -> NutritionSnapshot {
        guard let drink else {
            return RoughNutritionEstimator.drink(name: "", sizeML: sizeML, cupType: cupType,
                                                  sweetness: sweetness, temperature: temperature, ice: ice)
        }

        let serving = DrinkServingSelection(temperature: temperature, ice: ice)
        let eligibleVariants = drink.nutritionVariants.filter { variant in
            !(variant.toppings?.contains(where: { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) ?? false)
        }
        let exactVariant = eligibleVariants.first { variant in
            matchesSize(variant, cupType: cupType, sizeML: sizeML)
                && normalizedSweetness(variant.sweetness) == normalizedSweetness(sweetness)
                && servingSelection(for: variant) == serving
        }
        let selectedVariant = exactVariant ?? eligibleVariants.first { variant in
            matchesSize(variant, cupType: cupType, sizeML: sizeML)
                && normalized(variant.sweetness).isEmpty
                && normalized(variant.servingOption).isEmpty
                && normalized(variant.temperature).isEmpty
                && normalized(variant.ice).isEmpty
                && (variant.toppings?.isEmpty ?? true)
        }

        // A generic per-100ml label cannot be claimed to match an arbitrary sweetness.
        let multiplier = normalized(sweetness).isEmpty
            ? perUnitMultiplier(drink.nutritionPerUnit, sizeML: sizeML) : nil
        let values = Dictionary(uniqueKeysWithValues: Nutrient.allCases.map { nutrient -> (Nutrient, ValueWithSource?) in
            if let selectedVariant,
               let value = valid(nutrient.variantValue(selectedVariant)) {
                return (nutrient, ValueWithSource(
                    value: value,
                    confidence: confidence(selectedVariant.sourceType),
                    source: selectedVariant.source ?? "",
                    sourceURL: selectedVariant.sourceURL ?? ""
                ))
            }
            guard let nutrition = drink.nutritionPerUnit,
                  let multiplier,
                  let amount = valid(nutrient.unitValue(nutrition)),
                  let value = valid(amount * multiplier) else {
                return (nutrient, nil)
            }
            return (nutrient, ValueWithSource(
                value: value,
                confidence: confidence(nutrition.sourceType),
                source: nutrition.source ?? "",
                sourceURL: ""
            ))
        }).compactMapValues { $0 }

        let rough = RoughNutritionEstimator.drink(name: drink.name, category: drink.category,
                                                   sizeML: sizeML, cupType: cupType, sweetness: sweetness,
                                                   temperature: temperature, ice: ice)
        // The summary confidence describes the three headline metrics. Each metric also keeps its own source.
        let usedRoughValue = headlineNutrients.contains { values[$0] == nil }
        let usedEstimatedValue = headlineNutrients.contains { values[$0]?.confidence == .estimated }
        let snapshotConfidence: NutritionSnapshot.Confidence = usedRoughValue ? .rough :
            (usedEstimatedValue ? .estimated : .official)
        let sources = Set(values.values.map(\.source).filter { !$0.isEmpty }).sorted()
        let sourceURLs = Set(values.values.map(\.sourceURL).filter { !$0.isEmpty }).sorted()
        let sourceDescription = (sources + (usedRoughValue ? [rough.source] : [])).joined(separator: "；")

        return NutritionSnapshot(
            energyKcal: values[.energy]?.value ?? rough.energyKcal,
            sugarGrams: values[.sugar]?.value ?? rough.sugarGrams,
            caffeineMilligrams: values[.caffeine]?.value ?? rough.caffeineMilligrams,
            confidence: snapshotConfidence,
            source: sourceDescription,
            sourceURL: sourceURLs.isEmpty ? nil : sourceURLs.joined(separator: "；"),
            proteinGrams: values[.protein]?.value ?? rough.proteinGrams,
            fatGrams: values[.fat]?.value ?? rough.fatGrams,
            carbohydrateGrams: values[.carbohydrate]?.value ?? rough.carbohydrateGrams,
            assumptions: values.count < Nutrient.allCases.count ? rough.assumptions : "",
            metricSources: Dictionary(uniqueKeysWithValues: Nutrient.allCases.map {
                ($0.rawValue, values[$0]?.confidence.rawValue ?? "rough")
            })
        )
    }

    public static func nutrientsNeedingEstimate(
        in snapshot: NutritionSnapshot,
        catalog: NutritionSnapshot? = nil
    ) -> [Nutrient] {
        Nutrient.allCases.filter { nutrient in
            nutrient.needsEstimate(in: snapshot) && (catalog.map { nutrient.needsEstimate(in: $0) } ?? true)
        }
    }

    public static func supplement(
        _ snapshot: NutritionSnapshot,
        withAI values: [String: Double],
        assumptions: String,
        catalog: NutritionSnapshot? = nil
    ) -> NutritionSnapshot? {
        let accepted = Dictionary(uniqueKeysWithValues: nutrientsNeedingEstimate(in: snapshot, catalog: catalog)
            .compactMap { nutrient -> (Nutrient, Double)? in
                guard let value = values[nutrient.rawValue], value.isFinite, (0...10_000).contains(value) else {
                    return nil
                }
                return (nutrient, value)
            })
        guard !accepted.isEmpty else { return nil }

        var metricSources = snapshot.metricSources
        for nutrient in Nutrient.allCases {
            if accepted[nutrient] != nil {
                metricSources[nutrient.rawValue] = "ai"
            } else if valid(nutrient.value(in: snapshot)) != nil, metricSources[nutrient.rawValue] == nil {
                metricSources[nutrient.rawValue] = snapshot.confidence(for: nutrient.rawValue).rawValue
            }
        }

        let source = "AI 饮品估算"
        let usesOfflineEstimate = metricSources.values.contains("rough")
        var sources = snapshot.source.components(separatedBy: "；").filter { !$0.isEmpty }
        if usesOfflineEstimate, !sources.contains(RoughNutritionEstimator.drinkSource) {
            sources.append(RoughNutritionEstimator.drinkSource)
        } else if !usesOfflineEstimate {
            sources.removeAll { $0 == RoughNutritionEstimator.drinkSource }
        }
        if !sources.contains(source) { sources.append(source) }
        let existingNotes = usesOfflineEstimate || snapshot.hasAIEstimate ? snapshot.assumptions : ""
        let notes = [existingNotes, assumptions].filter { !$0.isEmpty }.joined(separator: "；")

        func value(_ nutrient: Nutrient) -> Double? {
            accepted[nutrient] ?? valid(nutrient.value(in: snapshot))
        }
        return NutritionSnapshot(
            energyKcal: value(.energy),
            sugarGrams: value(.sugar),
            caffeineMilligrams: value(.caffeine),
            confidence: headlineNutrients.contains { metricSources[$0.rawValue] == "rough" } ? .rough : .estimated,
            source: sources.joined(separator: "；"),
            sourceURL: snapshot.sourceURL,
            proteinGrams: value(.protein),
            fatGrams: value(.fat),
            carbohydrateGrams: value(.carbohydrate),
            assumptions: notes,
            metricSources: metricSources
        )
    }

    private static func servingSelection(for variant: MenuNutritionVariant) -> DrinkServingSelection {
        DrinkServingSelection(
            temperature: variant.temperature,
            ice: variant.ice,
            legacyServingOption: variant.servingOption
        )
    }

    private static func matchesSize(_ variant: MenuNutritionVariant, cupType: String, sizeML: Int?) -> Bool {
        let expectedCupType = normalized(cupType)
        if let variantCupType = nonEmpty(variant.cupType), variantCupType != expectedCupType {
            return false
        }

        if let sizeML, sizeML > 0 {
            return variant.sizeML == sizeML
        }
        guard variant.sizeML == nil || variant.sizeML == 0 else { return false }
        guard !expectedCupType.isEmpty, let variantCupType = nonEmpty(variant.cupType) else { return false }
        return variantCupType == expectedCupType
    }

    private static func perUnitMultiplier(_ nutrition: MenuNutritionPerUnit?, sizeML: Int?) -> Double? {
        guard let nutrition, nutrition.amount.isFinite, nutrition.amount > 0 else { return nil }
        switch nutrition.unit {
        case "ml":
            guard let sizeML, sizeML > 0 else { return nil }
            return Double(sizeML) / nutrition.amount
        case "杯":
            return 1 / nutrition.amount
        default:
            return nil
        }
    }

    private static func confidence(_ sourceType: String?) -> NutritionSnapshot.Confidence {
        sourceType == "official" ? .official : .estimated
    }

    private static func valid(_ value: Double?) -> Double? {
        guard let value, value.isFinite, value >= 0 else { return nil }
        return value
    }

    private static func normalized(_ value: String?) -> String {
        value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

    private static func normalizedSweetness(_ value: String?) -> String {
        let result = normalized(value)
        switch result {
        case "无糖": return "不另外加糖"
        case "微糖": return "三分糖"
        default: return result
        }
    }

    private static func nonEmpty(_ value: String?) -> String? {
        let result = normalized(value)
        return result.isEmpty ? nil : result
    }
}
