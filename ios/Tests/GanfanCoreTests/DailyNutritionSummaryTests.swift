import XCTest
@testable import GanfanCore

final class DailyNutritionSummaryTests: XCTestCase {
    func testDailyTotalsOnlyIncludeDrinkRecordsAndDoNotTurnUnknownIntoZero() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(secondsFromGMT: 0))
        let day = try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-11-13T12:00:00Z"))
        let official = try DrinkRecord(
            consumedAt: day,
            drinkName: "官方茶",
            nutrition: NutritionSnapshot(energyKcal: 100, sugarGrams: 8, caffeineMilligrams: nil, confidence: .official, source: "标签")
        )
        let estimated = try DrinkRecord(
            consumedAt: day.addingTimeInterval(60),
            drinkName: "估算咖啡",
            nutrition: NutritionSnapshot(energyKcal: 50, sugarGrams: nil, caffeineMilligrams: 20, confidence: .estimated)
        )
        let unknown = try DrinkRecord(
            consumedAt: day.addingTimeInterval(120),
            drinkName: "未知饮品",
            nutrition: NutritionSnapshot(energyKcal: nil, sugarGrams: nil, caffeineMilligrams: nil, confidence: .unavailable)
        )
        let yesterday = try DrinkRecord(consumedAt: day.addingTimeInterval(-86_400), drinkName: "昨天")
        let meal = try MealRecord(consumedAt: day, dishes: [MealDish(name: "午餐")])

        let summary = DailyNutritionSummary.summarize(
            [.drink(official), .drink(estimated), .drink(unknown), .drink(yesterday), .meal(meal)],
            on: day,
            calendar: calendar
        )

        XCTAssertEqual(summary.drinkCount, 3)
        XCTAssertEqual(summary.energyKcal.value, 150)
        XCTAssertEqual(summary.energyKcal.confidence, .estimated)
        XCTAssertEqual(summary.energyKcal.knownRecordCount, 2)
        XCTAssertEqual(summary.sugarGrams.value, 8)
        XCTAssertEqual(summary.sugarGrams.confidence, .official)
        XCTAssertEqual(summary.caffeineMilligrams.value, 20)
        XCTAssertEqual(summary.caffeineMilligrams.knownRecordCount, 1)
    }

    func testMetricWithNoKnownValuesIsUnavailableInsteadOfZero() throws {
        let date = Date(timeIntervalSince1970: 1_794_600_000)
        let drink = try DrinkRecord(
            consumedAt: date,
            drinkName: "未知饮品",
            nutrition: NutritionSnapshot(energyKcal: nil, sugarGrams: nil, caffeineMilligrams: nil, confidence: .unavailable)
        )

        let summary = DailyNutritionSummary.summarize([.drink(drink)], on: date)

        XCTAssertNil(summary.energyKcal.value)
        XCTAssertEqual(summary.energyKcal.confidence, .unavailable)
        XCTAssertEqual(summary.drinkCount, 1)
    }

    func testMixedSnapshotKeepsOfficialAndAIEstimatedMetricsDistinctInTotals() throws {
        let date = Date()
        let nutrition = NutritionSnapshot(
            energyKcal: 185, sugarGrams: 14, caffeineMilligrams: 40, confidence: .rough,
            metricSources: ["energyKcal": "official", "sugarGrams": "ai", "caffeineMilligrams": "rough"]
        )
        let drink = try DrinkRecord(consumedAt: date, drinkName: "测试饮品", nutrition: nutrition)
        let summary = DailyNutritionSummary.summarize([.drink(drink)], on: date)

        XCTAssertEqual(summary.energyKcal, NutritionMetricTotal(value: 185, confidence: .official, knownRecordCount: 1))
        XCTAssertEqual(summary.sugarGrams, NutritionMetricTotal(value: 14, confidence: .estimated, knownRecordCount: 1))
        XCTAssertEqual(summary.caffeineMilligrams, NutritionMetricTotal(value: 40, confidence: .rough, knownRecordCount: 1))
    }
}
