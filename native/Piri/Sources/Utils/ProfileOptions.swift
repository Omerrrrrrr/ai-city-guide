import Foundation

/// Port of `mobile/src/constants/profile-options.ts`.
struct ProfileOption<Value: Hashable> {
    let value: Value
    let labelKey: String
    let emoji: String?
}

enum ProfileOptions {
    static let professions: [ProfileOption<Profession>] = [
        .init(value: .architect, labelKey: "profileOptions.professions.architect", emoji: "🏛️"),
        .init(value: .historian, labelKey: "profileOptions.professions.historian", emoji: "📜"),
        .init(value: .photographer, labelKey: "profileOptions.professions.photographer", emoji: "📷"),
        .init(value: .artist, labelKey: "profileOptions.professions.artist", emoji: "🎨"),
        .init(value: .engineer, labelKey: "profileOptions.professions.engineer", emoji: "⚙️"),
        .init(value: .doctor, labelKey: "profileOptions.professions.doctor", emoji: "🩺"),
        .init(value: .foodie, labelKey: "profileOptions.professions.foodie", emoji: "🍽️"),
        .init(value: .student, labelKey: "profileOptions.professions.student", emoji: "📚"),
        .init(value: .writer, labelKey: "profileOptions.professions.writer", emoji: "✍️"),
        .init(value: .other, labelKey: "profileOptions.professions.other", emoji: "✦"),
    ]

    static let interests: [ProfileOption<Interest>] = [
        .init(value: .history, labelKey: "profileOptions.interests.history", emoji: "⏳"),
        .init(value: .architecture, labelKey: "profileOptions.interests.architecture", emoji: "🏛️"),
        .init(value: .art, labelKey: "profileOptions.interests.art", emoji: "🖼️"),
        .init(value: .religion, labelKey: "profileOptions.interests.religion", emoji: "🕌"),
        .init(value: .food, labelKey: "profileOptions.interests.food", emoji: "🍜"),
        .init(value: .nature, labelKey: "profileOptions.interests.nature", emoji: "🌿"),
        .init(value: .nightlife, labelKey: "profileOptions.interests.nightlife", emoji: "🌙"),
        .init(value: .music, labelKey: "profileOptions.interests.music", emoji: "🎵"),
        .init(value: .photography, labelKey: "profileOptions.interests.photography", emoji: "📸"),
        .init(value: .sports, labelKey: "profileOptions.interests.sports", emoji: "⚽"),
    ]

    static let faiths: [ProfileOption<Faith>] = [
        .init(value: .muslim, labelKey: "profileOptions.faiths.muslim", emoji: nil),
        .init(value: .christian, labelKey: "profileOptions.faiths.christian", emoji: nil),
        .init(value: .jewish, labelKey: "profileOptions.faiths.jewish", emoji: nil),
        .init(value: .buddhist, labelKey: "profileOptions.faiths.buddhist", emoji: nil),
        .init(value: .hindu, labelKey: "profileOptions.faiths.hindu", emoji: nil),
        .init(value: .secular, labelKey: "profileOptions.faiths.secular", emoji: nil),
        .init(value: .preferNotToSay, labelKey: "profileOptions.faiths.preferNotToSay", emoji: nil),
    ]

    static let budgets: [ProfileOption<Budget>] = [
        .init(value: .budget, labelKey: "profileOptions.budgets.budget", emoji: "💸"),
        .init(value: .moderate, labelKey: "profileOptions.budgets.moderate", emoji: "💳"),
        .init(value: .luxury, labelKey: "profileOptions.budgets.luxury", emoji: "💎"),
    ]

    static let groupTypes: [ProfileOption<GroupType>] = [
        .init(value: .solo, labelKey: "profileOptions.groupTypes.solo", emoji: "🧍"),
        .init(value: .couple, labelKey: "profileOptions.groupTypes.couple", emoji: "💑"),
        .init(value: .family, labelKey: "profileOptions.groupTypes.family", emoji: "👨‍👩‍👧"),
        .init(value: .friends, labelKey: "profileOptions.groupTypes.friends", emoji: "👯"),
    ]

    static let paces: [ProfileOption<Pace>] = [
        .init(value: .relaxed, labelKey: "profileOptions.paces.relaxed", emoji: "🐢"),
        .init(value: .balanced, labelKey: "profileOptions.paces.balanced", emoji: "⚖️"),
        .init(value: .packed, labelKey: "profileOptions.paces.packed", emoji: "⚡"),
    ]
}
