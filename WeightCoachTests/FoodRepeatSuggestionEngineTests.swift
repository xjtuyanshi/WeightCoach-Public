import XCTest
@testable import WeightCoach

final class FoodRepeatSuggestionEngineTests: XCTestCase {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }

    private var referenceDate: Date {
        date(year: 2026, month: 7, day: 28, hour: 12)
    }

    func testDifferentDaysPromoteFoodToFrequentAndKeepLatestTemplate() throws {
        let snapshots = [
            snapshot(index: 4, key: "protein-milk", daysAgo: 4, hour: 8),
            snapshot(index: 2, key: "protein-milk", daysAgo: 1, hour: 8),
            snapshot(index: 0, key: "protein-milk", daysAgo: 0, hour: 9),
        ]

        let result = FoodRepeatSuggestionEngine.makeSuggestions(
            snapshots: snapshots,
            referenceDate: referenceDate,
            calendar: calendar
        )

        let suggestion = try XCTUnwrap(result.frequent.first)
        XCTAssertEqual(suggestion.key, "protein-milk")
        XCTAssertEqual(suggestion.sourceIndex, 0)
        XCTAssertEqual(suggestion.distinctDayCount, 3)
        XCTAssertEqual(suggestion.occurrenceCount, 3)
        XCTAssertTrue(result.recent.isEmpty)
    }

    func testRepeatedEntriesOnSameDayDoNotBecomeFrequent() throws {
        let snapshots = [
            snapshot(index: 0, key: "egg", daysAgo: 0, hour: 12),
            snapshot(index: 1, key: "egg", daysAgo: 0, hour: 8),
            snapshot(index: 2, key: "egg", daysAgo: 0, hour: 7),
        ]

        let result = FoodRepeatSuggestionEngine.makeSuggestions(
            snapshots: snapshots,
            referenceDate: referenceDate,
            calendar: calendar
        )

        XCTAssertTrue(result.frequent.isEmpty)
        let recent = try XCTUnwrap(result.recent.first)
        XCTAssertEqual(recent.distinctDayCount, 1)
        XCTAssertEqual(recent.occurrenceCount, 3)
        XCTAssertEqual(recent.sourceIndex, 0)
    }

    func testWindowIncludesDayTwentyNineAndExcludesDayThirtyAndFuture() {
        let snapshots = [
            snapshot(index: 0, key: "today", daysAgo: 0, hour: 8),
            snapshot(index: 1, key: "edge", daysAgo: 29, hour: 8),
            snapshot(index: 2, key: "too-old", daysAgo: 30, hour: 8),
            FoodRepeatSuggestionSnapshot(
                sourceIndex: 3,
                key: "future",
                date: calendar.date(
                    byAdding: .day,
                    value: 1,
                    to: referenceDate
                )!
            ),
        ]

        let result = FoodRepeatSuggestionEngine.makeSuggestions(
            snapshots: snapshots,
            referenceDate: referenceDate,
            calendar: calendar
        )
        let keys = result.all.map(\.key)

        XCTAssertEqual(Set(keys), ["today", "edge"])
    }

    func testFrequentRankingUsesDaysThenOccurrencesThenRecency() {
        let snapshots = [
            snapshot(index: 0, key: "three-days", daysAgo: 0, hour: 8),
            snapshot(index: 1, key: "three-days", daysAgo: 2, hour: 8),
            snapshot(index: 2, key: "three-days", daysAgo: 4, hour: 8),
            snapshot(index: 3, key: "two-days-more-times", daysAgo: 0, hour: 7),
            snapshot(index: 4, key: "two-days-more-times", daysAgo: 1, hour: 8),
            snapshot(index: 5, key: "two-days-more-times", daysAgo: 1, hour: 7),
            snapshot(index: 6, key: "two-days", daysAgo: 0, hour: 9),
            snapshot(index: 7, key: "two-days", daysAgo: 1, hour: 9),
        ]

        let result = FoodRepeatSuggestionEngine.makeSuggestions(
            snapshots: snapshots,
            referenceDate: referenceDate,
            calendar: calendar
        )

        XCTAssertEqual(
            result.frequent.map(\.key),
            ["three-days", "two-days-more-times", "two-days"]
        )
    }

    func testRecentFillsRemainingCapacityWithoutDuplicatingFrequent() {
        var snapshots = [
            snapshot(index: 0, key: "frequent", daysAgo: 0, hour: 8),
            snapshot(index: 1, key: "frequent", daysAgo: 1, hour: 8),
        ]
        snapshots.append(contentsOf: (0..<8).map { offset in
            snapshot(
                index: offset + 2,
                key: "recent-\(offset)",
                daysAgo: offset,
                hour: 7
            )
        })

        let result = FoodRepeatSuggestionEngine.makeSuggestions(
            snapshots: snapshots,
            referenceDate: referenceDate,
            calendar: calendar
        )

        XCTAssertEqual(result.frequent.map(\.key), ["frequent"])
        XCTAssertEqual(result.recent.count, 5)
        XCTAssertFalse(result.recent.contains { $0.key == "frequent" })
        XCTAssertEqual(result.all.count, 6)
    }

    func testIdentityPrefersProductThenBarcodeThenReferenceAndNormalizesName() {
        let productID = UUID(uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE")!

        XCTAssertEqual(
            FoodRepeatIdentity.key(
                productID: productID,
                barcode: "123",
                referenceCatalogID: "egg-hard-boiled",
                name: "Other"
            ),
            "product:aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee"
        )
        XCTAssertEqual(
            FoodRepeatIdentity.key(
                productID: nil,
                barcode: " 0 123-45 ",
                referenceCatalogID: "egg-hard-boiled",
                name: "Other"
            ),
            "barcode:012345"
        )
        XCTAssertEqual(
            FoodRepeatIdentity.key(
                productID: nil,
                barcode: nil,
                referenceCatalogID: "egg-hard-boiled",
                name: "Other"
            ),
            "reference:egg-hard-boiled"
        )
        XCTAssertEqual(
            FoodRepeatIdentity.key(
                productID: nil,
                barcode: nil,
                referenceCatalogID: nil,
                name: "  Protéin   MILK  "
            ),
            "name:protein milk"
        )
    }

    func testReferenceCatalogIdentitySurvivesAppLanguageChanges() {
        let originalName = "水煮蛋（全蛋、煮熟，不含额外用油）"
        let repeatedName = originalName
        let originalKey = FoodRepeatIdentity.key(
            productID: nil,
            barcode: nil,
            referenceCatalogID: CommonFoodCatalog.referenceID(
                forStoredName: originalName
            ),
            name: originalName
        )
        let repeatedKey = FoodRepeatIdentity.key(
            productID: nil,
            barcode: nil,
            referenceCatalogID: CommonFoodCatalog.referenceID(
                forStoredName: repeatedName
            ),
            name: repeatedName
        )

        XCTAssertEqual(originalKey, "reference:egg-hard-boiled")
        XCTAssertEqual(repeatedKey, originalKey)
        XCTAssertEqual(
            CommonFoodCatalog.referenceID(
                forStoredName: "Hard-Boiled Egg (Whole egg, boiled; no added oil)"
            ),
            "egg-hard-boiled"
        )
    }

    private func snapshot(
        index: Int,
        key: String,
        daysAgo: Int,
        hour: Int
    ) -> FoodRepeatSuggestionSnapshot {
        FoodRepeatSuggestionSnapshot(
            sourceIndex: index,
            key: key,
            date: calendar.date(
                byAdding: .day,
                value: -daysAgo,
                to: date(
                    year: 2026,
                    month: 7,
                    day: 28,
                    hour: hour
                )
            )!
        )
    }

    private func date(
        year: Int,
        month: Int,
        day: Int,
        hour: Int
    ) -> Date {
        calendar.date(
            from: DateComponents(
                year: year,
                month: month,
                day: day,
                hour: hour
            )
        )!
    }
}
