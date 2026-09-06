import Foundation

enum Profession: String, Codable, CaseIterable {
    case architect, historian, photographer, artist, engineer, doctor, foodie, student, writer, other
}

enum Interest: String, Codable, CaseIterable {
    case history, architecture, art, religion, food, nature, nightlife, music, photography, sports
}

enum Faith: String, Codable, CaseIterable {
    case muslim, christian, jewish, buddhist, hindu, secular
    case preferNotToSay = "prefer_not_to_say"
}

enum Budget: String, Codable, CaseIterable {
    case budget, moderate, luxury
}

enum GroupType: String, Codable, CaseIterable {
    case solo, couple, family, friends
}

enum Pace: String, Codable, CaseIterable {
    case relaxed, balanced, packed
}

/// The reason for THIS trip specifically -- unlike every other field on
/// `UserProfile`, this isn't a stable personal trait, it's a temporary
/// status the user is expected to set before a specific trip and clear
/// afterward (same "edit anytime" affordance as the rest of the profile,
/// just meant to be revisited more often). Confirmed via research: trip
/// purpose/occasion is a real, evidenced personalization dimension
/// distinct from `groupType` -- a "couple" trip reads very differently to
/// the AI depending on whether it's a honeymoon or a routine weekend, and
/// `groupType` alone can't distinguish those. `nil` means "no special
/// occasion" (the common case), deliberately not an explicit case of its
/// own so the chip grid can toggle a selection off by tapping it again.
enum Occasion: String, Codable, CaseIterable {
    case honeymoon, anniversary, business, celebration
}

struct UserProfile: Codable, Equatable {
    var name: String = ""
    var profession: Profession?
    /// Free text, only meaningful when `profession == .other` — picking
    /// "Other" used to be a dead end: `professionText` below dropped it
    /// entirely rather than sending the literal word "other" to the AI, so
    /// anyone outside the ten preset options got zero personalization at
    /// all. This is what they actually typed instead.
    var professionOther: String = ""
    var interests: [Interest] = []
    /// Free-text interests beyond the ten presets — same idea as
    /// `professionOther`, but for a multi-select field: presets stay a
    /// single fast tap, this covers whatever isn't one of them.
    var customInterests: [String] = []
    var faith: Faith?
    var budget: Budget?
    var groupType: GroupType?
    var pace: Pace?
    var occasion: Occasion?
    var onboardingCompleted: Bool = false

    /// What actually reaches the AI prompt for profession — the preset's
    /// raw value normally, or the user's own typed text when they picked
    /// "Other" (and nothing at all if they picked "Other" but never typed
    /// anything, same as picking nothing).
    var professionText: String? {
        if profession == .other {
            let trimmed = professionOther.trimmingCharacters(in: .whitespaces)
            return trimmed.isEmpty ? nil : trimmed
        }
        return profession?.rawValue
    }

    /// Preset interests plus whatever custom ones were typed in, merged
    /// into the one flat list of strings the AI prompt actually wants.
    var interestsText: [String] {
        interests.map(\.rawValue) + customInterests
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }
}
