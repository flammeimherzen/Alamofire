import Foundation

private enum CacheKeys: String {
    case contentURL = "cached_content_url"
    case registrationAttempted = "registration_attempted"
}

public final class DataCache {
    public static let shared = DataCache()
    
    private let storage: UserDefaults
    
    private init() {
        self.storage = UserDefaults.standard
    }
    
    public var contentURL: String? {
        get { storage.string(forKey: CacheKeys.contentURL.rawValue) }
        set { storage.set(newValue, forKey: CacheKeys.contentURL.rawValue) }
    }
    
    public var hasContentURL: Bool {
        guard let url = contentURL, !url.isEmpty else {
            return false
        }
        return true
    }
    
    public var wasRegistrationAttempted: Bool {
        get { storage.bool(forKey: CacheKeys.registrationAttempted.rawValue) }
        set { storage.set(newValue, forKey: CacheKeys.registrationAttempted.rawValue) }
    }
    
    public func saveContentURL(_ url: String?) {
        print("💾 [DataCache] Saving content URL: \(url ?? "nil")")
        contentURL = url
        wasRegistrationAttempted = true
        print("   Registration attempted flag: \(wasRegistrationAttempted)")
    }
    
    public func clearCache() {
        contentURL = nil
        wasRegistrationAttempted = false
    }
}
