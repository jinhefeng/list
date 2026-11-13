import XCTest
@testable import GanfanCore

final class MenuCatalogTests: XCTestCase {
    func testSearchMatchesAliasesAndKeepsPendingSourceState() throws {
        let brand = MenuBrand(
            id: "brand-mixue",
            name: "蜜雪冰城",
            aliases: ["MXBC"],
            source: "公开菜单汇编；具体门店待核验",
            sourceURL: "https://example.test/menu",
            status: "pending"
        )
        let drink = MenuDrink(
            id: "mixue-lemon-water",
            brandID: brand.id,
            brandName: brand.name,
            name: "冰鲜柠檬水",
            aliases: ["柠檬水"],
            source: "公开菜单汇编；具体门店待核验",
            sourceURL: brand.sourceURL,
            status: "pending"
        )
        let catalog = MenuCatalog(version: "test", updatedAt: "2026-11-13", brands: [brand], drinks: [drink])

        XCTAssertEqual(catalog.searchBrands("mxbc").first?.id, brand.id)
        XCTAssertEqual(catalog.searchDrinks(brandID: brand.id, query: "柠檬水").first?.id, drink.id)
        XCTAssertEqual(catalog.searchDrinks(brandID: brand.id, query: "not found").count, 0)
        XCTAssertEqual(catalog.searchDrinks(brandID: brand.id, query: "柠檬").first?.status, "pending")

        let decoded = try MenuCatalog.decode(JSONEncoder().encode(catalog))
        XCTAssertEqual(decoded.drinks.first?.sourceURL, "https://example.test/menu")
        XCTAssertEqual(decoded.drinks.first?.status, "pending")
    }

    func testDecodesFullMenuOptionsNutritionAndProvenance() throws {
        let json = Data(#"""
        {
          "version":"v2",
          "generatedAt":"2026-11-13",
          "brands":[{"id":"b1","name":"品牌","aliases":["Brand"],"category":"茶饮","active":true,"status":"verified","source":"官网"}],
          "drinks":[{
            "id":"d1","brandId":"b1","brandName":"品牌","name":"青茶","aliases":["清茶"],"category":"纯茶",
            "active":true,"status":"pending","source":"来源说明","sourceType":"public_menu","sourceName":"公开菜单",
            "sourceUrl":"https://example.test/menu","updatedAt":"2026-11-13",
            "cupTypes":["中杯"],"cupSizes":[{"cupType":"中杯","sizeMl":500}],"sizesMl":[500],
            "sweetnessOptions":["无糖","半糖"],"servingOptions":["去冰","热饮"],
            "nutritionPerUnit":{"amount":100,"unit":"ml","energyKcal":12,"sugarG":2,"caffeineMg":8,"sourceType":"official","source":"营养标签"},
            "nutritionVariants":[{"cupType":"中杯","sizeMl":500,"sweetness":"无糖","energyKcal":60,"sugarG":10,"caffeineMg":40,"sourceType":"official","source":"品牌资料","updatedAt":"2026-11-13"}],
            "menuEntries":[{"scope":"store","city":"杭州","storeId":"s1","storeName":"品牌门店","status":"verified","sourceType":"authorized_platform","sourceName":"平台菜单","sourceUrl":"https://example.test/store","checkedAt":"2026-11-13","cupTypes":["中杯"],"cupSizes":[{"cupType":"中杯","sizeMl":500}],"sizesMl":[500],"sweetnessOptions":["无糖"],"servingOptions":["去冰"]}]
          }]
        }
        """#.utf8)

        let catalog = try MenuCatalog.decode(json)
        let drink = try XCTUnwrap(catalog.drinks.first)
        XCTAssertEqual(catalog.updatedAt, "2026-11-13")
        XCTAssertEqual(drink.cupTypes, ["中杯"])
        XCTAssertEqual(drink.cupSizes.first?.sizeML, 500)
        XCTAssertEqual(drink.sweetnessOptions, ["无糖", "半糖"])
        XCTAssertEqual(drink.nutritionPerUnit?.energyKcal, 12)
        XCTAssertEqual(drink.nutritionVariants.first?.sweetness, "无糖")
        XCTAssertEqual(drink.menuEntries.first?.sourceType, "authorized_platform")
        XCTAssertEqual(drink.menuEntries.first?.city, "杭州")
    }

    func testLocalCatalogOverlayKeepsUserChangesAndHonorsDeletionTombstones() {
        let bundled = MenuCatalog(
            version: "bundled-2",
            updatedAt: "2026-11-13",
            brands: [MenuBrand(id: "b1", name: "旧品牌"), MenuBrand(id: "b2", name: "保留品牌")],
            drinks: [
                MenuDrink(id: "d1", brandID: "b1", brandName: "旧品牌", name: "旧名称"),
                MenuDrink(id: "d2", brandID: "b2", brandName: "保留品牌", name: "待删除")
            ]
        )
        let brandOverride = MenuBrand(id: "b1", name: "自定义品牌名", localOverride: true)
        let drinkOverride = MenuDrink(id: "d1", brandID: "b1", brandName: "自定义品牌名", name: "自定义名称", localOverride: true)
        let customDrink = MenuDrink(id: "custom", brandID: "b1", brandName: "自定义品牌名", name: "自定义饮品", localOverride: true)

        let merged = bundled.merging(
            localBrands: [brandOverride],
            localDrinks: [drinkOverride, customDrink],
            deletedDrinkIDs: ["d2"]
        )

        XCTAssertEqual(merged.version, "bundled-2")
        XCTAssertEqual(merged.brands.map(\.name), ["自定义品牌名", "保留品牌"])
        XCTAssertEqual(merged.drinks.map(\.id), ["d1", "custom"])
        XCTAssertEqual(merged.drinks.first?.name, "自定义名称")
    }
}
