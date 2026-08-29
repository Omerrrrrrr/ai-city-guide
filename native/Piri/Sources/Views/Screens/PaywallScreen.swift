import StoreKit
import SwiftUI

/// Premium tier (Adım 4) purchase screen -- 2 tiers (Basic/Pro) × 2 periods
/// (monthly/yearly) = the 4 products `PurchaseStore` loads. Entry points:
/// `ProfileScreen`'s account card (signed-in, free tier) and
/// `POIExplainSheet`'s `upgrade_required` premium-details error.
struct PaywallScreen: View {
    @Environment(PurchaseStore.self) private var purchaseStore
    @Environment(AuthStore.self) private var authStore
    @Environment(\.dismiss) private var dismiss

    private enum Period: String, CaseIterable {
        case monthly, yearly
    }

    @State private var period: Period = .monthly
    @State private var purchasingProductID: String?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    header

                    Picker("", selection: $period) {
                        Text("paywall.monthly").tag(Period.monthly)
                        Text("paywall.yearly").tag(Period.yearly)
                    }
                    .pickerStyle(.segmented)

                    tierCard(id: "basic", titleKey: "paywall.basic.title", featureKey: "paywall.basic.feature")
                    tierCard(id: "pro", titleKey: "paywall.pro.title", featureKey: "paywall.pro.feature")

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

                    restoreButton
                }
                .padding(24)
            }
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

    private func tierCard(id: String, titleKey: String, featureKey: String) -> some View {
        let matchingProduct = product(id: id)
        // `purchasingProductID == matchingProduct?.id` alone is true when
        // BOTH are nil (no purchase in flight, and the product hasn't
        // loaded yet) -- confirmed live: every card showed a permanent
        // spinner instead of the "—" placeholder while products were
        // still loading. Require a real, non-nil id match instead.
        let isPurchasing = purchasingProductID != nil && purchasingProductID == matchingProduct?.id

        return VStack(alignment: .leading, spacing: 10) {
            Text(String(localized: String.LocalizationValue(titleKey)))
                .font(.system(size: 17, weight: .bold))
            Text(String(localized: String.LocalizationValue(featureKey)))
                .font(.footnote)
                .foregroundStyle(.secondary)

            Button {
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
                .background(RoundedRectangle(cornerRadius: 14).fill(Theme.navy))
            }
            .buttonStyle(.plain)
            .disabled(matchingProduct == nil || purchasingProductID != nil)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(RoundedRectangle(cornerRadius: 18).stroke(.secondary.opacity(0.18)))
    }

    private var restoreButton: some View {
        Button {
            Task { await purchaseStore.restorePurchases() }
        } label: {
            Text(String(localized: String.LocalizationValue("paywall.restore")))
                .font(.footnote)
                .foregroundStyle(Theme.navy)
        }
        .buttonStyle(.plain)
    }
}
