import Foundation

public final class AppRouter {
    public static let shared = AppRouter()
    
    private let networkService: NetworkService
    private let dataCache: DataCache
    
    private init() {
        self.networkService = NetworkService.shared
        self.dataCache = DataCache.shared
    }
    
    public func determineInitialRoute(completion: @escaping (DisplayMode, String?) -> Void) {
        print("🛣️ [AppRouter] Determining initial route...")
        
        if dataCache.wasRegistrationAttempted {
            if dataCache.hasContentURL, let cachedURL = dataCache.contentURL {
                print("✅ [AppRouter] Registration was successful, cached URL found: \(cachedURL)")
                print("   Showing web content (registration already completed)")
                completion(.webContent, cachedURL)
            } else {
                print("ℹ️ [AppRouter] Registration was attempted but failed (success = false)")
                print("   Showing native interface (no more registration attempts)")
                completion(.nativeInterface, nil)
            }
            return
        }
        
        print("🆕 [AppRouter] First launch, performing registration (one time only)...")
        networkService.performRegistration { mode, url in
            print("✅ [AppRouter] Route determined: \(mode), URL: \(url ?? "nil")")
            completion(mode, url)
        }
    }
}
