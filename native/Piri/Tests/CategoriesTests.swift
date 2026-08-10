import XCTest
@testable import Piri

/// Port of `mobile/src/utils/__tests__/categories.test.ts`.
final class CategoriesTests: XCTestCase {
    func testIconForKnownCategory() {
        XCTAssertEqual(Categories.icon(for: "museum"), "building.columns.fill")
        XCTAssertEqual(Categories.icon(for: "nature"), "leaf.fill")
    }

    func testIconFallsBackToPinForUnknownCategory() {
        XCTAssertEqual(Categories.icon(for: "not-a-real-category"), "mappin.circle.fill")
    }

    func testLabelResolvesKnownCategoryThroughCatalog() {
        // Unlike the RN test (which injects a `fakeT` returning the raw
        // key), `Categories.label` always resolves through the real
        // .xcstrings catalog in whatever language the device/simulator is
        // currently running — so this checks that the lookup actually
        // succeeded (didn't silently fall through to the raw key, which is
        // Foundation's fallback for an unresolved lookup) rather than
        // asserting a specific language's exact translated text.
        let label = Categories.label(for: "cultural-spot")
        XCTAssertFalse(label.isEmpty)
        XCTAssertNotEqual(label, "categories.culturalSpot")
    }

    func testLabelTitleCasesUnknownCategoryInsteadOfTranslating() {
        XCTAssertEqual(Categories.label(for: "some-unknown-thing"), "Some Unknown Thing")
    }
}
