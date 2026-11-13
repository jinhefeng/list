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

        XCTAssertNil(snapshot.energyKcal)
        XCTAssertEqual(snapshot.confidence, .unavailable)
        XCTAssertEqual(snapshot.source, "")
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

    func testPerCupBaselineDoesNotRequireCapacityAndUnknownMlSizeIsUnavailable() {
        let perCupDrink = menuDrink(perUnit: MenuNutritionPerUnit(
            amount: 1,
            unit: "杯",
            energyKcal: 120,
            sourceType: "official",
            source: "每杯营养表"
        ))
        let perCup = DrinkNutritionCalculator.snapshot(for: perCupDrink, cupType: "自定义杯")
        XCTAssertEqual(perCup.energyKcal, 120)
        XCTAssertEqual(perCup.confidence, .official)

        let perMLDrink = menuDrink(perUnit: MenuNutritionPerUnit(
            amount: 100,
            unit: "ml",
            energyKcal: 80,
            sourceType: "official"
        ))
        let unknownSize = DrinkNutritionCalculator.snapshot(for: perMLDrink, cupType: "未知容量杯")
        XCTAssertNil(unknownSize.energyKcal)
        XCTAssertEqual(unknownSize.confidence, .unavailable)
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
