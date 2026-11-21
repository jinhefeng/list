import XCTest
@testable import GanfanCore

final class DrinkNutritionCalculatorTests: XCTestCase {
    func testLegacyServingOptionsNormalizeIntoTemperatureAndIce() {
        XCTAssertEqual(
            DrinkServingSelection(legacyServingOption: "少冰"),
            DrinkServingSelection(temperature: "冰饮", ice: "少冰")
        )
        XCTAssertEqual(
            DrinkServingSelection(legacyServingOption: "热"),
            DrinkServingSelection(temperature: "热饮", ice: "")
        )
        XCTAssertEqual(
            DrinkServingSelection(temperature: "", ice: "去冰"),
            DrinkServingSelection(temperature: "冰饮", ice: "去冰")
        )
    }

    func testExactOfficialVariantMatchesSizeSweetnessTemperatureAndIce() {
        let variant = MenuNutritionVariant(
            cupType: "中杯",
            sizeML: 500,
            sweetness: "半糖",
            temperature: "冰饮",
            ice: "少冰",
            energyKcal: 185,
            sugarG: 24,
            caffeineMg: 46,
            sourceType: "official",
            source: "品牌营养表",
            sourceURL: "https://example.invalid/nutrition"
        )
        let drink = menuDrink(
            variants: [variant],
            perUnit: MenuNutritionPerUnit(
                amount: 100,
                unit: "ml",
                energyKcal: 999,
                sourceType: "estimated",
                source: "低优先级基准"
            )
        )

        let snapshot = DrinkNutritionCalculator.snapshot(
            for: drink,
            cupType: "中杯",
            sizeML: 500,
            sweetness: "半糖",
            temperature: "冰饮",
            ice: "少冰"
        )

        XCTAssertEqual(snapshot.energyKcal, 185)
        XCTAssertEqual(snapshot.sugarGrams, 24)
        XCTAssertEqual(snapshot.caffeineMilligrams, 46)
        XCTAssertEqual(snapshot.confidence, .official)
        XCTAssertEqual(snapshot.source, "品牌营养表")
        XCTAssertEqual(snapshot.sourceURL, "https://example.invalid/nutrition")
    }

    func testVariantWithUnrecordedToppingsDoesNotMatch() {
        let toppingVariant = MenuNutritionVariant(
            cupType: "中杯",
            sizeML: 500,
            sweetness: "半糖",
            temperature: "冰饮",
            ice: "少冰",
            toppings: ["珍珠"],
            energyKcal: 300,
            sourceType: "official",
            source: "含珍珠规格"
        )

        let snapshot = DrinkNutritionCalculator.snapshot(
            for: menuDrink(variants: [toppingVariant]),
            cupType: "中杯",
            sizeML: 500,
            sweetness: "半糖",
            temperature: "冰饮",
            ice: "少冰"
        )

        XCTAssertNotNil(snapshot.energyKcal)
        XCTAssertEqual(snapshot.confidence, .rough)
        XCTAssertTrue(snapshot.source.contains("粗估"))
    }

    func testPerMilliliterBaselineScalesWithKnownSize() {
        let drink = menuDrink(perUnit: MenuNutritionPerUnit(
            amount: 100,
            unit: "ml",
            energyKcal: 80,
            sugarG: 11,
            caffeineMg: 20,
            sourceType: "estimated",
            source: "按每 100 ml 估算"
        ))

        let snapshot = DrinkNutritionCalculator.snapshot(for: drink, cupType: "大杯", sizeML: 450)

        XCTAssertEqual(try XCTUnwrap(snapshot.energyKcal), 360, accuracy: 0.001)
        XCTAssertEqual(try XCTUnwrap(snapshot.sugarGrams), 49.5, accuracy: 0.001)
        XCTAssertEqual(try XCTUnwrap(snapshot.caffeineMilligrams), 90, accuracy: 0.001)
        XCTAssertEqual(snapshot.confidence, .estimated)
        XCTAssertEqual(snapshot.source, "按每 100 ml 估算")
    }

    func testPerCupBaselineDoesNotRequireCapacityAndUnknownMlSizeFallsBackToRough() {
        let perCupDrink = menuDrink(perUnit: MenuNutritionPerUnit(
            amount: 1,
            unit: "杯",
            energyKcal: 120,
            sourceType: "official",
            source: "每杯营养表"
        ))
        let perCup = DrinkNutritionCalculator.snapshot(for: perCupDrink, cupType: "自定义杯")
        XCTAssertEqual(perCup.energyKcal, 120)
        XCTAssertEqual(perCup.confidence, .rough)
        XCTAssertEqual(perCup.metricSources["energyKcal"], "official")
        XCTAssertEqual(perCup.metricSources["sugarGrams"], "rough")

        let perMLDrink = menuDrink(perUnit: MenuNutritionPerUnit(
            amount: 100,
            unit: "ml",
            energyKcal: 80,
            sourceType: "official"
        ))
        let unknownSize = DrinkNutritionCalculator.snapshot(for: perMLDrink, cupType: "未知容量杯")
        XCTAssertNotNil(unknownSize.energyKcal)
        XCTAssertEqual(unknownSize.confidence, .rough)
    }

