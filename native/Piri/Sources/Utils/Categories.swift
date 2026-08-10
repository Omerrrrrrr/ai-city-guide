import Foundation

/// Port of `mobile/src/utils/categories.ts`.
enum Categories {
    static let icon: [String: String] = [
        "museum": "building.columns.fill",
        "landmark": "mappin.and.ellipse",
        "cultural-spot": "theatermasks.fill",
        "beach": "beach.umbrella.fill",
        "walking-area": "figure.walk",
        "cafe": "cup.and.saucer.fill",
        "restaurant": "fork.knife",
        "viewpoint": "sun.horizon.fill",
        "nature": "leaf.fill",
        "shopping-area": "bag.fill",
        "lodging": "bed.double.fill",
        "square-street": "building.2.fill",
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

    static func icon(for category: String) -> String {
        icon[category] ?? "mappin.circle.fill"
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
    let icon: String?
    let labelKey: String
}

enum CategoryFilters {
    static let all: [CategoryFilter] = [
        CategoryFilter(id: "all", icon: nil, labelKey: "categoryFilters.all"),
        CategoryFilter(id: "museum", icon: "building.columns.fill", labelKey: "categoryFilters.museums"),
        CategoryFilter(id: "landmark", icon: "mappin.and.ellipse", labelKey: "categoryFilters.landmarks"),
        CategoryFilter(id: "cultural-spot", icon: "theatermasks.fill", labelKey: "categoryFilters.culture"),
        CategoryFilter(id: "walking-area", icon: "figure.walk", labelKey: "categoryFilters.walks"),
        CategoryFilter(id: "beach", icon: "beach.umbrella.fill", labelKey: "categoryFilters.beaches"),
        CategoryFilter(id: "cafe", icon: "cup.and.saucer.fill", labelKey: "categoryFilters.cafes"),
        CategoryFilter(id: "restaurant", icon: "fork.knife", labelKey: "categoryFilters.food"),
        CategoryFilter(id: "viewpoint", icon: "sun.horizon.fill", labelKey: "categoryFilters.views"),
        CategoryFilter(id: "nature", icon: "leaf.fill", labelKey: "categoryFilters.nature"),
        CategoryFilter(id: "shopping-area", icon: "bag.fill", labelKey: "categoryFilters.shopping"),
    ]
}
