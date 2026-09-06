import StoreKit
import SwiftUI

/// Premium tier (Adım 4) purchase screen -- 2 tiers (Basic/Pro) × 2 periods
/// (monthly/yearly) = the 4 subscription products, plus the one-time Trip
/// Pass (`tripPassSection`) as a secondary option below them. Entry points:
/// `ProfileScreen`'s account card (signed-in, free tier) and
/// `POIExplainSheet`'s `upgrade_required` premium-details error.
struct PaywallScreen: View {
    @Environment(PurchaseStore.self) private var purchaseStore
    @Environment(AuthStore.self) private var authStore
    @Environment(\.dismiss) private var dismiss

    private enum Period: String, CaseIterable {
        case monthly, yearly
    }

    private enum Tier: String, CaseIterable {
        case basic, pro
    }

    // UI copy only -- doesn't enforce anything itself. Must stay in sync
    // with `apps/api/src/entitlements.ts`'s `TIER_LIMITS`, the actual
    // source of truth: the two paid tiers unlock the exact same feature
    // set (richer, verified premium place data), differing only in how much
    // of it each period allows. Pro's count dropped from 300 to 120 in the
    // 2026-09 pricing review -- 300 cost more per heavy user in live-data
    // fetches than either considered Pro price nets after Apple's cut.
    private static let placeUnlocksPerMonth: [Tier: Int] = [.basic: 50, .pro: 120]
    // Basic still shows its literal daily count; Pro's own quota (see
    // `TIER_LIMITS.pro.ask_piri_chat`) stays a real number server-side but
    // is deliberately framed as unlimited here -- it's a high backend
    // abuse-guard, not a product-facing limit a normal user should ever
    // see or hit.
    private static let chatQuestionsPerDay: [Tier: Int] = [.basic: 40]

    @State private var period: Period = .monthly
    @State private var tier: Tier = .pro
    @State private var purchasingProductID: String?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    header

