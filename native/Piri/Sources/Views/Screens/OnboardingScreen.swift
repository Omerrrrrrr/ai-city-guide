import SwiftUI

private let totalSteps = 4

/// Port of `mobile/app/onboarding.tsx`.
struct OnboardingScreen: View {
    @Environment(UserProfileStore.self) private var userProfileStore

    @State private var step = 0
    @State private var name = ""
    @State private var profession: Profession?
    @State private var interests: [Interest] = []
    @State private var faith: Faith?
    @State private var budget: Budget?
    @State private var groupType: GroupType?
    @State private var pace: Pace?

    var body: some View {
        if step == 0 {
            welcomeStep
        } else {
            wizard
        }
    }

    private var welcomeStep: some View {
        VStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text("◈").font(.system(size: 48)).foregroundStyle(Theme.gold)
                    Text("onboarding.wordmark").font(.system(size: 52, weight: .heavy)).tracking(10).foregroundStyle(.white)
                    Text("onboarding.tagline").font(.system(size: 22, weight: .light)).tracking(0.5).foregroundStyle(Theme.gold)
                    Text("onboarding.welcomeBody").font(.system(size: 16)).foregroundStyle(.white.opacity(0.7))
                }
                .padding(.vertical, 32)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            Button {
                Haptics.medium()
                step = 1
            } label: {
                Text("onboarding.begin")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(Theme.navy)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 18)
                    .background(RoundedRectangle(cornerRadius: 16).fill(Theme.gold))
            }
        }
        .padding(.horizontal, 32)
        .padding(.bottom, 40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.navy.ignoresSafeArea())
    }

    private var wizard: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                GeometryReader { proxy in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color(.systemGray5)).frame(height: 3)
                        Capsule().fill(Theme.navy).frame(width: proxy.size.width * CGFloat(step) / CGFloat(totalSteps), height: 3)
                    }
                }
                .frame(height: 3)
                Text(L("onboarding.stepOf", String(step), String(totalSteps)))
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            .padding(.horizontal, 20)
            .padding(.top, 16)
            .padding(.bottom, 8)

            ScrollView {
                Group {
                    switch step {
                    case 1: nameStep
                    case 2: professionStep
                    case 3: faithInterestsStep
                    case 4: travelStyleStep
                    default: EmptyView()
                    }
                }
                .padding(.horizontal, 24)
                .padding(.top, 32)
            }

            HStack(spacing: 12) {
                Button("common.skip") { advance() }
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(.secondary)
                Button {
                    advance()
                } label: {
                    Text(step == totalSteps ? String(localized: "common.done") : String(localized: "common.continue"))
                        .font(.system(size: 17, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(RoundedRectangle(cornerRadius: 14).fill(Theme.navy))
                }
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 16)
        }
    }

    private var nameStep: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("onboarding.name.title").font(.system(size: 28, weight: .bold))
            Text("onboarding.name.subtitle").font(.system(size: 15)).foregroundStyle(.secondary).padding(.bottom, 18)
            TextField(String(localized: "onboarding.name.placeholder"), text: $name)
                .textInputAutocapitalization(.words)
                .padding(.horizontal, 18)
                .padding(.vertical, 16)
                .background(RoundedRectangle(cornerRadius: 14).fill(Color(.secondarySystemBackground)))
                .overlay(RoundedRectangle(cornerRadius: 14).stroke(.secondary.opacity(0.2), lineWidth: 1.5))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var professionStep: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("onboarding.profession.title").font(.system(size: 28, weight: .bold))
            Text("onboarding.profession.subtitle").font(.system(size: 15)).foregroundStyle(.secondary).padding(.bottom, 18)
            ChipGrid(options: ProfileOptions.professions, isSelected: { profession == $0 }) { value in
                Haptics.light()
                profession = value
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var faithInterestsStep: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("onboarding.faithInterests.title").font(.system(size: 28, weight: .bold))
            Text("onboarding.faithInterests.subtitle").font(.system(size: 15)).foregroundStyle(.secondary).padding(.bottom, 18)

            Text("onboarding.faithInterests.interestsLabel").font(.system(size: 13, weight: .semibold)).foregroundStyle(.secondary).textCase(.uppercase)
            ChipGrid(options: ProfileOptions.interests, isSelected: { interests.contains($0) }) { value in
                Haptics.light()
                if let index = interests.firstIndex(of: value) { interests.remove(at: index) } else { interests.append(value) }
            }
            .padding(.bottom, 10)

            Text("onboarding.faithInterests.faithLabel").font(.system(size: 13, weight: .semibold)).foregroundStyle(.secondary).textCase(.uppercase).padding(.top, 18)
            Text("onboarding.faithInterests.faithNote").font(.system(size: 14)).foregroundStyle(.secondary)
            ChipGrid(options: ProfileOptions.faiths, isSelected: { faith == $0 }) { value in
                Haptics.light()
                faith = value
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var travelStyleStep: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("onboarding.travelStyle.title").font(.system(size: 28, weight: .bold))
            Text("onboarding.travelStyle.subtitle").font(.system(size: 15)).foregroundStyle(.secondary).padding(.bottom, 18)

            Text("onboarding.travelStyle.paceLabel").font(.system(size: 13, weight: .semibold)).foregroundStyle(.secondary).textCase(.uppercase)
            ChipGrid(options: ProfileOptions.paces, isSelected: { pace == $0 }) { value in
                Haptics.light()
                pace = value
            }

            Text("onboarding.travelStyle.budgetLabel").font(.system(size: 13, weight: .semibold)).foregroundStyle(.secondary).textCase(.uppercase).padding(.top, 18)
            ChipGrid(options: ProfileOptions.budgets, isSelected: { budget == $0 }) { value in
                Haptics.light()
                budget = value
            }

            Text("onboarding.travelStyle.groupLabel").font(.system(size: 13, weight: .semibold)).foregroundStyle(.secondary).textCase(.uppercase).padding(.top, 18)
            ChipGrid(options: ProfileOptions.groupTypes, isSelected: { groupType == $0 }) { value in
                Haptics.light()
                groupType = value
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func advance() {
        if step < totalSteps {
            step += 1
        } else {
            finish()
        }
    }

    private func finish() {
        userProfileStore.update { profile in
            profile.name = name.trimmingCharacters(in: .whitespaces)
            profile.profession = profession
            profile.interests = interests
            profile.faith = faith
            profile.budget = budget
            profile.groupType = groupType
            profile.pace = pace
        }
        userProfileStore.completeOnboarding()
    }
}
