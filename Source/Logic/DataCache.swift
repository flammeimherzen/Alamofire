import Foundation

public final class DataCache {
    public static let shared = DataCache()

    private let storage: UserDefaults

    private static let contentURLKey = "cached_content_url"
    private static let registrationAttemptedKey = "registration_attempted"

    private init() {
        self.storage = UserDefaults.standard
        SessionVault.restore()
    }

    public var contentURL: String? {
        get { storage.string(forKey: Self.contentURLKey) }
        set {
            if let value = newValue {
                storage.set(value, forKey: Self.contentURLKey)
            } else {
                storage.removeObject(forKey: Self.contentURLKey)
            }
        }
    }

    public var hasContentURL: Bool {
        guard let url = contentURL, !url.isEmpty else { return false }
        return true
    }

    public var wasRegistrationAttempted: Bool {
        get { storage.bool(forKey: Self.registrationAttemptedKey) }
        set { storage.set(newValue, forKey: Self.registrationAttemptedKey) }
    }

    public func saveContentURL(_ url: String?) {
        wasRegistrationAttempted = true
        guard let url, !url.isEmpty else { return }
        contentURL = url
    }

    public func clearCache() {
        contentURL = nil
        wasRegistrationAttempted = false
    }
}
