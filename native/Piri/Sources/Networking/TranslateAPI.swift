import Foundation

/// Generic text translation (MyMemory, free, keyless) -- not tied to
/// reviews specifically, just the first real caller (`PiriReviewsSection`).
enum TranslateAPI {
    static func translate(text: String, targetLang: String) async throws -> TranslationResult {
        try await APIClient.shared.post("/translate", body: TranslateRequest(text: text, targetLang: targetLang))
    }
}
