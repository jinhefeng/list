import Foundation

public struct NutritionMetricTotal: Equatable, Sendable {
    public let value: Double?
    public let confidence: NutritionSnapshot.Confidence
    public let knownRecordCount: Int
}

public struct DailyNutritionSummary: Equatable, Sendable {
    public let drinkCount: Int
    public let officialCount: Int
    public let estimatedCount: Int
    public let roughCount: Int
    public let unavailableCount: Int
    public let energyKcal: NutritionMetricTotal
    public let proteinGrams: NutritionMetricTotal
    public let fatGrams: NutritionMetricTotal
    public let sugarGrams: NutritionMetricTotal
    public let caffeineMilligrams: NutritionMetricTotal

    public static func summarize(
        _ records: [JournalRecord],
        on date: Date,
        calendar: Calendar = .current
    ) -> DailyNutritionSummary {
        let start = calendar.startOfDay(for: date)
        let end = calendar.date(byAdding: .day, value: 1, to: start) ?? start.addingTimeInterval(86_400)
        let drinks = records.compactMap { record -> DrinkRecord? in
            guard case .drink(let drink) = record, drink.consumedAt >= start, drink.consumedAt < end else { return nil }
            return drink
        }

        let qualities = drinks.map { drink in
            drink.nutrition?.confidence ?? .unavailable
        }
        return DailyNutritionSummary(
            drinkCount: drinks.count,
            officialCount: qualities.filter { $0 == .official }.count,
            estimatedCount: qualities.filter { $0 == .estimated }.count,
            roughCount: qualities.filter { $0 == .rough }.count,
            unavailableCount: qualities.filter { $0 == .unavailable }.count,
            energyKcal: Self.total(drinks, nutrient: .energy),
            proteinGrams: Self.total(drinks, nutrient: .protein),
            fatGrams: Self.total(drinks, nutrient: .fat),
            sugarGrams: Self.total(drinks, nutrient: .sugar),
            caffeineMilligrams: Self.total(drinks, nutrient: .caffeine)
        )
    }

    private static func total(
        _ drinks: [DrinkRecord],
        nutrient: DrinkNutritionCalculator.Nutrient
    ) -> NutritionMetricTotal {
        var values: [Double] = []
        var qualities: [NutritionSnapshot.Confidence] = []
        for drink in drinks {
            guard let snapshot = drink.nutrition,
                  let amount = nutrient.value(in: snapshot),
                  amount.isFinite,
                  amount >= 0 else { continue }
            values.append(amount)
            let confidence = snapshot.confidence(for: nutrient.rawValue)
            qualities.append(confidence == .unavailable ? .estimated : confidence)
        }

        guard !values.isEmpty else {
            return NutritionMetricTotal(value: nil, confidence: .unavailable, knownRecordCount: 0)
        }
        let confidence: NutritionSnapshot.Confidence = qualities.contains(.rough) ? .rough : (qualities.contains(.estimated) ? .estimated : .official)
        return NutritionMetricTotal(value: values.reduce(0, +), confidence: confidence, knownRecordCount: values.count)
    }
}
