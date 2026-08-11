import SwiftUI

// Not country flags — Apple's HIG explicitly discourages flags for language
// pickers (a flag represents a country, not a language, and several
// languages have no single flag that fits), so every row uses the same
// "globe" icon and lets the label text tell them apart.
private let languageOptions: [(code: String?, icon: String, labelKey: String)] = [
    (nil, "globe", "settings.language.system"),
    ("en", "globe", "settings.language.en"),
    ("tr", "globe", "settings.language.tr"),
    ("nb", "globe", "settings.language.nb"),
]

/// Groups the same way `OnboardingScreen`'s wizard steps already do:
/// interests+faith together, pace+budget+group ("who are you traveling
/// with") together under "Preferences" — mirrored here as tabs instead of
/// one long scroll of stacked cards. Named "Preferences," not "Plan" —
/// this tab holds travel-style settings, not a saved itinerary, and
/// sharing the word with `SavedCollectionKind.plan`'s actual saved plans
/// (shown a few cards below as the "Planlar" stat) read as the same
/// feature when it very much isn't.
private enum ProfileTab: Hashable, Identifiable {
    case language, profession, interests, plan
    var id: Self { self }
}

/// Port of `mobile/app/(tabs)/settings.tsx`.
struct ProfileScreen: View {
    @Environment(UserProfileStore.self) private var userProfileStore
    @Environment(CityStore.self) private var cityStore
    @Environment(LanguageStore.self) private var languageStore
    @Environment(SavedPlacesStore.self) private var savedPlacesStore
    @Environment(RecentlyViewedStore.self) private var recentlyViewedStore
    @Environment(TripsStore.self) private var tripsStore
    @Environment(PlacesQuery.self) private var placesQuery

    @State private var isEditingName = false
    @State private var nameInput = ""
    @State private var showingCityPicker = false
    @State private var showingSaved: SavedTab?
    @State private var showingRestartHint = false
    @State private var profileTab: ProfileTab = .language

    private var profile: UserProfile { userProfileStore.profile }
    private var displayName: String {
        let trimmed = profile.name.trimmingCharacters(in: .whitespaces)
        return trimmed.isEmpty ? String(localized: "settings.travelerFallback") : trimmed
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                header
                profileTabsSegment
                profileTabContent
                cityCard
                savedDataCard
                tripsCard

                Text(L("settings.version", (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String) ?? "1.0.0"))
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary.opacity(0.7))
                    .frame(maxWidth: .infinity)

