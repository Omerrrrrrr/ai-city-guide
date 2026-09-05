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
    ("es", "globe", "settings.language.es"),
    ("de", "globe", "settings.language.de"),
    ("fr", "globe", "settings.language.fr"),
    ("it", "globe", "settings.language.it"),
    ("pt-BR", "globe", "settings.language.pt"),
]

private let appearanceOptions: [(scheme: ColorScheme?, icon: String, labelKey: String)] = [
    (nil, "circle.righthalf.filled", "settings.appearance.system"),
    (.light, "sun.max.fill", "settings.appearance.light"),
    (.dark, "moon.fill", "settings.appearance.dark"),
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
    case profession, interests, plan
    var id: Self { self }
}

/// Which side of the currency converter `CurrencyPickerSheet` is currently
/// open for -- see `ProfileScreen.cityCard`.
private enum CurrencySide: Identifiable {
    case home, destination
    var id: Self { self }
}

/// Port of `mobile/app/(tabs)/settings.tsx`.
struct ProfileScreen: View {
    @Environment(UserProfileStore.self) private var userProfileStore
    @Environment(CityStore.self) private var cityStore
    @Environment(LanguageStore.self) private var languageStore
    @Environment(AppearanceStore.self) private var appearanceStore
    @Environment(MapsProviderStore.self) private var mapsProviderStore
    @Environment(PreferredCurrencyStore.self) private var preferredCurrencyStore
    @Environment(SavedPlacesStore.self) private var savedPlacesStore
    @Environment(RecentlyViewedStore.self) private var recentlyViewedStore
    @Environment(MyReviewsStore.self) private var myReviewsStore
    @Environment(TripsStore.self) private var tripsStore
    @Environment(PlacesQuery.self) private var placesQuery
    @Environment(AuthStore.self) private var authStore
    @Environment(FriendsStore.self) private var friendsStore
    @Environment(PurchaseStore.self) private var purchaseStore

    @State private var isEditingName = false
    @State private var isEditingProfileDetails = false
    @State private var isEditingAppSettings = false
    @State private var nameInput = ""
    @State private var showingCityPicker = false
    @State private var pickingCurrencySide: CurrencySide?
    @State private var destinationCurrencyOverride: String?
    @State private var liveRate: Double?
    @State private var liveRateTask: Task<Void, Never>?
    @State private var showingSaved: SavedTab?
    @State private var showingRestartHint = false
    @State private var profileTab: ProfileTab = .profession
    @State private var newInterestText = ""
    @State private var showingSignIn = false
    @State private var showingPaywall = false
    @State private var showingAvatarPicker = false

