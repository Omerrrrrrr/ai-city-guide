import Foundation

/// Port of `mobile/src/utils/categories.ts`.
enum Categories {
    static let emoji: [String: String] = [
        "museum": "🏛️",
        "landmark": "🗿",
        "cultural-spot": "🎭",
        "beach": "🏖️",
        "walking-area": "🚶",
        "cafe": "☕",
        "restaurant": "🍽️",
        "viewpoint": "🌅",
        "nature": "🌿",
        "shopping-area": "🛍️",
        "lodging": "🏨",
        "square-street": "🏙️",
    ]

    private static let labelKeys: [String: String] = [
        "landmark": "categories.landmark",
        "museum": "categories.museum",
        "cultural-spot": "categories.culturalSpot",
        "square-street": "categories.squareStreet",
        "beach": "categories.beach",
        "walking-area": "categories.walkingArea",
        "cafe": "categories.cafe",
        "restaurant": "categories.restaurant",
        "viewpoint": "categories.viewpoint",
        "shopping-area": "categories.shoppingArea",
        "lodging": "categories.lodging",
        "nature": "categories.nature",
    ]

    static func emoji(for category: String) -> String {
        emoji[category] ?? "📍"
    }

    static func label(for category: String) -> String {
        guard let key = labelKeys[category] else {
            return category.split(separator: "-").map { $0.prefix(1).uppercased() + $0.dropFirst() }.joined(separator: " ")
        }
        return String(localized: String.LocalizationValue(key))
    }
}

/// Port of `mobile/src/constants/category-filters.ts`.
struct CategoryFilter {
    let id: String
    let emoji: String?
    let labelKey: String
}

enum CategoryFilters {
    static let all: [CategoryFilter] = [
        CategoryFilter(id: "all", emoji: nil, labelKey: "categoryFilters.all"),
        CategoryFilter(id: "museum", emoji: "🏛️", labelKey: "categoryFilters.museums"),
        CategoryFilter(id: "landmark", emoji: "🗿", labelKey: "categoryFilters.landmarks"),
        CategoryFilter(id: "cultural-spot", emoji: "🎭", labelKey: "categoryFilters.culture"),
        CategoryFilter(id: "walking-area", emoji: "🚶", labelKey: "categoryFilters.walks"),
        CategoryFilter(id: "beach", emoji: "🏖️", labelKey: "categoryFilters.beaches"),
        CategoryFilter(id: "cafe", emoji: "☕", labelKey: "categoryFilters.cafes"),
        CategoryFilter(id: "restaurant", emoji: "🍽️", labelKey: "categoryFilters.food"),
        CategoryFilter(id: "viewpoint", emoji: "🌅", labelKey: "categoryFilters.views"),
        CategoryFilter(id: "nature", emoji: "🌿", labelKey: "categoryFilters.nature"),
        CategoryFilter(id: "shopping-area", emoji: "🛍️", labelKey: "categoryFilters.shopping"),
    ]
}
