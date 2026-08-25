import Foundation

/// StoreKit 2 purchase verification (Premium tier Adım 4). One endpoint,
/// reused for a fresh purchase, a renewal picked up via
/// `Transaction.updates`, and a restore (`AppStore.sync()`) alike -- see
/// `PurchaseStore`.
enum IAPAPI {
    static func verifyTransaction(signedTransactionInfo: String, token: String) async throws -> AuthUser {
        try await APIClient.shared.post(
            "/iap/verify-transaction",
            body: VerifyTransactionRequest(signedTransactionInfo: signedTransactionInfo),
            bearerToken: token
        )
    }
}

private struct VerifyTransactionRequest: Encodable {
    var signedTransactionInfo: String
}
