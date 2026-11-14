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
    private enum Nutrient: CaseIterable {
        case energy
        case sugar
        case caffeine

        var variantValue: (MenuNutritionVariant) -> Double? {
            switch self {
            case .energy: { $0.energyKcal }
            case .sugar: { $0.sugarG }
            case .caffeine: { $0.caffeineMg }
            }
        }

        var unitValue: (MenuNutritionPerUnit) -> Double? {
            switch self {
            case .energy: { $0.energyKcal }
            case .sugar: { $0.sugarG }
            case .caffeine: { $0.caffeineMg }
            }
        }
    }

    private struct ValueWithSource {
        let value: Double
        let confidence: NutritionSnapshot.Confidence
        let source: String
        let sourceURL: String
    }

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
                && normalized(variant.sweetness) == normalized(sweetness)
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
        let values: [ValueWithSource?] = Nutrient.allCases.map { nutrient in
            if let selectedVariant,
               let value = valid(nutrient.variantValue(selectedVariant)) {
                return ValueWithSource(
                    value: value,
                    confidence: confidence(selectedVariant.sourceType),
                    source: selectedVariant.source ?? "",
                    sourceURL: selectedVariant.sourceURL ?? ""
                )
            }
            guard let nutrition = drink.nutritionPerUnit,
                  let multiplier,
                  let value = valid(nutrient.unitValue(nutrition)) else {
                return nil
            }
            return ValueWithSource(
                value: value * multiplier,
                confidence: confidence(nutrition.sourceType),
                source: nutrition.source ?? "",
                sourceURL: ""
            )
        }

        let availableValues = values.compactMap { $0 }
        let rough = RoughNutritionEstimator.drink(name: drink.name, category: drink.category,
                                                   sizeML: sizeML, cupType: cupType, sweetness: sweetness,
                                                   temperature: temperature, ice: ice)
        // Fill missing metrics independently, rather than reporting unknown sugar or caffeine
        // as zero. Any mixed snapshot is marked as rough, with both sources preserved.
        let usedRoughValue = values.contains(where: { $0 == nil })
        let usedEstimatedValue = availableValues.contains { $0.confidence == .estimated }
        let snapshotConfidence: NutritionSnapshot.Confidence = usedRoughValue ? .rough :
            (usedEstimatedValue ? .estimated : .official)
        let sources = Array(Set(availableValues.map(\.source).filter { !$0.isEmpty })).sorted()
        let sourceURLs = Array(Set(availableValues.map(\.sourceURL).filter { !$0.isEmpty })).sorted()
        let sourceDescription = (sources + (usedRoughValue ? [rough.source] : [])).joined(separator: "；")

        return NutritionSnapshot(
            energyKcal: values[0]?.value ?? rough.energyKcal,
            sugarGrams: values[1]?.value ?? rough.sugarGrams,
            caffeineMilligrams: values[2]?.value ?? rough.caffeineMilligrams,
            confidence: snapshotConfidence,
            source: sourceDescription,
            sourceURL: sourceURLs.isEmpty ? nil : sourceURLs.joined(separator: "；"),
            proteinGrams: macro(variant: selectedVariant?.proteinG, unit: drink.nutritionPerUnit?.proteinG, multiplier: multiplier) ?? rough.proteinGrams,
            fatGrams: macro(variant: selectedVariant?.fatG, unit: drink.nutritionPerUnit?.fatG, multiplier: multiplier) ?? rough.fatGrams,
            carbohydrateGrams: macro(variant: selectedVariant?.carbohydrateG, unit: drink.nutritionPerUnit?.carbohydrateG, multiplier: multiplier) ?? rough.carbohydrateGrams,
            assumptions: rough.assumptions,
            metricSources: [
                "energyKcal": values[0]?.confidence.rawValue ?? "rough",
                "sugarGrams": values[1]?.confidence.rawValue ?? "rough",
                "caffeineMilligrams": values[2]?.confidence.rawValue ?? "rough",
                "proteinGrams": macro(variant: selectedVariant?.proteinG, unit: drink.nutritionPerUnit?.proteinG, multiplier: multiplier) == nil ? "rough" : snapshotConfidence.rawValue,
                "fatGrams": macro(variant: selectedVariant?.fatG, unit: drink.nutritionPerUnit?.fatG, multiplier: multiplier) == nil ? "rough" : snapshotConfidence.rawValue,
                "carbohydrateGrams": macro(variant: selectedVariant?.carbohydrateG, unit: drink.nutritionPerUnit?.carbohydrateG, multiplier: multiplier) == nil ? "rough" : snapshotConfidence.rawValue
            ]
        )
    }

    private static func macro(variant: Double?, unit: Double?, multiplier: Double?) -> Double? {
        if let variant = valid(variant) { return variant }
        if let multiplier, let value = valid(unit) { return value * multiplier }
        return nil
    }

    private static var unavailable: NutritionSnapshot {
        NutritionSnapshot(energyKcal: nil, sugarGrams: nil, caffeineMilligrams: nil, confidence: .unavailable)
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

    private static func nonEmpty(_ value: String?) -> String? {
        let result = normalized(value)
        return result.isEmpty ? nil : result
    }
}
