import Foundation

/// Port of `mobile/src/constants/profile-options.ts`.
struct ProfileOption<Value: Hashable> {
    let value: Value
    let labelKey: String
    let icon: String?
}

enum ProfileOptions {
    static let professions: [ProfileOption<Profession>] = [
        .init(value: .architect, labelKey: "profileOptions.professions.architect", icon: "building.columns.fill"),
        .init(value: .historian, labelKey: "profileOptions.professions.historian", icon: "scroll.fill"),
        .init(value: .photographer, labelKey: "profileOptions.professions.photographer", icon: "camera.fill"),
        .init(value: .artist, labelKey: "profileOptions.professions.artist", icon: "paintpalette.fill"),
        .init(value: .engineer, labelKey: "profileOptions.professions.engineer", icon: "gearshape.fill"),
        .init(value: .doctor, labelKey: "profileOptions.professions.doctor", icon: "stethoscope"),
        .init(value: .foodie, labelKey: "profileOptions.professions.foodie", icon: "fork.knife"),
        .init(value: .student, labelKey: "profileOptions.professions.student", icon: "graduationcap.fill"),
        .init(value: .writer, labelKey: "profileOptions.professions.writer", icon: "pencil"),
        .init(value: .other, labelKey: "profileOptions.professions.other", icon: "ellipsis.circle.fill"),
    ]

    static let interests: [ProfileOption<Interest>] = [
        .init(value: .history, labelKey: "profileOptions.interests.history", icon: "hourglass"),
        .init(value: .architecture, labelKey: "profileOptions.interests.architecture", icon: "building.columns.fill"),
        .init(value: .art, labelKey: "profileOptions.interests.art", icon: "photo.artframe"),
        .init(value: .religion, labelKey: "profileOptions.interests.religion", icon: "hands.sparkles.fill"),
        .init(value: .food, labelKey: "profileOptions.interests.food", icon: "fork.knife"),
        .init(value: .nature, labelKey: "profileOptions.interests.nature", icon: "leaf.fill"),
        .init(value: .nightlife, labelKey: "profileOptions.interests.nightlife", icon: "moon.stars.fill"),
        .init(value: .music, labelKey: "profileOptions.interests.music", icon: "music.note"),
        .init(value: .photography, labelKey: "profileOptions.interests.photography", icon: "camera.aperture"),
        .init(value: .sports, labelKey: "profileOptions.interests.sports", icon: "figure.run"),
    ]

    static let faiths: [ProfileOption<Faith>] = [
        .init(value: .muslim, labelKey: "profileOptions.faiths.muslim", icon: nil),
        .init(value: .christian, labelKey: "profileOptions.faiths.christian", icon: nil),
        .init(value: .jewish, labelKey: "profileOptions.faiths.jewish", icon: nil),
        .init(value: .buddhist, labelKey: "profileOptions.faiths.buddhist", icon: nil),
        .init(value: .hindu, labelKey: "profileOptions.faiths.hindu", icon: nil),
        .init(value: .secular, labelKey: "profileOptions.faiths.secular", icon: nil),
        .init(value: .preferNotToSay, labelKey: "profileOptions.faiths.preferNotToSay", icon: nil),
    ]

    static let budgets: [ProfileOption<Budget>] = [
        .init(value: .budget, labelKey: "profileOptions.budgets.budget", icon: "banknote.fill"),
        .init(value: .moderate, labelKey: "profileOptions.budgets.moderate", icon: "creditcard.fill"),
        .init(value: .luxury, labelKey: "profileOptions.budgets.luxury", icon: "diamond.fill"),
    ]

    static let groupTypes: [ProfileOption<GroupType>] = [
        .init(value: .solo, labelKey: "profileOptions.groupTypes.solo", icon: "person.fill"),
        .init(value: .couple, labelKey: "profileOptions.groupTypes.couple", icon: "person.2.fill"),
        .init(value: .family, labelKey: "profileOptions.groupTypes.family", icon: "person.3.fill"),
        .init(value: .friends, labelKey: "profileOptions.groupTypes.friends", icon: "figure.2.arms.open"),
    ]

    static let paces: [ProfileOption<Pace>] = [
        .init(value: .relaxed, labelKey: "profileOptions.paces.relaxed", icon: "tortoise.fill"),
        .init(value: .balanced, labelKey: "profileOptions.paces.balanced", icon: "scalemass.fill"),
        .init(value: .packed, labelKey: "profileOptions.paces.packed", icon: "bolt.fill"),
    ]
}
