import Foundation

// Every enum on this file persists as part of `UserProfile` (Keychain via
// `UserProfileStore`), all as `Optional` fields on that struct -- but a
// synthesized `Decodable` enum still throws on an unrecognized raw value
// rather than decoding to `nil`, and one field throwing fails the WHOLE
// `UserProfile` decode (`KeychainStore`'s `try?` then silently resets the
// entire onboarding profile, not just that one field). No case has ever
// been removed/renamed yet, so this is safe today -- but the next time one
// is, every case below needs either a custom `init(from:)` with a fallback
// (`nil`/a default case) or to stay additive-only (new cases fine, no
// removals/renames) to avoid repeating the `AuthUser` incident
// (AuthModels.swift) for this data.
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
    /// Multi-select as of 2026-09 (a tester expected to pick more than
    /// one) -- was a single `Profession?` before. The old singular
    /// `profession` key is still what's on disk for anyone who onboarded
    /// earlier, so the custom decoder below migrates it into a one-element
    /// array instead of silently dropping it.
    var professions: [Profession] = []
    /// Free text, only meaningful when `professions` contains `.other` —
    /// picking "Other" used to be a dead end: `professionText` below
    /// dropped it entirely rather than sending the literal word "other" to
    /// the AI, so anyone outside the ten preset options got zero
    /// personalization at all. This is what they actually typed instead.
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

    // A custom `init(from:)` below suppresses Swift's free synthesized
    // memberwise init, so it's rebuilt explicitly here (tests and any
    // other convenience-construction call site relied on it).
    init(
        name: String = "",
        professions: [Profession] = [],
        professionOther: String = "",
        interests: [Interest] = [],
        customInterests: [String] = [],
        faith: Faith? = nil,
        budget: Budget? = nil,
        groupType: GroupType? = nil,
        pace: Pace? = nil,
        occasion: Occasion? = nil,
        onboardingCompleted: Bool = false
    ) {
        self.name = name
        self.professions = professions
        self.professionOther = professionOther
        self.interests = interests
        self.customInterests = customInterests
        self.faith = faith
        self.budget = budget
        self.groupType = groupType
        self.pace = pace
        self.occasion = occasion
        self.onboardingCompleted = onboardingCompleted
    }

    private enum CodingKeys: String, CodingKey {
        case name, professions, profession, professionOther, interests, customInterests, faith, budget, groupType, pace, occasion, onboardingCompleted
    }

    /// Custom decoder -- see this file's own top-of-file warning: a
    /// synthesized decoder throws on ANY missing key, and `KeychainStore`'s
    /// `try?` turns that into a silent full-profile reset for every
    /// existing user the moment a field is added the "normal" way
    /// (confirmed: `JSONDecoder` throws `keyNotFound`, it does not fall
    /// back to a stored property's default). Every field here falls back
    /// to its default instead, and the old singular `profession` migrates
    /// into `professions` rather than being dropped.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? ""
        if let multi = try c.decodeIfPresent([Profession].self, forKey: .professions) {
            professions = multi
        } else if let single = try c.decodeIfPresent(Profession.self, forKey: .profession) {
            professions = [single]
        } else {
            professions = []
        }
        professionOther = try c.decodeIfPresent(String.self, forKey: .professionOther) ?? ""
        interests = try c.decodeIfPresent([Interest].self, forKey: .interests) ?? []
        customInterests = try c.decodeIfPresent([String].self, forKey: .customInterests) ?? []
        faith = try c.decodeIfPresent(Faith.self, forKey: .faith)
        budget = try c.decodeIfPresent(Budget.self, forKey: .budget)
        groupType = try c.decodeIfPresent(GroupType.self, forKey: .groupType)
        pace = try c.decodeIfPresent(Pace.self, forKey: .pace)
        occasion = try c.decodeIfPresent(Occasion.self, forKey: .occasion)
        onboardingCompleted = try c.decodeIfPresent(Bool.self, forKey: .onboardingCompleted) ?? false
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(name, forKey: .name)
        try c.encode(professions, forKey: .professions)
        try c.encode(professionOther, forKey: .professionOther)
        try c.encode(interests, forKey: .interests)
        try c.encode(customInterests, forKey: .customInterests)
        try c.encodeIfPresent(faith, forKey: .faith)
        try c.encodeIfPresent(budget, forKey: .budget)
        try c.encodeIfPresent(groupType, forKey: .groupType)
        try c.encodeIfPresent(pace, forKey: .pace)
        try c.encodeIfPresent(occasion, forKey: .occasion)
        try c.encode(onboardingCompleted, forKey: .onboardingCompleted)
    }

    /// What actually reaches the AI prompt for profession — every selected
    /// preset's raw value, comma-joined, plus the user's own typed text
    /// when "Other" is among the selections (and nothing for "Other" if
    /// they never typed anything, same as not picking it). Truncated to
    /// 60 chars to match `user-context.ts`'s schema limit on the backend.
    var professionText: String? {
        var parts = professions.filter { $0 != .other }.map(\.rawValue)
        if professions.contains(.other) {
            let trimmed = professionOther.trimmingCharacters(in: .whitespaces)
            if !trimmed.isEmpty { parts.append(trimmed) }
        }
        guard !parts.isEmpty else { return nil }
        return String(parts.joined(separator: ", ").prefix(60))
    }

    /// Preset interests plus whatever custom ones were typed in, merged
    /// into the one flat list of strings the AI prompt actually wants.
    var interestsText: [String] {
        interests.map(\.rawValue) + customInterests
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }
}
