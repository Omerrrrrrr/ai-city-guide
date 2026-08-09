import Foundation

/// Generic Codable-backed UserDefaults slot, standing in for the RN app's
/// AsyncStorage-backed Zustand `persist` middleware (non-sensitive stores:
/// city, user-profile, trips, recently-viewed).
struct UserDefaultsStore<Value: Codable> {
    let key: String
    private let defaults: UserDefaults

    init(key: String, defaults: UserDefaults = .standard) {
        self.key = key
        self.defaults = defaults
    }

    func load() -> Value? {
        guard let data = defaults.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(Value.self, from: data)
    }

    func save(_ value: Value) {
        guard let data = try? JSONEncoder().encode(value) else { return }
        defaults.set(data, forKey: key)
    }

    func clear() {
        defaults.removeObject(forKey: key)
    }
}
