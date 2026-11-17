import Foundation
import XCTest
@testable import GanfanCore

final class NutritionV2Tests: XCTestCase {
    func testLegacyNutritionSnapshotStillDecodes() throws {
        let legacy = Data(#"{"energyKcal":180,"sugarGrams":25,"caffeineMilligrams":40,"confidence":"estimated","source":"旧数据"}"#.utf8)
        let snapshot = try JSONDecoder().decode(NutritionSnapshot.self, from: legacy)
        XCTAssertEqual(snapshot.energyKcal, 180)
        XCTAssertEqual(snapshot.confidence, .estimated)
        XCTAssertNil(snapshot.proteinGrams)
        XCTAssertEqual(snapshot.assumptions, "")
    }

    func testMealDishNutritionIsPersistedWithRecord() throws {
        let nutrition = RoughNutritionEstimator.dish(name: "宫保鸡丁")
        let meal = try MealRecord(dishes: [MealDish(name: "宫保鸡丁", nutrition: nutrition)])
        let restored = try JournalRecordCodec.decode(JournalRecordCodec.encode(.meal(meal)))
        guard case .meal(let decoded) = restored else { return XCTFail("wrong type") }
        XCTAssertEqual(decoded.dishes.first?.nutrition, nutrition)
    }

    func testDefaultMealAndDrinkEstimatesAreNonempty() {
        let drink = RoughNutritionEstimator.drink(name: "自制奶茶", sizeML: 450, sweetness: "无糖")
        XCTAssertEqual(drink.confidence, .rough)
        XCTAssertGreaterThan(drink.energyKcal ?? 0, 0)
        XCTAssertGreaterThan(drink.sugarGrams ?? 0, 0) // intrinsic dairy sugar
        XCTAssertFalse(drink.assumptions.isEmpty)

        let meal = RoughNutritionEstimator.dish(name: "神秘菜品")
        XCTAssertEqual(meal.confidence, .rough)
        XCTAssertGreaterThan(meal.energyKcal ?? 0, 0)
        XCTAssertGreaterThan(meal.proteinGrams ?? 0, 0)
    }

    func testIngredientBasedEstimationIsRoughAndTraceable() {
        let snapshot = IngredientNutritionEstimator.calculate(dishName: "鸡肉饭", ingredients: [
            EstimatedFoodIngredient(name: "米饭", grams: 200),
            EstimatedFoodIngredient(name: "鸡肉", grams: 120),
            EstimatedFoodIngredient(name: "食用油", grams: 15)
        ])
        XCTAssertEqual(snapshot.confidence, .rough)
        XCTAssertGreaterThan(snapshot.energyKcal ?? 0, 400)
        XCTAssertGreaterThan(snapshot.proteinGrams ?? 0, 20)
        XCTAssertTrue(snapshot.assumptions.contains("米饭 200g"))
        XCTAssertTrue(snapshot.source.contains("AI"))
    }

    func testRemotePackMergesNutrientsAndPreservesUserOverride() throws {
        let catalog = MenuCatalog(version: "1", updatedAt: "2026-01-01",
            brands: [MenuBrand(id: "brand1", name: "示例品牌")],
            drinks: [MenuDrink(id: "tea1", brandID: "brand1", brandName: "示例品牌", name: "鲜奶茶",
                nutritionPerUnit: MenuNutritionPerUnit(amount: 100, unit: "ml", energyKcal: 40)),
                MenuDrink(id: "local-legacy", legacyIDs: ["tea-legacy"], brandID: "brand1", brandName: "示例品牌", name: "旧本地菜单")])
        let remote = NutritionDataPack(version: "2026.11.14.1", generatedAt: "2026-11-14",
            entries: [
                NutritionUpdateEntry(id: "tea1", nutritionPerUnit:
                    MenuNutritionPerUnit(amount: 100, unit: "ml", energyKcal: 68, sugarG: 6)),
                NutritionUpdateEntry(id: "tea-legacy", nutritionPerUnit:
                    MenuNutritionPerUnit(amount: 100, unit: "ml", sugarG: 9)),
                NutritionUpdateEntry(id: "tea2", brandID: "brand1", brandName: "示例品牌", name: "新款",
                    nutritionPerUnit: MenuNutritionPerUnit(amount: 100, unit: "ml", energyKcal: 20))
            ])
        let updated = try remote.merging(into: catalog)
        XCTAssertEqual(updated.drinks.count, 3)
        XCTAssertEqual(updated.drinks.first?.nutritionPerUnit?.energyKcal, 68)
        XCTAssertEqual(updated.drinks.first(where: { $0.id == "local-legacy" })?.nutritionPerUnit?.sugarG, 9)
        XCTAssertEqual(updated.drinks.first(where: { $0.id == "local-legacy" })?.legacyIDs, ["tea-legacy"])
        let custom = MenuDrink(id: "tea1", brandID: "brand1", brandName: "示例品牌",
                               name: "用户修改的鲜奶茶", localOverride: true, custom: true)
        let state = MenuCatalogUserState(drinks: [custom])
        let final = updated.merging(localBrands: [], localDrinks: state.drinks, deletedDrinkIDs: [])
        XCTAssertEqual(final.drinks.first?.name, "用户修改的鲜奶茶")
        XCTAssertEqual(final.drinks.count, 3)
    }

    func testFailedAndOutdatedPackDoNotReplaceCurrent() throws {
        let defaults = try XCTUnwrap(UserDefaults(suiteName: "nutrition-test-\(UUID().uuidString)"))
        let repo = NutritionUpdateRepository(store: defaults)
        let catalog = MenuCatalog(version: "1", updatedAt: "",
                                  brands: [], drinks: [])
        let first = NutritionDataPack(version: "2026.11.14.2", generatedAt: "2026-11-14", entries: [])
        let data = try JSONEncoder().encode(first)
        try repo.install(data, bundled: catalog)
        XCTAssertEqual(repo.load()?.version, "2026.11.14.2")
        let older = NutritionDataPack(version: "2026.11.14.1", generatedAt: "2026-11-14", entries: [])
        XCTAssertThrowsError(try repo.install(JSONEncoder().encode(older), bundled: catalog))
        XCTAssertEqual(repo.load()?.version, "2026.11.14.2")
        let bad = NutritionDataPack(version: "2026.11.14.3", generatedAt: "2026-11-14",
            entries: [NutritionUpdateEntry(id: "bad",
                nutritionPerUnit: MenuNutritionPerUnit(amount: 100, unit: "ml", energyKcal: -2))])
        XCTAssertThrowsError(try repo.install(JSONEncoder().encode(bad), bundled: catalog))
        XCTAssertEqual(repo.load()?.version, "2026.11.14.2")
    }

    func testVersionComparisonIsNumeric() {
        XCTAssertTrue(NutritionDataPack.isNewer("2026.11.15", than: "2026.11.9"))
        XCTAssertFalse(NutritionDataPack.isNewer("2026.11.8", than: "2026.11.9"))
        XCTAssertFalse(NutritionDataPack.isNewer("2026.11.9.0", than: "2026.11.9"))
    }
}