    func testRoughEstimateDoesNotClaimZeroSugarForMilkTea() {
        let drink = MenuDrink(id: "tea", brandID: "a", brandName: "示例", name: "鲜奶茶", category: "奶茶")
        let result = DrinkNutritionCalculator.snapshot(for: drink, cupType: "中杯", sizeML: 500, sweetness: "无糖")
        XCTAssertEqual(result.confidence, .rough)
        XCTAssertGreaterThan(result.sugarGrams ?? 0, 0)
        XCTAssertNotNil(result.energyKcal)
        XCTAssertNotNil(result.proteinGrams)
        XCTAssertTrue(result.assumptions.contains("500"))
    }

    func testKnownGenericBaselineIsNotReusedForDifferentSweetness() {
        let drink = menuDrink(perUnit: MenuNutritionPerUnit(
            amount: 100, unit: "ml", energyKcal: 80, sourceType: "official"
        ))
        let result = DrinkNutritionCalculator.snapshot(for: drink, sizeML: 500, sweetness: "三分糖")
        XCTAssertEqual(result.confidence, .rough)
        XCTAssertNotEqual(result.energyKcal, 400)
    }

    func testAISupplementProtectsCatalogValuesAndRetainsOfflineFallback() throws {
        let variant = MenuNutritionVariant(
            cupType: "中杯", sizeML: 500, energyKcal: 185, proteinG: 8, fatG: 0,
            sourceType: "official", source: "品牌营养表", sourceURL: "https://example.invalid/nutrition"
        )
        let baseline = DrinkNutritionCalculator.snapshot(for: menuDrink(variants: [variant]), cupType: "中杯", sizeML: 500)
        XCTAssertEqual(baseline.confidence, .rough)
        XCTAssertEqual(baseline.confidence(for: "proteinGrams"), .official)

        let result = try XCTUnwrap(DrinkNutritionCalculator.supplement(
            baseline,
            withAI: ["energyKcal": 300, "proteinGrams": 12, "fatGrams": 2, "sugarGrams": 14, "caffeineMilligrams": -1],
            assumptions: "按整杯估算"
        ))

        XCTAssertEqual(result.energyKcal, 185)
        XCTAssertEqual(result.proteinGrams, 8)
        XCTAssertEqual(result.fatGrams, 0)
        XCTAssertEqual(result.sugarGrams, 14)
        XCTAssertEqual(result.caffeineMilligrams, baseline.caffeineMilligrams)
        XCTAssertEqual(result.metricSources["sugarGrams"], "ai")
        XCTAssertEqual(result.confidence(for: "sugarGrams"), .estimated)
        XCTAssertEqual(result.confidence(for: "caffeineMilligrams"), .rough)
        XCTAssertTrue(result.hasAIEstimate)
        XCTAssertTrue(result.source.contains("品牌营养表"))
        XCTAssertTrue(result.source.contains("离线饮品分类粗估"))
        XCTAssertTrue(result.source.contains("AI 饮品估算"))
        XCTAssertEqual(result.sourceURL, baseline.sourceURL)
        XCTAssertTrue(result.assumptions.contains("按整杯估算"))
    }

    func testAILeavesUnknownValuesMissingAndKeepsPreviouslyAcceptedEstimates() throws {
        let baseline = NutritionSnapshot(
            energyKcal: nil, sugarGrams: nil, caffeineMilligrams: nil, confidence: .unavailable
        )
        let result = try XCTUnwrap(DrinkNutritionCalculator.supplement(
            baseline, withAI: ["sugarGrams": 0, "energyKcal": .infinity], assumptions: ""
        ))
        XCTAssertNil(result.energyKcal)
        XCTAssertNil(result.caffeineMilligrams)
        XCTAssertEqual(result.sugarGrams, 0)
        XCTAssertEqual(result.metricSources["sugarGrams"], "ai")
        XCTAssertNil(DrinkNutritionCalculator.supplement(result, withAI: ["sugarGrams": 9], assumptions: ""))
    }

    func testMatchedCatalogProtectsLegacySnapshotWithAmbiguousMacroSources() throws {
        let legacy = NutritionSnapshot(
            energyKcal: 100, sugarGrams: nil, caffeineMilligrams: nil, confidence: .rough,
            proteinGrams: 12, metricSources: ["proteinGrams": "rough"]
        )
        let catalog = NutritionSnapshot(
            energyKcal: nil, sugarGrams: nil, caffeineMilligrams: nil, confidence: .rough,
            proteinGrams: 12, metricSources: ["proteinGrams": "official"]
        )
        let result = try XCTUnwrap(DrinkNutritionCalculator.supplement(
            legacy, withAI: ["sugarGrams": 10, "proteinGrams": 17], assumptions: "", catalog: catalog
        ))

        XCTAssertEqual(result.proteinGrams, 12)
        XCTAssertEqual(result.sugarGrams, 10)
    }

    private func menuDrink(
        variants: [MenuNutritionVariant] = [],
        perUnit: MenuNutritionPerUnit? = nil
    ) -> MenuDrink {
        MenuDrink(
            id: "drink.test",
            brandID: "brand.test",
            brandName: "测试品牌",
            name: "测试饮品",
            nutritionPerUnit: perUnit,
            nutritionVariants: variants
        )
    }
}
