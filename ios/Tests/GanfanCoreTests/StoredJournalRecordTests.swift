import Foundation
import SwiftData
import XCTest
@testable import GanfanCore

@MainActor
final class StoredJournalRecordTests: XCTestCase {
    func testNewContainerStartsWithAnEmptyLibrary() throws {
        let container = try makeInMemoryContainer()
        let context = ModelContext(container)

        XCTAssertTrue(try context.fetch(FetchDescriptor<StoredJournalRecord>()).isEmpty)
    }

    func testStoresAndFetchesDrinkAndMealFromSwiftData() throws {
        let container = try makeInMemoryContainer()
        let context = ModelContext(container)
        let drink = try DrinkRecord(drinkName: "拿铁")
        let meal = try MealRecord(dishes: [try MealDish(name: "米饭"), try MealDish(name: "青菜")])

        context.insert(try StoredJournalRecord(record: .drink(drink)))
        context.insert(try StoredJournalRecord(record: .meal(meal)))
        try context.save()

        let fetched = try context.fetch(FetchDescriptor<StoredJournalRecord>())
        let decoded = try fetched.map { try $0.decodeRecord() }
        XCTAssertEqual(decoded.count, 2)
        guard case .drink(let restoredDrink)? = decoded.first(where: { $0.id == drink.id }),
              case .meal(let restoredMeal)? = decoded.first(where: { $0.id == meal.id }) else {
            return XCTFail("Expected both stored record types")
        }
        XCTAssertEqual(restoredDrink.drinkName, drink.drinkName)
        XCTAssertEqual(restoredMeal.dishes.map(\.name), meal.dishes.map(\.name))
        XCTAssertEqual(restoredMeal.consumedAt.timeIntervalSince1970, meal.consumedAt.timeIntervalSince1970, accuracy: 1)
    }

    func testEditedRecordMarksItForBackupAndKeepsItsIdentifier() throws {
        let container = try makeInMemoryContainer()
        let context = ModelContext(container)
        let original = try DrinkRecord(drinkName: "拿铁")
        let stored = try StoredJournalRecord(record: .drink(original), needsBackup: false)
        context.insert(stored)

        let updated = try DrinkRecord(id: original.id, drinkName: "美式")
        try stored.replace(with: .drink(updated))
        try context.save()

        guard case .drink(let restored) = try stored.decodeRecord() else {
            return XCTFail("Expected the edited drink record")
        }
        XCTAssertEqual(restored.id, updated.id)
        XCTAssertEqual(restored.drinkName, updated.drinkName)
        XCTAssertEqual(restored.consumedAt.timeIntervalSince1970, updated.consumedAt.timeIntervalSince1970, accuracy: 1)
        XCTAssertTrue(stored.needsBackup)
    }

    func testUnknownPayloadVersionIsNotDecodedAsCurrentData() throws {
        let record = try DrinkRecord(drinkName: "拿铁")
        let stored = try StoredJournalRecord(record: .drink(record))
        stored.payloadVersion = 99

        XCTAssertThrowsError(try stored.decodeRecord()) { error in
            XCTAssertEqual(error as? StoredJournalRecordError, .unsupportedPayloadVersion(99))
        }
    }

    func testLegacyMicroSweetnessIsCanonicalizedWhenReading() throws {
        let record = try DrinkRecord(drinkName: "拿铁", sweetness: "三分糖")
        let stored = try StoredJournalRecord(record: .drink(record))
        let encoded = try JournalRecordCodec.encode(.drink(record))
        let legacyPayload = String(decoding: encoded, as: UTF8.self)
            .replacingOccurrences(of: "三分糖", with: "微糖")
        stored.payload = Data(legacyPayload.utf8)

        guard case .drink(let decoded) = try stored.decodeRecord() else {
            return XCTFail("Expected the legacy drink record")
        }
        XCTAssertEqual(decoded.sweetness, "三分糖")
    }

    func testDateRangeFetchIncludesDayStartAndExcludesNextDay() throws {
        let container = try makeInMemoryContainer()
        let context = ModelContext(container)
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let start = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 11, day: 17)))
        let end = try XCTUnwrap(calendar.date(byAdding: .day, value: 1, to: start))
        let records = [
            try DrinkRecord(consumedAt: start.addingTimeInterval(-1), drinkName: "昨天"),
            try DrinkRecord(consumedAt: start, drinkName: "当天开始"),
            try DrinkRecord(consumedAt: end.addingTimeInterval(-1), drinkName: "当天结束前"),
            try DrinkRecord(consumedAt: end, drinkName: "次日开始")
        ]
        for record in records {
            context.insert(try StoredJournalRecord(record: .drink(record)))
        }
        try context.save()

        let predicate = #Predicate<StoredJournalRecord> { storedRecord in
            storedRecord.consumedAt >= start && storedRecord.consumedAt < end
        }
        let fetched = try context.fetch(FetchDescriptor<StoredJournalRecord>(
            predicate: predicate,
            sortBy: [SortDescriptor(\.consumedAt), SortDescriptor(\.recordID)]
        ))

        XCTAssertEqual(fetched.map(\.recordID), [records[1].id.uuidString, records[2].id.uuidString])
    }

    func testDeletingOneRecordLeavesOtherRecordsUntouched() throws {
        let container = try makeInMemoryContainer()
        let context = ModelContext(container)
        let drink = try DrinkRecord(drinkName: "拿铁")
        let meal = try MealRecord(dishes: [try MealDish(name: "米饭")])
        let storedDrink = try StoredJournalRecord(record: .drink(drink))
        context.insert(storedDrink)
        context.insert(try StoredJournalRecord(record: .meal(meal)))
        try context.save()

        context.delete(storedDrink)
        try context.save()

        let remaining = try context.fetch(FetchDescriptor<StoredJournalRecord>())
        XCTAssertEqual(remaining.count, 1)
        XCTAssertEqual(try remaining.first?.decodeRecord().id, meal.id)
    }

    func testPersistentRecordCanBeReadAfterReopeningContainer() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("GanfanSwiftDataTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let storeURL = directory.appendingPathComponent("Library.store")
        let record = try DrinkRecord(drinkName: "冰鲜柠檬水")

        do {
            let container = try ModelContainer(
                for: StoredJournalRecord.self,
                configurations: ModelConfiguration(url: storeURL)
            )
            let context = ModelContext(container)
            context.insert(try StoredJournalRecord(record: .drink(record)))
            try context.save()
        }

        do {
            let container = try ModelContainer(
                for: StoredJournalRecord.self,
                configurations: ModelConfiguration(url: storeURL)
            )
            let context = ModelContext(container)
            let stored = try XCTUnwrap(context.fetch(FetchDescriptor<StoredJournalRecord>()).first)
            let reopened = try stored.decodeRecord()
            guard case .drink(let reopenedDrink) = reopened else {
                return XCTFail("Expected a persisted drink")
            }
            XCTAssertEqual(reopenedDrink.id, record.id)
            XCTAssertEqual(reopenedDrink.drinkName, record.drinkName)
        }
    }

    private func makeInMemoryContainer() throws -> ModelContainer {
        try ModelContainer(
            for: StoredJournalRecord.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
    }
}