    private var profile: UserProfile { userProfileStore.profile }
    private var displayName: String {
        let trimmed = profile.name.trimmingCharacters(in: .whitespaces)
        return trimmed.isEmpty ? String(localized: "settings.travelerFallback") : trimmed
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                header
                quickStatsRow
                cityCard
                if authStore.isSignedIn {
                    premiumCard
                }
                profileSummaryCard
                // Plain app settings (display language, light/dark mode,
                // preferred maps app) -- previously nested inside "Seni
                // Böyle Görüyoruz"'s personalization tabs, behind its edit
                // toggle, under a "Dil" tab. Reported live ("Bu sayfa
                // yanlış," referring to that card): none of these three
                // describe how the app personalizes to the user, so they
                // don't belong gated inside a personalization-profile
                // editor at all -- they're just settings, always visible.
                // Grouped with "How we see you" just above Account, at the
                // bottom of the scroll -- both are settings-adjacent
                // ("configure how the app treats me") rather than the
                // profile's own substantive content (Friends/Trips/Saved/
                // Premium), which now leads the screen instead.
                appSettingsCard
                accountCard

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
                        NavigationLink(destination: AdminReviewsScreen()) {
                            Text("settings.reviewModeration")
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
        .sheet(isPresented: $showingSignIn) { SignInScreen() }
        .sheet(isPresented: $showingPaywall) { PaywallScreen() }
        .sheet(isPresented: $showingAvatarPicker) { AvatarPickerSheet() }
        .background(Theme.screenBackground.ignoresSafeArea())
        .environment(\.colorScheme, .dark)
        .navigationBarHidden(true)
    }

    /// The entry point `PaywallScreen`'s own doc comment always claimed
    /// existed here ("ProfileScreen's account card, signed-in, free
    /// tier") but never actually did until now -- there was no purchase
    /// button or active-plan confirmation anywhere in the app. Signed-out
    /// accounts don't see this at all (matches `accountCard`'s own
    /// sign-in gate above it -- nothing to upgrade without an account).
    private var premiumCard: some View {
        card(titleKey: "settings.premium") {
            if let user = authStore.user, user.isPaidTier {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 6) {
                        Image(systemName: "checkmark.seal.fill").foregroundStyle(Theme.gold)
                        Text(String(localized: String.LocalizationValue(
                            user.tier == "pro" ? "settings.premium.proActive" : "settings.premium.basicActive"
                        )))
                        .font(.system(size: 15, weight: .semibold))
                    }
                    if let expiresAt = user.tierExpiresAt, let date = ISO8601DateFormatter().date(from: expiresAt) {
                        Text(L("settings.premium.renewsOn", date.formatted(date: .abbreviated, time: .omitted)))
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    if let url = URL(string: "https://apps.apple.com/account/subscriptions") {
                        Link(destination: url) {
                            Text(String(localized: String.LocalizationValue("settings.premium.manage")))
                                .font(.footnote.weight(.semibold))
                                .foregroundStyle(Theme.gold)
                        }
                    }
                }
            } else {
                VStack(alignment: .leading, spacing: 10) {
                    Text(String(localized: String.LocalizationValue("settings.premium.free")))
                        .font(.system(size: 14))
                        .foregroundStyle(.secondary)
                    Button {
                        showingPaywall = true
                    } label: {
                        Text(String(localized: String.LocalizationValue("settings.premium.upgrade")))
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(RoundedRectangle(cornerRadius: 14).fill(Theme.gold))
                    }
                    .buttonStyle(.plain)
                    Button {
                        Task { await purchaseStore.restorePurchases() }
                    } label: {
                        Text(String(localized: String.LocalizationValue("paywall.restore")))
                            .font(.footnote)
                            .foregroundStyle(Theme.gold)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 14) {
                // Only signed-in accounts can actually store a photo
                // server-side (see `PATCH /me/avatar`) -- a signed-out
                // session keeps the plain initial-letter circle, not
                // tappable, same as before.
                if authStore.isSignedIn {
                    Button {
                        Haptics.light()
                        showingAvatarPicker = true
                    } label: {
                        avatarView
                    }
                    .buttonStyle(.plain)
                } else {
                    avatarView
                }

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

                Spacer(minLength: 8)
            }

            // A full-width headline, not a small badge tucked in the
            // corner -- every mockup this pass drew from gave level/XP its
            // own prominent row right under the avatar, not a detail easy
            // to miss beside the name. Still just a tap-through to the
            // exact same `GamificationScreen` breakdown as before.
            NavigationLink(destination: GamificationScreen()) {
                levelIndicator
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 12)
        .padding(.bottom, 16)
        .frame(maxWidth: .infinity, alignment: .leading)
        // A gradient hero band, not the flat glass fill every other
        // screen's header uses -- this is the one place in Profile that
        // should read as the premium, "important" moment, matching the
        // gold-to-navy header band every mockup gave the Profile screen.
        .background(LinearGradient.piriHero)
        .padding(.horizontal, -20)
        .padding(.top, -20)
    }

    /// The real uploaded photo (`AuthUser.avatarUrl`) when signed in and set,
    /// else the same initial-letter placeholder this always showed before
    /// (reported live: "Kişinin kendi profil fotoğrafı yok").
    @ViewBuilder
    private var avatarView: some View {
        if let avatarUrl = authStore.user?.avatarUrl {
            DataURIImage(dataUri: avatarUrl)
                .frame(width: 52, height: 52)
                .clipShape(Circle())
        } else {
            ZStack {
                Circle().fill(.white.opacity(0.15))
                Text(displayName.prefix(1).uppercased()).font(.system(size: 24, weight: .bold)).foregroundStyle(Theme.gold)
            }
            .frame(width: 52, height: 52)
        }
    }

    /// Reflects the profile fields already collected (profession, interests,
    /// budget, group, pace) back in plain language, with editing one tap
    /// away — the same fields already silently shape every AI blurb via
    /// `buildProfileContext`, but until now the user never saw evidence of
    /// that. Deliberately excludes `faith`: the research behind this card
    /// (see the 2026-08 visual-design report) found users are fine with a
    /// sensitive field driving something they themselves triggered (the
    /// halal filter, already built that way) but not with it appearing as
    /// a passive, always-visible label about them.
    private var profileSummaryCard: some View {
        let parts = ProfileOptions.summaryParts(for: profile)
        return card(titleKey: "settings.profileSummary.title", trailing: {
            Button(String(localized: isEditingProfileDetails ? "common.done" : "settings.profileSummary.edit")) {
                withAnimation { isEditingProfileDetails.toggle() }
            }
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(Theme.gold)
        }) {
            VStack(alignment: .leading, spacing: 14) {
                if !parts.isEmpty {
                    Text(parts.joined(separator: " · ")).font(.system(size: 15))
                }
                if isEditingProfileDetails {
                    profileTabsSegment
                    profileTabContent
                }
            }
        }
    }

    /// A score derived fresh from data already tracked elsewhere (profile
    /// completeness, saved places, completed trips, recently-viewed count)
    /// rather than a separately persisted counter -- see `Gamification`.
    /// Lives in the header, to the right of the name, as a compact badge;
    /// tapping it drills into `GamificationScreen` for the full XP
    /// breakdown and the Leaderboard link, rather than this header chip
    /// growing into its own scrolled-past card.
    private var levelIndicator: some View {
        let completedTrips = tripsStore.trips.filter { $0.endedAt != nil }.count
        let savedPlaceCount = savedPlacesStore.collections.reduce(0) { $0 + $1.places.count }
        let xp = Gamification.xp(
            profile: profile,
            savedPlaceCount: savedPlaceCount,
            completedTripCount: completedTrips,
            visitedCount: recentlyViewedStore.viewed.count,
            reviewCount: myReviewsStore.count
        )
        let level = Gamification.level(forXP: xp)

        return VStack(alignment: .leading, spacing: 6) {
            HStack {
                HStack(spacing: 8) {
                    Text(Gamification.rankName(forLevel: level))
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(.white)
                    Text(L("settings.xp.level", level))
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Theme.navy)
                        .padding(.horizontal, 8).padding(.vertical, 3)
                        .background(Capsule().fill(Theme.gold))
                }
                Spacer()
                Text(L("settings.xp.progressFraction", xp, (level) * Gamification.xpPerLevel))
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.white.opacity(0.7))
            }
            ProgressView(value: Gamification.progressIntoCurrentLevel(xp))
                .tint(Theme.gold)
        }
        .frame(maxWidth: .infinity)
    }

    private var profileTabsSegment: some View {
        HStack(spacing: 3) {
            profileTabButton(.profession, label: String(localized: "settings.tabs.profession"))
            profileTabButton(.interests, label: String(localized: "settings.tabs.interests"))
            profileTabButton(.plan, label: String(localized: "settings.tabs.plan"))
        }
        .padding(3)
        .background(RoundedRectangle(cornerRadius: 12).fill(Theme.cardFill))
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
            if profile.profession == .other {
                professionOtherField
            }
        }
    }