                    VStack(spacing: 8) {
                        Picker("", selection: $tier) {
                            Text("paywall.basic.title").tag(Tier.basic)
                            Text("paywall.pro.title").tag(Tier.pro)
                        }
                        .pickerStyle(.segmented)

                        if tier == .pro {
                            Text("paywall.mostPopular")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundStyle(Theme.navy)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 4)
                                .background(Capsule().fill(Theme.gold))
                        }
                    }

                    Picker("", selection: $period) {
                        Text("paywall.monthly").tag(Period.monthly)
                        Text("paywall.yearly").tag(Period.yearly)
                    }
                    .pickerStyle(.segmented)

                    featureChecklist
                    purchaseButton

                    if let loadError = purchaseStore.loadError {
                        Text(loadError)
                            .font(.footnote)
                            .foregroundStyle(Theme.closedRed)
                    }

                    if let error = purchaseStore.purchaseError {
                        Text(error)
                            .font(.footnote)
                            .foregroundStyle(Theme.closedRed)
                    }

                    autoRenewDisclosure

                    tripPassSection

                    restoreButton
                    legalLinks
                }
                .padding(24)
            }
            .background(Theme.screenBackground.ignoresSafeArea())
            .environment(\.colorScheme, .dark)
            .navigationTitle(String(localized: String.LocalizationValue("paywall.title")))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(String(localized: String.LocalizationValue("common.cancel"))) { dismiss() }
                }
            }
            .task { await purchaseStore.loadProducts() }
        }
    }

    private var header: some View {
        VStack(spacing: 8) {
            Text("◈").font(.largeTitle).foregroundStyle(Theme.gold)
            Text(String(localized: String.LocalizationValue("paywall.subtitle")))
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
    }

    private func product(id: String) -> Product? {
        purchaseStore.products.first { $0.id == "com.piriapp.piri.\(id).\(period.rawValue)" }
    }

    /// One checklist shared by both tiers, since they unlock the exact same
    /// features (see `placeUnlocksPerMonth`'s doc comment) -- only the two
    /// quota-bearing rows change their number when `tier` toggles.
    private var featureChecklist: some View {
        VStack(alignment: .leading, spacing: 12) {
            checklistRow(String(localized: "paywall.feature.richerDescriptions"))
            checklistRow(String(localized: "paywall.feature.morePhotos"))
            checklistRow(L("paywall.feature.placeUnlocksCount", Self.placeUnlocksPerMonth[tier] ?? 0))
            if let chatCount = Self.chatQuestionsPerDay[tier] {
                checklistRow(L("paywall.feature.chatQuestionsCount", chatCount))
            } else {
                checklistRow(String(localized: "paywall.feature.chatUnlimited"))
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .piriElevatedCard()
    }

    private func checklistRow(_ text: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "checkmark.circle.fill").foregroundStyle(Theme.gold)
            Text(text).font(.system(size: 15))
        }
    }

    private var purchaseButton: some View {
        let matchingProduct = product(id: tier.rawValue)
        // `purchasingProductID == matchingProduct?.id` alone is true when
        // BOTH are nil (no purchase in flight, and the product hasn't
        // loaded yet) -- confirmed live: the button showed a permanent
        // spinner instead of the "—" placeholder while products were
        // still loading. Require a real, non-nil id match instead.
        let isPurchasing = purchasingProductID != nil && purchasingProductID == matchingProduct?.id

        return Button {
            guard let matchingProduct else { return }
            Task {
                purchasingProductID = matchingProduct.id
                let success = await purchaseStore.purchase(matchingProduct, authStore: authStore)
                purchasingProductID = nil
                if success { dismiss() }
            }
        } label: {
            Group {
                if isPurchasing {
                    ProgressView().tint(.white)
                } else {
                    Text(matchingProduct?.displayPrice ?? "—")
                }
            }
            .font(.system(size: 15, weight: .semibold))
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(RoundedRectangle(cornerRadius: 14).fill(LinearGradient.piriHero))
            .shadow(color: Theme.gold.opacity(0.35), radius: 12, x: 0, y: 6)
        }
        .buttonStyle(.plain)
        .disabled(matchingProduct == nil || purchasingProductID != nil)
    }

    /// One-time, repurchasable Trip Pass -- a secondary option below the
    /// subscription tiers above, not a third tier of its own. Only shown
    /// once the product has actually loaded (same "don't imply a purchase
    /// exists before it's confirmed available" rule `purchaseButton`
    /// follows for the subscriptions).
    @ViewBuilder
    private var tripPassSection: some View {
        if let tripPassProduct {
            let isPurchasing = purchasingProductID == tripPassProduct.id

            VStack(spacing: 6) {
                Button {
                    Task {
                        purchasingProductID = tripPassProduct.id
                        let success = await purchaseStore.purchase(tripPassProduct, authStore: authStore)
                        purchasingProductID = nil
                        if success { dismiss() }
                    }
                } label: {
                    if isPurchasing {
                        ProgressView().tint(Theme.gold)
                    } else {
                        Text(L("paywall.tripPass.description", tripPassProduct.displayPrice))
                    }
                }
                .buttonStyle(.plain)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(Theme.gold)
                .disabled(purchasingProductID != nil)

                Text(String(localized: "paywall.tripPass.oneTime"))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .multilineTextAlignment(.center)
        }
    }

    private var tripPassProduct: Product? {
        purchaseStore.products.first { $0.id == PurchaseStore.tripPassProductID }
    }

    private var restoreButton: some View {
        Button {
            Task { await purchaseStore.restorePurchases() }
        } label: {
            Text(String(localized: String.LocalizationValue("paywall.restore")))
                .font(.footnote)
                .foregroundStyle(Theme.gold)
        }
        .buttonStyle(.plain)
    }

    /// Required by App Review guideline 3.1.2 -- the length/price/
    /// auto-renewal terms of an auto-renewing subscription must be stated
    /// on the purchase screen itself, not just in App Store Connect's own
    /// product metadata.
    private var autoRenewDisclosure: some View {
        Text(String(localized: String.LocalizationValue(
            period == .monthly ? "paywall.autoRenew.monthly" : "paywall.autoRenew.yearly"
        )))
        .font(.caption2)
        .foregroundStyle(.secondary)
        .multilineTextAlignment(.center)
    }

    /// Also required by 3.1.2 -- functional links to the Privacy Policy and
    /// Terms of Use (EULA) must be reachable from the subscription purchase
    /// screen itself. No custom EULA exists, so this links Apple's own
    /// standard one (the same one App Store Connect's License Agreement
    /// field defaults to when a developer hasn't supplied a custom EULA).
    private var legalLinks: some View {
        HStack(spacing: 16) {
            Link(String(localized: String.LocalizationValue("paywall.termsOfUse")),
                 destination: URL(string: "https://www.apple.com/legal/internet-services/itunes/dev/stdeula/")!)
            Link(String(localized: String.LocalizationValue("paywall.privacyPolicy")),
                 destination: URL(string: "https://api.getpiri.com/privacy")!)
        }
        .font(.caption)
        .foregroundStyle(.secondary)
    }
}
