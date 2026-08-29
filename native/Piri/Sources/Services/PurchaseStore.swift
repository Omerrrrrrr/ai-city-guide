import Foundation
import Observation
import StoreKit

/// StoreKit 2 purchase flow (Premium tier Adım 4). Loads the 4 subscription
/// `Product`s, drives a purchase, and verifies every transaction it ever
/// sees (a fresh purchase, a renewal, or a restore alike) against the
/// backend via `IAPAPI` -- the backend, not this store, is the actual
/// source of truth for `AuthUser.tier`, reached via `AuthStore.refreshMe()`
/// after each successful verify. Doesn't hold a reference to `AuthStore`
/// itself (methods take one as a parameter instead), matching every other
/// store in this app -- cross-store orchestration lives in `RootView`.
@Observable
final class PurchaseStore {
    static let productIDs = [
        "com.piriapp.piri.basic.monthly",
        "com.piriapp.piri.basic.yearly",
        "com.piriapp.piri.pro.monthly",
        "com.piriapp.piri.pro.yearly",
    ]

    private(set) var products: [Product] = []
    private(set) var isLoadingProducts = false
    private(set) var loadError: String?
    var purchaseError: String?

    // StoreKit product loading (`loadProducts` below) only returns real
    // data when Xcode itself launches the app (Run/Test), which honors
    // the scheme's `StoreKitConfigurationFileReference` (see
    // `project.yml`) -- a bare `xcrun simctl launch` (headless/scripted
    // testing) has no scheme in play, so `Product.products(for:)` falls
    // through to the real App Store network path and naturally returns
    // nothing for these 4 placeholder product IDs.
    // `StoreKitTest.SKTestSession` looked like a launch-method-independent
    // workaround but Apple only supports it from a *test target*'s
    // bundle, not the main app's -- verify this flow by running the
    // `Piri` scheme directly from Xcode instead.

    func loadProducts() async {
        guard products.isEmpty else { return }
        isLoadingProducts = true
        defer { isLoadingProducts = false }
        do {
            products = try await Product.products(for: Self.productIDs)
            if products.isEmpty {
                loadError = "StoreKit returned zero products for the 4 configured IDs."
            }
        } catch {
            loadError = "\(error)"
        }
    }

    /// Returns `true` only once the purchase has been both made and
    /// verified server-side (i.e. `authStore.user?.tier` is already
    /// current by the time this returns) -- a cancel or a still-pending
    /// (e.g. Ask to Buy) purchase returns `false` without setting
    /// `purchaseError`, since neither is a real failure worth surfacing as
    /// one.
    @discardableResult
    func purchase(_ product: Product, authStore: AuthStore) async -> Bool {
        purchaseError = nil
        do {
            switch try await product.purchase() {
            case .success(let verification):
                return await sync(verification, authStore: authStore)
            case .userCancelled, .pending:
                return false
            @unknown default:
                return false
            }
        } catch {
            purchaseError = String(localized: "paywall.purchaseFailed")
            return false
        }
    }

    /// `AppStore.sync()` re-delivers this account's existing entitlements
    /// through `Transaction.updates` (see `observeTransactionUpdates`,
    /// running for the app's whole lifetime from `RootView`) -- nothing
    /// further to do here once it returns.
    func restorePurchases() async {
        try? await AppStore.sync()
    }

    /// Started once from `RootView.task`, runs for the app's lifetime.
    /// Picks up a purchase made while this store's own `purchase(_:)` call
    /// wasn't the one in flight (e.g. bought on another device, a renewal,
    /// or a restore) and verifies+syncs it the same way.
    func observeTransactionUpdates(authStore: AuthStore) async {
        for await verification in Transaction.updates {
            await sync(verification, authStore: authStore)
        }
    }

    @discardableResult
    private func sync(_ verification: VerificationResult<Transaction>, authStore: AuthStore) async -> Bool {
        guard case .verified(let transaction) = verification else {
            // StoreKit's own on-device check failed -- never trust this,
            // don't finish it (nothing safe to acknowledge).
            return false
        }
        guard let token = authStore.token else {
            // Not signed in -- can't attach a purchase to an account.
            // Leaving the transaction unfinished means StoreKit redelivers
            // it through `Transaction.updates` next launch/foreground,
            // once there's somewhere to attach it.
            return false
        }
        do {
            _ = try await IAPAPI.verifyTransaction(signedTransactionInfo: verification.jwsRepresentation, token: token)
        } catch {
            // Backend unreachable or rejected it -- also leave unfinished
            // so this retries later rather than silently dropping a real
            // purchase.
            return false
        }
        await transaction.finish()
        await authStore.refreshMe()
        return true
    }
}
