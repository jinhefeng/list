import XCTest
@testable import GanfanCore

final class MenuCatalogRepositoryTests: XCTestCase {
    func testPersistsLocalCatalogOverridesTombstonesAndGlobalCupSizes() throws {
        let suiteName = "MenuCatalogRepositoryTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let repository = MenuCatalogRepository(userDefaults: defaults)
        let bundled = MenuCatalog(
            version: "bundled-v2",
            updatedAt: "2026-11-13",
            brands: [MenuBrand(id: "brand-1", name: "品牌")],
            drinks: [
                MenuDrink(id: "drink-1", brandID: "brand-1", brandName: "品牌", name: "原菜单名"),
                MenuDrink(id: "drink-deleted", brandID: "brand-1", brandName: "品牌", name: "已删除")
            ]
        )
        let state = MenuCatalogUserState(
            brands: [MenuBrand(id: "brand-1", name: "我的品牌名", localOverride: true)],
            drinks: [
                MenuDrink(id: "drink-1", brandID: "brand-1", brandName: "我的品牌名", name: "我的饮品名", localOverride: true),
                MenuDrink(id: "custom-1", brandID: "brand-1", brandName: "我的品牌名", name: "自定义饮品", custom: true)
            ],
            deletedDrinkIDs: ["drink-deleted"],
            globalCupSizes: [MenuCupSize(cupType: "中杯", sizeML: 500)]
        )

        try repository.saveUserState(state)

        let savedState = try repository.loadUserState()
        XCTAssertEqual(savedState, state)
        let merged = try repository.catalog(from: bundled)
        XCTAssertEqual(merged.version, "bundled-v2")
        XCTAssertEqual(merged.brands.first?.name, "我的品牌名")
        XCTAssertEqual(merged.drinks.map(\.id), ["drink-1", "custom-1"])
        XCTAssertEqual(merged.drinks.first?.name, "我的饮品名")
        XCTAssertEqual(savedState.globalCupSizes.first?.sizeML, 500)
    }

    func testReconcilesRestoredBrandAndMenusByUniqueNameAndPreservesCustomLogoAndDrinkIDs() throws {
        let suiteName = "MenuCatalogRepositoryTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let repository = MenuCatalogRepository(userDefaults: defaults)
        let logoID = UUID()
        let restored = MenuCatalog(
            version: "old",
            updatedAt: "2026-11-15",
            brands: [MenuBrand(
                id: "local-brand-manual",
                name: "太奔牛",
                logoImageID: logoID,
                logoIsOverridden: true
            )],
            drinks: [MenuDrink(
                id: "local-drink-manual",
                brandID: "local-brand-manual",
                brandName: "太奔牛",
                name: "厚乳拿铁",
                source: "手机维护",
                cupTypes: ["大杯"],
                nutritionPerUnit: MenuNutritionPerUnit(amount: 100, unit: "ml", energyKcal: 90, sourceType: "official", source: "手机标签"),
                menuEntries: [MenuEntry(scope: "brand", sourceName: "手机菜单", cupTypes: ["大杯"])],
                localOverride: true,
                custom: true
            )]
        )
        let restoredState = MenuCatalogUserState.restoredCatalogOverlay(from: restored, settings: nil)
        try repository.saveUserState(restoredState)
        let bundled = MenuCatalog(
            version: "new",
            updatedAt: "2026-11-16",
            brands: [MenuBrand(id: "brand-tai-ben-niu", name: "太犇牛", aliases: ["太奔牛"], logoAssetName: "BrandIconTaiBenNiu")],
            drinks: [MenuDrink(
                id: "brand-tai-ben-niu-drink-1",
                brandID: "brand-tai-ben-niu",
                brandName: "太犇牛",
                name: "厚乳拿铁",
                cupTypes: ["中杯"],
                nutritionPerUnit: MenuNutritionPerUnit(amount: 100, unit: "ml", sugarG: 3)
            )]
        )

        let firstCatalog = try repository.catalog(from: bundled)
        let migratedState = try repository.loadUserState()
        let secondCatalog = try repository.catalog(from: bundled)

        XCTAssertEqual(migratedState.brands.map(\.id), ["brand-tai-ben-niu"])
        XCTAssertEqual(firstCatalog.brands.map(\.id), ["brand-tai-ben-niu"])
        XCTAssertEqual(firstCatalog.brands.first?.logoImageID, logoID)
        XCTAssertTrue(firstCatalog.brands.first?.logoIsOverridden == true)
        XCTAssertEqual(firstCatalog.drinks.map(\.id), ["local-drink-manual"])
        XCTAssertEqual(firstCatalog.drinks.first?.brandID, "brand-tai-ben-niu")
        XCTAssertEqual(firstCatalog.drinks.first?.legacyIDs, ["brand-tai-ben-niu-drink-1"])
        XCTAssertEqual(firstCatalog.drinks.first?.cupTypes, ["大杯", "中杯"])
        XCTAssertEqual(firstCatalog.drink(for: "brand-tai-ben-niu-drink-1")?.id, "local-drink-manual")
        XCTAssertEqual(firstCatalog.drinks.first?.nutritionPerUnit?.energyKcal, 90)
        XCTAssertEqual(firstCatalog.drinks.first?.nutritionPerUnit?.sugarG, 3)
        XCTAssertEqual(secondCatalog, firstCatalog)
        XCTAssertEqual(try repository.loadUserState(), migratedState)
    }

    func testUncustomizedRestoredBrandUsesBundledLogoAndAmbiguousNameIsLeftAlone() throws {
        let suiteName = "MenuCatalogRepositoryTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let repository = MenuCatalogRepository(userDefaults: defaults)
        let restored = MenuCatalog(
            version: "old",
            updatedAt: "2026-11-15",
            brands: [MenuBrand(id: "local-brand-peets", name: "Peets Coffee")],
            drinks: []
        )
        try repository.saveUserState(.restoredCatalogOverlay(from: restored, settings: nil))
        let bundled = MenuCatalog(
            version: "new",
            updatedAt: "2026-11-16",
            brands: [
                MenuBrand(id: "brand-peets", name: "Peet's", aliases: ["Peets Coffee"], logoAssetName: "PeetsLogo"),
                MenuBrand(id: "brand-other", name: "Other", aliases: ["Peets Coffee"])
            ],
            drinks: []
        )

        let catalog = try repository.catalog(from: bundled)
        let state = try repository.loadUserState()

        XCTAssertTrue(state.brands.contains(where: { $0.id == "local-brand-peets" }))
        XCTAssertTrue(catalog.brands.contains(where: { $0.id == "local-brand-peets" }))
        XCTAssertNil(catalog.brands.first(where: { $0.id == "brand-peets" })?.logoImageID)
        XCTAssertEqual(catalog.brands.first(where: { $0.id == "brand-peets" })?.logoAssetName, "PeetsLogo")
    }
}