                #if DEBUG
                card(titleKey: "settings.adminDevOnly") {
                    VStack(spacing: 10) {
                        NavigationLink(destination: AdminHoursScreen()) {
                            Text("settings.hoursReview")
                                .font(.system(size: 15, weight: .semibold))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 14)
                                .background(RoundedRectangle(cornerRadius: 14).fill(Theme.navy.opacity(0.04)))
                                .overlay(RoundedRectangle(cornerRadius: 14).stroke(Theme.navy.opacity(0.14)))
                        }
                        .buttonStyle(.plain)
                        NavigationLink(destination: AdminImagesScreen()) {
                            Text("settings.imageReview")
                                .font(.system(size: 15, weight: .semibold))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 14)
                                .background(RoundedRectangle(cornerRadius: 14).fill(Theme.navy.opacity(0.04)))
                                .overlay(RoundedRectangle(cornerRadius: 14).stroke(Theme.navy.opacity(0.14)))
                        }
                        .buttonStyle(.plain)
                    }
                }
                #endif
            }
            .padding(20)
        }
        .sheet(isPresented: $showingCityPicker) { CityPickerScreen() }
        .sheet(item: $showingSaved) { tab in SavedScreen(initialTab: tab) }
        .navigationBarHidden(true)
    }

    private var header: some View {
        HStack(spacing: 14) {
            ZStack {
                Circle().fill(.white.opacity(0.15))
                Text(displayName.prefix(1).uppercased()).font(.system(size: 24, weight: .bold)).foregroundStyle(Theme.gold)
            }
            .frame(width: 52, height: 52)

            VStack(alignment: .leading, spacing: 2) {
                if isEditingName {
                    TextField(String(localized: "onboarding.name.placeholder"), text: $nameInput)
                        .font(.system(size: 20, weight: .bold))
                        .foregroundStyle(.white)
                        .onSubmit {
                            userProfileStore.update { $0.name = nameInput.trimmingCharacters(in: .whitespaces) }
                            isEditingName = false
                        }
                } else {
                    Button {
                        nameInput = profile.name
                        isEditingName = true
                    } label: {
                        HStack(spacing: 4) {
                            Text(displayName).font(.system(size: 20, weight: .bold)).foregroundStyle(.white)
                            Image(systemName: "pencil").font(.system(size: 16)).foregroundStyle(.white.opacity(0.35))
                        }
                    }
                }

                let professionLabel = profile.profession.map { profession in
                    ProfileOptions.professions.first { $0.value == profession }.map { String(localized: String.LocalizationValue($0.labelKey)) }
                } ?? nil
                let faithLabel = (profile.faith != nil && profile.faith != .preferNotToSay)
                    ? ProfileOptions.faiths.first { $0.value == profile.faith }.map { String(localized: String.LocalizationValue($0.labelKey)) }
                    : nil
                let subline = [professionLabel ?? nil, faithLabel ?? nil].compactMap { $0 }.joined(separator: " · ")
                if !subline.isEmpty {
                    Text(subline).font(.system(size: 14)).foregroundStyle(.white.opacity(0.6))
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 12)
        .padding(.bottom, 16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .piriGlassSurface()
        .padding(.horizontal, -20)
        .padding(.top, -20)
    }

    private var profileTabsSegment: some View {
        HStack(spacing: 3) {
            profileTabButton(.language, label: String(localized: "settings.tabs.language"))
            profileTabButton(.profession, label: String(localized: "settings.tabs.profession"))
            profileTabButton(.interests, label: String(localized: "settings.tabs.interests"))
            profileTabButton(.plan, label: String(localized: "settings.tabs.plan"))
        }
        .padding(3)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color(.secondarySystemBackground)))
    }

    private func profileTabButton(_ value: ProfileTab, label: String) -> some View {
        let active = profileTab == value
        return Button {
            profileTab = value
        } label: {
            Text(label)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(active ? .white : .primary.opacity(0.65))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 9)
                .background(active ? RoundedRectangle(cornerRadius: 10).fill(Theme.navy) : nil)
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var profileTabContent: some View {
        switch profileTab {
        case .language: languageCard
        case .profession: professionCard
        case .interests: interestsTabContent
        case .plan: planTabContent
        }
    }

    private var professionCard: some View {
        card(titleKey: "onboarding.profession.title") {
            ChipGrid(options: ProfileOptions.professions, isSelected: { profile.profession == $0 }) { value in
                Haptics.light()
                userProfileStore.update { $0.profession = value }
            }
        }
    }

    // Grouped the same way `OnboardingScreen.faithInterestsStep` already
    // groups them.
    @ViewBuilder
    private var interestsTabContent: some View {
        card(titleKey: "onboarding.faithInterests.interestsLabel") {
            ChipGrid(options: ProfileOptions.interests, isSelected: { profile.interests.contains($0) }) { value in
                Haptics.light()
                userProfileStore.update { profile in
                    if let index = profile.interests.firstIndex(of: value) {
                        profile.interests.remove(at: index)
                    } else {
                        profile.interests.append(value)
                    }
                }
            }
        }
        card(titleKey: "onboarding.faithInterests.faithLabel", noteKey: "settings.faithNote") {
            ChipGrid(options: ProfileOptions.faiths, isSelected: { profile.faith == $0 }) { value in
                Haptics.light()
                userProfileStore.update { $0.faith = value }
            }
        }
    }

    // Grouped the same way `OnboardingScreen.travelStyleStep` already
    // groups them — pace, budget, and "who are you traveling with" (group
    // type) all under one "Preferences" heading.
    @ViewBuilder
    private var planTabContent: some View {
        card(titleKey: "onboarding.travelStyle.paceLabel") {
            ChipGrid(options: ProfileOptions.paces, isSelected: { profile.pace == $0 }) { value in
                Haptics.light()
                userProfileStore.update { $0.pace = value }
            }
        }
        card(titleKey: "onboarding.travelStyle.budgetLabel") {
            ChipGrid(options: ProfileOptions.budgets, isSelected: { profile.budget == $0 }) { value in
                Haptics.light()
                userProfileStore.update { $0.budget = value }
            }
        }
        card(titleKey: "onboarding.travelStyle.groupLabel") {
            ChipGrid(options: ProfileOptions.groupTypes, isSelected: { profile.groupType == $0 }) { value in
                Haptics.light()
                userProfileStore.update { $0.groupType = value }
            }
        }
    }

    private var languageCard: some View {
        card(titleKey: "settings.language.label") {
            FlowLayout(spacing: 8) {
                ForEach(languageOptions, id: \.labelKey) { option in
                    let active = languageStore.code == option.code
                    Button {
                        guard !active else { return }
                        Haptics.light()
                        languageStore.setLanguage(option.code)
                        showingRestartHint = true
                    } label: {
                        HStack(spacing: 5) {
                            Image(systemName: option.icon)
                            Text(String(localized: String.LocalizationValue(option.labelKey)))
                        }
                        .font(.system(size: 14, weight: .medium))
                        .padding(.horizontal, 14).padding(.vertical, 8)
                        .background(Capsule().fill(active ? Theme.navy : Color(.secondarySystemBackground)))
                        .foregroundStyle(active ? .white : .primary)
                        .overlay(Capsule().stroke(active ? Theme.navy : Color(.separator), lineWidth: 1.5))
                    }
                    .buttonStyle(.plain)
                }
            }
            // Unlike i18next's instant in-JS switch, iOS has no public API to
            // re-resolve a running process's localized strings — the choice
            // only takes effect after Piri is force-quit and reopened.
            Text("settings.language.restartHint")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
        }
        .alert(String(localized: "settings.language.restartHint"), isPresented: $showingRestartHint) {
            Button(String(localized: "common.done"), role: .cancel) {}
        }
    }

    private var cityCard: some View {
        card(titleKey: "settings.currentCity") {
            Button {
                showingCityPicker = true
            } label: {
                HStack {
                    Image(systemName: cityStore.cityName != nil ? "mappin" : "globe")
                        .foregroundStyle(.primary)
                    Text(cityStore.cityName.map { L("home.cityPill", $0) } ?? String(localized: "common.everywhere"))
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.primary)
                    Spacer()
                    Text("settings.changeCity").font(.system(size: 14, weight: .semibold)).foregroundStyle(Theme.gold)
                }
                // Without this, only the icon/text/label glyphs themselves
                // are tappable — the `Spacer()`-filled middle of the row
                // isn't part of any subview's rendered bounds, so a tap
                // there (found via a UI test computing its tap point from
                // the accessibility frame's center, which lands in exactly
                // that gap) silently misses the button entirely.
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
    }

    private var savedDataCard: some View {
        let savedListsCount = savedPlacesStore.savedLists.count
        let plansCount = savedPlacesStore.plans.count
        let recentCount = recentlyViewedStore.viewed.count

        return card(titleKey: "settings.savedPlaces", trailing: {
            Button("settings.viewAll") { showingSaved = .saved }
                .font(.system(size: 14, weight: .semibold)).foregroundStyle(Theme.gold)
        }) {
            HStack(spacing: 12) {
                statButton(count: savedListsCount, labelKey: "settings.stats.lists") { showingSaved = .saved }
                statButton(count: plansCount, labelKey: "settings.stats.plans") { showingSaved = .plan }
                statButton(count: recentCount, labelKey: "settings.stats.visited") { showingSaved = .visited }
            }
            clearButton(titleKey: "settings.clearHistory", disabled: recentCount == 0) { recentlyViewedStore.clearHistory() }
        }
    }

    private var tripsCard: some View {
        card(titleKey: "trips.title", trailing: {
            NavigationLink(destination: TripsScreen()) {
                Text("settings.viewAll").font(.system(size: 14, weight: .semibold)).foregroundStyle(Theme.gold)
            }
        }) {
            Text(LPlural("trips.count", count: tripsStore.trips.count)).font(.system(size: 14)).foregroundStyle(.secondary)
        }
    }

    private func statButton(count: Int, labelKey: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 2) {
                Text("\(count)").font(.system(size: 22, weight: .bold))
                Text(String(localized: String.LocalizationValue(labelKey))).font(.system(size: 12)).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .background(RoundedRectangle(cornerRadius: 12).fill(Theme.navy.opacity(0.05)))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(.secondary.opacity(0.12)))
        }
        .buttonStyle(.plain)
    }

    private func clearButton(titleKey: String, disabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(String(localized: String.LocalizationValue(titleKey)))
                .font(.system(size: 14))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 11)
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(.secondary.opacity(0.24)))
        }
        .buttonStyle(.plain)
        .disabled(disabled)
        .opacity(disabled ? 0.35 : 1)
    }

    @ViewBuilder
    private func card(titleKey: String, noteKey: String? = nil, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(String(localized: String.LocalizationValue(titleKey)))
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
            if let noteKey {
                Text(String(localized: String.LocalizationValue(noteKey))).font(.system(size: 14)).foregroundStyle(.secondary).padding(.top, -6)
            }
            content()
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(RoundedRectangle(cornerRadius: 18).stroke(.secondary.opacity(0.18)))
    }

    @ViewBuilder
    private func card(titleKey: String, @ViewBuilder trailing: () -> some View, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(String(localized: String.LocalizationValue(titleKey)))
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
                Spacer()
                trailing()
            }
            content()
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(RoundedRectangle(cornerRadius: 18).stroke(.secondary.opacity(0.18)))
    }
}

