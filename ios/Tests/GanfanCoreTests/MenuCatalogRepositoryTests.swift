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
}
