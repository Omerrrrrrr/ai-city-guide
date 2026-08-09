import Foundation
import Observation

/// Port of `mobile/src/store/language.ts`. `code` is `nil` for "follow system".
@Observable
final class LanguageStore {
    private(set) var code: String?

    private let defaultsKey = "language-preference"

    init() {
        code = UserDefaults.standard.string(forKey: defaultsKey)
        LanguageManager.apply(code)
    }

    func setLanguage(_ code: String?) {
        self.code = code
        if let code {
            UserDefaults.standard.set(code, forKey: defaultsKey)
        } else {
            UserDefaults.standard.removeObject(forKey: defaultsKey)
        }
        LanguageManager.apply(code)
    }
}