    // Ten presets can't cover everyone's actual interests -- this lets
    // someone add their own ("wine tasting", "street art", whatever isn't
    // one of the chips above) instead of settling for the closest fit or
    // nothing. Merged into `UserProfile.interestsText` alongside the presets.
    private var customInterestsField: some View {
        VStack(alignment: .leading, spacing: 10) {
            if !profile.customInterests.isEmpty {
                FlowLayout(spacing: 8) {
                    ForEach(profile.customInterests, id: \.self) { interest in
                        HStack(spacing: 5) {
                            Text(interest)
                            Button {
                                Haptics.light()
                                userProfileStore.update { $0.customInterests.removeAll { $0 == interest } }
                            } label: {
                                Image(systemName: "xmark").font(.system(size: 10, weight: .bold))
                            }
                        }
                        .font(.system(size: 14, weight: .medium))
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(Capsule().fill(Theme.navy))
                        .foregroundStyle(.white)
                    }
                }
            }

            HStack(spacing: 8) {
                TextField(String(localized: "profileOptions.interests.addPlaceholder"), text: $newInterestText)
                    .textInputAutocapitalization(.never)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 11)
                    .background(RoundedRectangle(cornerRadius: 12).fill(Theme.cardFill))
                    .onSubmit(addCustomInterest)

                Button(action: addCustomInterest) {
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: 26))
                        .foregroundStyle(newInterestText.trimmingCharacters(in: .whitespaces).isEmpty ? Color.secondary.opacity(0.4) : Theme.gold)
                }
                .disabled(newInterestText.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(.top, 10)
    }

