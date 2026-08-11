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

/// Port of `buildProfileContext` in `mobile/src/store/user-profile.ts` —
/// turns the local profile into free text the AI prompt is conditioned on.
func buildProfileContext(_ profile: UserProfile) -> String {
    var parts: [String] = []

    if !profile.name.isEmpty {
        parts.append("The user's name is \(profile.name).")
    }
    if let profession = profile.professionText {
        parts.append("They work as a \(profession).")
    }
    let interestsText = profile.interestsText
    if !interestsText.isEmpty {
        parts.append("Their interests include: \(interestsText.joined(separator: ", ")).")
    }
    if let faith = profile.faith, faith != .preferNotToSay {
        if faith == .secular {
            parts.append("They have a secular/non-religious worldview.")
        } else {
            parts.append("They identify as \(faith.rawValue).")
        }
    }

    guard !parts.isEmpty else { return "" }

    return "About this user:\n" + parts.joined(separator: " ")
        + "\n\nTailor your response to their perspective. An architect should hear about structural and design details. A historian should hear about historical context and timeline. A Muslim visiting a mosque should hear about religious significance. A photographer should hear about light, composition, and visual opportunities. And so on."
}
