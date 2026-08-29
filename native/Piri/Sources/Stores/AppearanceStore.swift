import Foundation
import Observation
import SwiftUI

/// Same shape as `LanguageStore`: `scheme` is `nil` for "follow system".
@Observable
final class AppearanceStore {
    private(set) var scheme: ColorScheme?

    private let defaultsKey = "appearance-preference"

    init() {
        switch UserDefaults.standard.string(forKey: defaultsKey) {
        case "light": scheme = .light
        case "dark": scheme = .dark
        default: scheme = nil
        }
    }

    func setScheme(_ scheme: ColorScheme?) {
        self.scheme = scheme
        switch scheme {
        case .light: UserDefaults.standard.set("light", forKey: defaultsKey)
        case .dark: UserDefaults.standard.set("dark", forKey: defaultsKey)
        default: UserDefaults.standard.removeObject(forKey: defaultsKey)
        }
    }
}
