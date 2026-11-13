import Foundation
import XCTest
@testable import GanfanCore

final class JournalModelTests: XCTestCase {
    func testDrinkRecordRoundTripsWithOptionalFieldsAndNutritionSnapshot() throws {
        let record = try DrinkRecord(
            consumedAt: Date(timeIntervalSince1970: 1_800_000_000),
            brandName: " 星巴克 ",
            drinkName: " 拿铁 ",
            sweetness: "无糖",
            locationName: "湖滨店",
            locationAddress: "杭州市上城区平海路",
            latitude: 30.2500,
            longitude: 120.1700,
            nutrition: NutritionSnapshot(
                energyKcal: 180,
                sugarGrams: nil,
                caffeineMilligrams: 95,
                confidence: .estimated,
                source: "试算",
                sourceURL: "https://example.invalid/source"
            )
        )

        let encoded = try JournalRecordCodec.encode(.drink(record))
        let decoded = try JournalRecordCodec.decode(encoded)

        XCTAssertEqual(decoded, .drink(record))
        XCTAssertEqual(record.brandName, "星巴克")
        XCTAssertEqual(record.drinkName, "拿铁")
        XCTAssertEqual(record.locationName, "湖滨店")
        XCTAssertEqual(record.locationAddress, "杭州市上城区平海路")
        XCTAssertEqual(record.latitude, 30.2500)
        XCTAssertEqual(record.longitude, 120.1700)
    }

    func testDrinkRecordRoundTripsSeparateTemperatureAndIceFields() throws {
        let record = try DrinkRecord(
            consumedAt: Date(timeIntervalSince1970: 1_800_000_000),
            drinkName: "冰乌龙",
            temperature: "冰饮",
            ice: "少冰"
        )

        let decoded = try JournalRecordCodec.decode(JournalRecordCodec.encode(.drink(record)))

        XCTAssertEqual(decoded, .drink(record))
        XCTAssertEqual(record.temperature, "冰饮")
        XCTAssertEqual(record.ice, "少冰")
    }

