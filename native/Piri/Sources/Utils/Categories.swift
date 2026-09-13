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
