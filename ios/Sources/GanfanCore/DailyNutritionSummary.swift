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
            energyKcal: Self.total(drinks) { $0.energyKcal },
            sugarGrams: Self.total(drinks) { $0.sugarGrams },
            caffeineMilligrams: Self.total(drinks) { $0.caffeineMilligrams }
        )
    }

    private static func total(
        _ drinks: [DrinkRecord],
        value: (NutritionSnapshot) -> Double?
    ) -> NutritionMetricTotal {
        var values: [Double] = []
        var qualities: [NutritionSnapshot.Confidence] = []
        for drink in drinks {
            guard let snapshot = drink.nutrition,
                  let amount = value(snapshot),
                  amount.isFinite,
                  amount >= 0 else { continue }
            values.append(amount)
            qualities.append(snapshot.confidence == .unavailable ? .estimated : snapshot.confidence)
        }

        guard !values.isEmpty else {
            return NutritionMetricTotal(value: nil, confidence: .unavailable, knownRecordCount: 0)
        }
        let confidence: NutritionSnapshot.Confidence = qualities.contains(.rough) ? .rough : (qualities.contains(.estimated) ? .estimated : .official)
        return NutritionMetricTotal(value: values.reduce(0, +), confidence: confidence, knownRecordCount: values.count)
    }
}
