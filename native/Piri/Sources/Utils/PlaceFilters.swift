import Foundation

/// Port of `mobile/src/utils/place-filters.ts`.
enum PlaceFilters {
    static let curatedTags = [
        "rainy day", "short stop", "family", "budget", "local favorite",
        "waterfront", "photogenic", "date night", "coffee break", "meal",
    ]

    private static let tagLabelKeys: [String: String] = [
        "rainy day": "tags.rainyDay",
        "short stop": "tags.shortStop",
        "family": "tags.family",
        "budget": "tags.budget",
        "local favorite": "tags.localFavorite",
        "waterfront": "tags.waterfront",
        "photogenic": "tags.photogenic",
        "date night": "tags.dateNight",
        "coffee break": "tags.coffeeBreak",
        "meal": "tags.meal",
    ]

    static func formatTag(_ tag: String) -> String {
        guard let key = tagLabelKeys[tag] else {
            return tag.split(separator: " ").map { $0.prefix(1).uppercased() + $0.dropFirst() }.joined(separator: " ")
        }
        return String(localized: String.LocalizationValue(key))
    }

    static func curatedTags(in places: [Place]) -> [String] {
        let present = Set(places.flatMap(\.tags))
        return curatedTags.filter { present.contains($0) }
    }

    private static func openPriority(_ place: Place) -> Int {
        switch PlaceHours.openStatus(for: place).state {
        case .allDay: return 4
        case .open: return 3
        case .closed: return 2
        case .unknown: return 1
        case .temporarilyClosed: return 0
        }
    }

    private static func verifiedPriority(_ place: Place) -> Int {
        var score = PlaceHours.openStatus(for: place).verified ? 2 : 0
        if place.image.verified { score += 1 }
        return score
    }

    static func qualityScore(_ place: Place) -> Int {
        var score = 0
        switch place.importanceTier {
        case .hero: score += 30
        case .supporting: score += 18
        case .longTail: score += 6
        }
        if place.image.verified { score += 6 }
        if place.visitInfo.hoursVerified { score += 4 }
        if let confidence = place.wiki?.confidence {
            score += min(14, Int(confidence / 10))
        }
        if place.wiki?.status == .matched { score += 3 }
        if place.tags.contains("local favorite") { score += 2 }
        if place.tags.contains("photogenic") { score += 1 }
        return score
    }

    static func isHighQuality(_ place: Place) -> Bool {
        qualityScore(place) >= 24
    }

    private static func importanceScore(_ tier: PlaceImportanceTier) -> Int {
        switch tier {
        case .hero: return 3
        case .supporting: return 2
        case .longTail: return 1
        }
    }

    static func sortedForBrowse(_ places: [Place]) -> [Place] {
        places.sorted { a, b in
            let openDiff = openPriority(b) - openPriority(a)
            if openDiff != 0 { return openDiff < 0 }
            let verifiedDiff = verifiedPriority(b) - verifiedPriority(a)
            if verifiedDiff != 0 { return verifiedDiff < 0 }
            let qualityDiff = qualityScore(b) - qualityScore(a)
            if qualityDiff != 0 { return qualityDiff < 0 }
            let importanceDiff = importanceScore(b.importanceTier) - importanceScore(a.importanceTier)
            if importanceDiff != 0 { return importanceDiff < 0 }
            return a.name.localizedCompare(b.name) == .orderedAscending
        }
    }

    private static func profileBoost(_ place: Place, profile: UserProfile) -> Int {
        var score = 0
        let tags = place.tags
        let category = place.category
        let interests = Set(profile.interests.map(\.rawValue))

        func interested(_ interest: String) -> Bool { interests.contains(interest) }

        if profile.profession == .architect || interested("architecture") {
            if tags.contains("architecture") || category == "landmark" || category == "museum" { score += 6 }
        }
        if profile.profession == .historian || interested("history") {
            if category == "museum" || category == "cultural-spot" || category == "landmark" || tags.contains("history") { score += 6 }
        }
        if profile.profession == .photographer || interested("photography") {
            if tags.contains("photogenic") || category == "viewpoint" { score += 6 }
        }
        if profile.profession == .foodie || interested("food") {
            if category == "cafe" || category == "restaurant" || tags.contains("meal") || tags.contains("coffee break") { score += 6 }
        }
        if profile.profession == .artist || interested("art") {
            if tags.contains("art") || category == "museum" || category == "cultural-spot" { score += 5 }
        }
        if interested("nature") {
            if category == "beach" || category == "nature" || category == "walking-area" { score += 5 }
        }
        if interested("nightlife") {
            if tags.contains("nightlife") || tags.contains("date night") { score += 5 }
        }
        if interested("religion") {
            if tags.contains("religion") || category == "cultural-spot" { score += 4 }
        }
        if let faith = profile.faith, faith != .secular, faith != .preferNotToSay {
            if tags.contains("religion") || category == "cultural-spot" { score += 3 }
        }
        if profile.budget == .budget, tags.contains("budget") { score += 5 }
        if profile.groupType == .family, tags.contains("family") { score += 6 }
        if profile.groupType == .couple, tags.contains("date night") { score += 5 }

        let duration = place.visitInfo.durationMinutes
        if profile.pace == .packed, tags.contains("short stop") || (duration.map { $0 <= 45 } ?? false) { score += 4 }
        if profile.pace == .relaxed, let duration, duration >= 90 { score += 4 }

        return score
    }

    private static func historyBoost(_ place: Place, viewed: [Place]) -> Int {
        var score = 0
        for other in viewed where other.id != place.id {
            if other.category == place.category { score += 2 }
            for tag in other.tags where place.tags.contains(tag) { score += 1 }
        }
        return min(score, 8)
    }

    static func sortedForProfile(_ places: [Place], profile: UserProfile, viewed: [Place] = []) -> [Place] {
        let hasProfile = profile.profession != nil || !profile.interests.isEmpty || profile.faith != nil
            || profile.budget != nil || profile.groupType != nil || profile.pace != nil
        guard hasProfile || !viewed.isEmpty else { return sortedForBrowse(places) }

        func totalBoost(_ place: Place) -> Int { profileBoost(place, profile: profile) + historyBoost(place, viewed: viewed) }

        return places.sorted { a, b in
            let boostDiff = totalBoost(b) - totalBoost(a)
            if boostDiff != 0 { return boostDiff < 0 }
            let openDiff = openPriority(b) - openPriority(a)
            if openDiff != 0 { return openDiff < 0 }
            return qualityScore(b) - qualityScore(a) < 0
        }
    }

    struct QueryFilters {
        var query: String = ""
        var category: String = "all"
        var tag: String = "all"
        var openNow: Bool = false
    }

    static func filter(_ places: [Place], with filters: QueryFilters) -> [Place] {
        let q = filters.query.trimmingCharacters(in: .whitespaces).lowercased()
        return places.filter { place in
            if filters.category != "all", place.category != filters.category { return false }
            if filters.tag != "all", !place.tags.contains(filters.tag) { return false }
            if filters.openNow, !PlaceHours.isOpen(PlaceHours.openStatus(for: place)) { return false }
            guard !q.isEmpty else { return true }
            return place.name.lowercased().contains(q)
                || place.description.lowercased().contains(q)
                || place.tags.contains { $0.lowercased().contains(q) }
        }
    }
}