    private func addCustomInterest() {
        let trimmed = newInterestText.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        Haptics.light()
        userProfileStore.update { profile in
            if !profile.customInterests.contains(where: { $0.caseInsensitiveCompare(trimmed) == .orderedSame }) {
                profile.customInterests.append(trimmed)
            }
        }
        newInterestText = ""
    }

    // Picking "Other" used to be a dead end -- see `UserProfile.professionText`
    // -- so the AI never learned anything beyond "not one of the ten presets."
    // This is the only place that text actually gets captured.
    private var professionOtherField: some View {
        TextField(String(localized: "profileOptions.professions.otherPlaceholder"), text: Binding(
            get: { profile.professionOther },
            set: { newValue in userProfileStore.update { $0.professionOther = newValue } }
        ))
        .textInputAutocapitalization(.words)
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .background(RoundedRectangle(cornerRadius: 12).fill(Theme.cardFill))
        .padding(.top, 10)
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
            customInterestsField
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

    /// Collapses Language/Appearance/Preferred Maps App behind one tappable
    /// summary row instead of three always-visible cards -- reported live
    /// as visual clutter now that each renders as its own full elevated
    /// card. Tapping reveals the exact same three cards, unchanged,
    /// directly below.
    private var appSettingsCard: some View {
        VStack(spacing: 12) {
            Button {
                Haptics.light()
                withAnimation { isEditingAppSettings.toggle() }
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: "gearshape.fill")
                        .foregroundStyle(Theme.gold)
                        .frame(width: 28, height: 28)
                        .background(Circle().fill(Theme.gold.opacity(0.12)))
                    VStack(alignment: .leading, spacing: 2) {
                        Text(String(localized: "settings.appSettings.title"))
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(.primary)
                        if !isEditingAppSettings {
                            Text(appSettingsSummary).font(.system(size: 13)).foregroundStyle(.secondary).lineLimit(1)
                        }
                    }
                    Spacer()
                    Image(systemName: "chevron.down")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .rotationEffect(.degrees(isEditingAppSettings ? 180 : 0))
                }
                .padding(14)
                .piriElevatedCard(cornerRadius: 14)
            }
            .buttonStyle(.plain)

            if isEditingAppSettings {
                languageCard
                appearanceCard
                mapsProviderCard
            }
        }
    }

    private var appSettingsSummary: String {
        let language = languageOptions.first { $0.code == languageStore.code }
            .map { String(localized: String.LocalizationValue($0.labelKey)) } ?? ""
        let appearance = appearanceOptions.first { $0.scheme == appearanceStore.scheme }
            .map { String(localized: String.LocalizationValue($0.labelKey)) } ?? ""
        let maps = String(localized: String.LocalizationValue(mapsProviderStore.provider.labelKey))
        return [language, appearance, maps].joined(separator: " · ")
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
                        .background(Capsule().fill(active ? Theme.navy : Theme.cardFill))
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

    private var appearanceCard: some View {
        card(titleKey: "settings.appearance.label") {
            HStack(spacing: 8) {
                ForEach(appearanceOptions, id: \.labelKey) { option in
                    let active = appearanceStore.scheme == option.scheme
                    Button {
                        guard !active else { return }
                        Haptics.light()
                        appearanceStore.setScheme(option.scheme)
                    } label: {
                        HStack(spacing: 5) {
                            Image(systemName: option.icon)
                            Text(String(localized: String.LocalizationValue(option.labelKey)))
                        }
                        .font(.system(size: 14, weight: .medium))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background(Capsule().fill(active ? Theme.navy : Theme.cardFill))
                        .foregroundStyle(active ? .white : .primary)
                        .overlay(Capsule().stroke(active ? Theme.navy : Color(.separator), lineWidth: 1.5))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    /// Which app "Open in Maps" hands off to, app-wide (`PlaceDirections`
    /// reads this same preference) — not just Apple Maps, since not every
    /// traveler has or prefers it.
    private var mapsProviderCard: some View {
        card(titleKey: "settings.mapsProvider.label") {
            HStack(spacing: 8) {
                ForEach(MapsProvider.allCases) { option in
                    let active = mapsProviderStore.provider == option
                    Button {
                        guard !active else { return }
                        Haptics.light()
                        mapsProviderStore.setProvider(option)
                    } label: {
                        HStack(spacing: 5) {
                            Image(systemName: option.icon)
                            Text(String(localized: String.LocalizationValue(option.labelKey)))
                        }
                        .font(.system(size: 14, weight: .medium))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background(Capsule().fill(active ? Theme.navy : Theme.cardFill))
                        .foregroundStyle(active ? .white : .primary)
                        .overlay(Capsule().stroke(active ? Theme.navy : Color(.separator), lineWidth: 1.5))
                    }
                    .buttonStyle(.plain)
                }
            }
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

            if let subtitle = cityContextSubtitle {
                Text(subtitle)
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .padding(.top, 2)
            }

            // Two independently-pickable sides, not one auto-derived from
            // the city -- a first version only let the destination side
            // follow the current city's currency automatically, but the
            // point of a converter is comparing whatever two currencies
            // the traveler actually cares about (their own, and a
            // *specific* one they're pricing against), not just "here vs.
            // home." Both open the same `CurrencyPickerSheet`, just for a
            // different side.
            currencyRow(
                icon: "banknote",
                labelKey: "settings.homeCurrency",
                code: preferredCurrencyStore.code
            ) { pickingCurrencySide = .home }

            currencyRow(
                icon: "arrow.left.arrow.right",
                labelKey: "settings.counterpartCurrency",
                code: destinationCurrencyCode
            ) { pickingCurrencySide = .destination }

            if let liveRate {
                Text("1 \(preferredCurrencyStore.code) ≈ \(String(format: "%.3f", liveRate)) \(destinationCurrencyCode)")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
            }
        }
        .sheet(item: $pickingCurrencySide) { side in
            CurrencyPickerSheet(
                title: side == .home ? String(localized: "settings.homeCurrency.title") : String(localized: "settings.counterpartCurrency.title"),
                selectedCode: side == .home ? preferredCurrencyStore.code : destinationCurrencyCode
            ) { code in
                if side == .home {
                    preferredCurrencyStore.setCode(code)
                } else {
                    destinationCurrencyOverride = code
                }
            }
        }
        .task { await refreshLiveRate() }
        .onChange(of: preferredCurrencyStore.code) { _, _ in Task { await refreshLiveRate() } }
        .onChange(of: destinationCurrencyOverride) { _, _ in Task { await refreshLiveRate() } }
        .onChange(of: cityStore.countryInfo) { _, _ in Task { await refreshLiveRate() } }
    }

    private func currencyRow(icon: String, labelKey: String, code: String, action: @escaping () -> Void) -> some View {
        Button {
            Haptics.light()
            action()
        } label: {
            HStack {
                Image(systemName: icon).foregroundStyle(.primary)
                Text(L(labelKey, code))
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.primary)
                Spacer()
                Text("settings.changeCurrency").font(.system(size: 14, weight: .semibold)).foregroundStyle(Theme.gold)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    /// `nil` (the default) means "follow the current city's own currency" --
    /// set once the traveler explicitly picks a different counterpart, at
    /// which point it stops tracking city changes until cleared. Falls back
    /// to USD when neither a city nor an override is set, same reasoning as
    /// `PreferredCurrencyStore`'s own default.
    private var destinationCurrencyCode: String {
        destinationCurrencyOverride ?? cityStore.countryInfo?.currencies.first?.code ?? "USD"
    }

    /// Independent of `CityStore.exchangeRates` (which is always keyed to
    /// the current city's own currency as `base`) -- once the counterpart
    /// side can be overridden away from the city's currency, that cache no
    /// longer necessarily has the right base, so this fetches fresh
    /// whenever either side changes instead.
    private func refreshLiveRate() async {
        liveRateTask?.cancel()
        let task = Task {
            let rates = try? await CityContextAPI.currencyRates(base: preferredCurrencyStore.code)
            guard !Task.isCancelled else { return }
            liveRate = rates?.rates[destinationCurrencyCode]
        }
        liveRateTask = task
        await task.value
    }

    /// Reads `CityStore`'s per-city cache (country/timezone, fetched once
    /// per city change -- see `CityStore.refreshContext`) rather than
    /// making its own network call. No currency here anymore -- that's the
    /// two picker rows + live-rate line below instead of a passive label,
    /// and no flag emoji -- confirmed live it renders as two broken tofu
    /// boxes rather than the intended flag glyph, not worth the risk.
    private var cityContextSubtitle: String? {
        guard let info = cityStore.countryInfo else { return nil }
        var parts = [info.name]
        if let timezone = cityStore.timezones.first {
            parts.append(timezone)
        }
        return parts.joined(separator: " · ")
    }

    private var accountCard: some View {
        card(titleKey: "settings.account") {
            if let user = authStore.user {
                VStack(alignment: .leading, spacing: 10) {
                    let name = user.displayName?.trimmingCharacters(in: .whitespaces)
                    Text((name?.isEmpty == false ? name : nil) ?? user.email)
                        .font(.system(size: 15, weight: .semibold))
                    Button(role: .destructive) {
                        authStore.signOut()
                    } label: {
                        Text(String(localized: String.LocalizationValue("settings.account.signOut")))
                            .font(.system(size: 14, weight: .semibold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .overlay(RoundedRectangle(cornerRadius: 12).stroke(.secondary.opacity(0.24)))
                    }
                    .buttonStyle(.plain)
                }
            } else {
                VStack(alignment: .leading, spacing: 10) {
                    Text(String(localized: String.LocalizationValue("settings.account.signedOutNote")))
                        .font(.system(size: 14))
                        .foregroundStyle(.secondary)
                    Button {
                        showingSignIn = true
                    } label: {
                        Text(String(localized: String.LocalizationValue("settings.account.signIn")))
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(RoundedRectangle(cornerRadius: 14).fill(Theme.navy))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    /// Only shown signed-in (Faz 1 social layer requires an account, same
    /// reasoning `RootView`'s sync gating already uses). Loads its own
    /// count on appear rather than depending on `FriendsScreen` having
    /// been opened first, since this card renders whenever Profile does.
    /// Three equal-weight tiles in one row, matching every mockup this pass
    /// drew from -- replaces what used to be three separate full-width
    /// cards (Friends/Saved Places/Trips), each with its own "View all"
    /// link, header label, and (for Saved Places) a further Lists/Plans/
    /// Visited breakdown + a Clear History button. That breakdown and the
    /// clear action are still one tap away inside `SavedScreen` itself
    /// (its own Visited tab has the identical Clear button already) --
    /// nothing here is actually lost, just no longer duplicated at the top
    /// level for content dense enough to warrant a whole card each.
    private var quickStatsRow: some View {
        HStack(spacing: 10) {
            Button {
                Haptics.light()
                showingSaved = .saved
            } label: {
                quickStatTile(
                    icon: "bookmark.fill",
                    value: savedPlacesStore.savedLists.count + savedPlacesStore.plans.count,
                    labelKey: "settings.savedPlaces"
                )
            }
            .buttonStyle(.plain)

            NavigationLink(destination: TripsScreen()) {
                quickStatTile(icon: "suitcase.fill", value: tripsStore.trips.count, labelKey: "trips.title")
            }
            .buttonStyle(.plain)

            if authStore.isSignedIn {
                NavigationLink(destination: FriendsScreen()) {
                    quickStatTile(icon: "person.2.fill", value: friendsStore.friends.count, labelKey: "friends.title")
                        .overlay(alignment: .topTrailing) {
                            if !friendsStore.incomingRequests.isEmpty {
                                Text("\(friendsStore.incomingRequests.count)")
                                    .font(.system(size: 11, weight: .bold))
                                    .foregroundStyle(.white)
                                    .padding(.horizontal, 6).padding(.vertical, 2)
                                    .background(Capsule().fill(Theme.gold))
                                    .offset(x: -6, y: 6)
                            }
                        }
                }
                .buttonStyle(.plain)
                .task {
                    if let token = authStore.token {
                        await friendsStore.fetchFollows(token: token)
                    }
                }
            }
        }
    }

    private func quickStatTile(icon: String, value: Int, labelKey: String) -> some View {
        VStack(spacing: 6) {
            Image(systemName: icon).font(.system(size: 19)).foregroundStyle(Theme.gold)
            Text("\(value)").font(.system(size: 18, weight: .bold)).foregroundStyle(.primary)
            Text(String(localized: String.LocalizationValue(labelKey)))
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 14)
        .piriElevatedCard(cornerRadius: 14)
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
        .piriElevatedCard()
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
        .piriElevatedCard()
    }
}

