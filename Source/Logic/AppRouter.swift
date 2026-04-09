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
        if dataCache.wasRegistrationAttempted {
            if dataCache.hasContentURL, let cachedURL = dataCache.contentURL {
                completion(.webContent, cachedURL)
            } else {
                completion(.nativeInterface, nil)
            }
            return
        }

        networkService.performRegistration { mode, url in
            completion(mode, url)
        }
    }
}
