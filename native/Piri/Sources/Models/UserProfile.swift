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
    var interests: [Interest] = []
    var faith: Faith?
    var budget: Budget?
    var groupType: GroupType?
    var pace: Pace?
    var onboardingCompleted: Bool = false
}

/// Port of `buildProfileContext` in `mobile/src/store/user-profile.ts` —
/// turns the local profile into free text the AI prompt is conditioned on.
func buildProfileContext(_ profile: UserProfile) -> String {
    var parts: [String] = []

    if !profile.name.isEmpty {
        parts.append("The user's name is \(profile.name).")
    }
    if let profession = profile.profession, profession != .other {
        parts.append("They work as a \(profession.rawValue).")
    }
    if !profile.interests.isEmpty {
        let interests = profile.interests.map(\.rawValue).joined(separator: ", ")
        parts.append("Their interests include: \(interests).")
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