    func testOlderDrinkPayloadWithoutTemperatureAndIceStillDecodes() throws {
        let original = try DrinkRecord(drinkName: "旧记录", servingOption: "少冰")
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: JournalRecordCodec.encode(.drink(original))) as? [String: Any])
        var drink = try XCTUnwrap(object["drink"] as? [String: Any])
        var fields = try XCTUnwrap(drink["_0"] as? [String: Any])
        fields.removeValue(forKey: "temperature")
        fields.removeValue(forKey: "ice")
        drink["_0"] = fields
        object["drink"] = drink
        let olderPayload = try JSONSerialization.data(withJSONObject: object)

        let decoded = try JournalRecordCodec.decode(olderPayload)

        guard case .drink(let restored) = decoded else {
            return XCTFail("Expected a drink record")
        }
        XCTAssertEqual(restored.servingOption, "少冰")
        XCTAssertNil(restored.temperature)
        XCTAssertNil(restored.ice)
    }

    func testMealRecordKeepsMultipleDishNamesAndOrder() throws {
        let dishes = [
            try MealDish(name: " 红烧肉 "),
            try MealDish(name: "青菜")
        ]
        let record = try MealRecord(
            storeName: "小馆",
            locationAddress: "浙江省杭州市西湖区",
            latitude: 30.2741,
            longitude: 120.1551,
            dishes: dishes
        )

        let decoded = try JournalRecordCodec.decode(JournalRecordCodec.encode(.meal(record)))
        guard case .meal(let restored) = decoded else {
            return XCTFail("Expected a meal record")
        }

        XCTAssertEqual(restored.id, record.id)
        XCTAssertEqual(restored.consumedAt.timeIntervalSince1970, record.consumedAt.timeIntervalSince1970, accuracy: 1)
        XCTAssertEqual(restored.storeName, record.storeName)
        XCTAssertEqual(restored.locationAddress, record.locationAddress)
        XCTAssertEqual(restored.latitude, record.latitude)
        XCTAssertEqual(restored.longitude, record.longitude)
        XCTAssertEqual(restored.dishes.map(\.id), record.dishes.map(\.id))
        XCTAssertEqual(restored.dishes.map(\.name), ["红烧肉", "青菜"])
    }

    func testMealRecordCanKeepManualAddressWithoutMapCoordinates() throws {
        let record = try MealRecord(
            storeName: "街边小店",
            locationAddress: "杭州市上城区某路",
            dishes: [try MealDish(name: "馄饨")]
        )

        let decoded = try JournalRecordCodec.decode(JournalRecordCodec.encode(.meal(record)))

        guard case .meal(let restored) = decoded else {
            return XCTFail("Expected a meal record")
        }
        XCTAssertEqual(restored.locationAddress, "杭州市上城区某路")
        XCTAssertNil(restored.latitude)
        XCTAssertNil(restored.longitude)
    }

    func testRejectsMissingDrinkNameAndDishName() throws {
        XCTAssertThrowsError(try DrinkRecord(drinkName: "   ")) { error in
            XCTAssertEqual(error as? JournalModelError, .emptyDrinkName)
        }
        XCTAssertThrowsError(try MealDish(name: "  ")) { error in
            XCTAssertEqual(error as? JournalModelError, .emptyDishName)
        }
        XCTAssertThrowsError(try MealRecord(dishes: [])) { error in
            XCTAssertEqual(error as? JournalModelError, .mealNeedsDish)
        }
    }

    func testCustomDrinkDoesNotNeedACatalogEntry() throws {
        let customDrink = try DrinkRecord(
            brandID: "",
            brandName: "",
            drinkID: "",
            drinkName: "家里手冲咖啡"
        )

        let decoded = try JournalRecordCodec.decode(JournalRecordCodec.encode(.drink(customDrink)))

        guard case .drink(let decodedDrink) = decoded else {
            return XCTFail("Expected a custom drink record")
        }
        XCTAssertEqual(decodedDrink.id, customDrink.id)
        XCTAssertEqual(decodedDrink.brandID, "")
        XCTAssertEqual(decodedDrink.brandName, "")
        XCTAssertEqual(decodedDrink.drinkID, "")
        XCTAssertEqual(decodedDrink.drinkName, "家里手冲咖啡")
    }

    func testRejectsInvalidSizeAndCoordinates() throws {
        XCTAssertThrowsError(try DrinkRecord(drinkName: "茶", sizeML: -1)) { error in
            XCTAssertEqual(error as? JournalModelError, .invalidSize)
        }
        XCTAssertThrowsError(try MealRecord(latitude: 100, longitude: 0, dishes: [try MealDish(name: "饭")])) { error in
            XCTAssertEqual(error as? JournalModelError, .invalidCoordinate)
        }
    }

    func testDecoderRevalidatesCodableRecords() throws {
        let validRecord = try DrinkRecord(drinkName: "茶")
        let encoded = try JournalRecordCodec.encode(.drink(validRecord))
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: [String: [String: Any]]])
        var drinkObject = try XCTUnwrap(object["drink"])
        var fields = try XCTUnwrap(drinkObject["_0"])
        fields["drinkName"] = "   "
        drinkObject["_0"] = fields
        object["drink"] = drinkObject
        let invalidEncoded = try JSONSerialization.data(withJSONObject: object)

        XCTAssertThrowsError(try JournalRecordCodec.decode(invalidEncoded)) { error in
            XCTAssertEqual(error as? JournalModelError, .emptyDrinkName)
        }
    }

    func testTimelineSortsMixedRecordTypesNewestFirst() throws {
        let olderDrink = try DrinkRecord(consumedAt: Date(timeIntervalSince1970: 100), drinkName: "茶")
        let newerMeal = try MealRecord(consumedAt: Date(timeIntervalSince1970: 300), dishes: [try MealDish(name: "饭")])
        let middleDrink = try DrinkRecord(consumedAt: Date(timeIntervalSince1970: 200), drinkName: "咖啡")

        XCTAssertEqual(
            JournalRecord.newestFirst([.drink(olderDrink), .meal(newerMeal), .drink(middleDrink)]),
            [.meal(newerMeal), .drink(middleDrink), .drink(olderDrink)]
        )
    }
}
