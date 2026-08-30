import Foundation

struct TranslationResult: Decodable {
    var translatedText: String
    var detectedSourceLang: String?
}

struct TranslateRequest: Encodable {
    var text: String
    var targetLang: String
}
