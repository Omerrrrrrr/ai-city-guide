import Foundation

struct AuthUser: Codable, Equatable {
    let id: String
    let email: String
    let displayName: String?
}

struct AuthTokenResponse: Decodable {
    let token: String
    let user: AuthUser
}

struct AppleSignInRequest: Encodable {
    let identityToken: String
    let email: String?
    let fullName: String?
}

struct RegisterRequest: Encodable {
    let email: String
    let password: String
    let displayName: String?
}

struct LoginRequest: Encodable {
    let email: String
    let password: String
}

/// Mirrors the backend's whole-blob sync shape 1:1: each of the three synced
/// stores already serializes itself to one JSON value for local persistence
/// (see UserDefaultsStore/KeychainStore), and the server stores/returns
/// exactly that same shape under a `value` + `updatedAt` envelope.
struct SyncEntry<Value: Codable>: Codable {
    let value: Value
    let updatedAt: String
}

struct SyncPullResponse: Decodable {
    let profile: SyncEntry<UserProfile>?
    let savedPlaces: SyncEntry<[SavedCollection]>?
    let trips: SyncEntry<[Trip]>?
}

/// Partial by design (all-optional, synthesized `Encodable` omits nil
/// members entirely) -- a push only ever carries whichever one store
/// actually changed, not the other two.
struct SyncPushRequest: Encodable {
    var profile: UserProfile?
    var savedPlaces: [SavedCollection]?
    var trips: [Trip]?
}

struct SyncPushResponse: Decodable {
    let updatedAt: String
}
