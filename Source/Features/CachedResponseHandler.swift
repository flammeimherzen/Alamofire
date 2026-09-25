
import Foundation

public protocol CachedResponseHandler: Sendable {
    func dataTask(_ task: URLSessionDataTask,
                  willCacheResponse response: CachedURLResponse,
                  completion: @escaping (CachedURLResponse?) -> Void)
}

public struct ResponseCacher {
    public enum Behavior: Sendable {
        case cache
        case doNotCache
        case modify(@Sendable (_ task: URLSessionDataTask, _ cachedResponse: CachedURLResponse) -> CachedURLResponse?)
    }

    public static let cache = ResponseCacher(behavior: .cache)
    public static let doNotCache = ResponseCacher(behavior: .doNotCache)

    public let behavior: Behavior

    public init(behavior: Behavior) {
        self.behavior = behavior
    }
}

extension ResponseCacher: CachedResponseHandler {
    public func dataTask(_ task: URLSessionDataTask,
                         willCacheResponse response: CachedURLResponse,
                         completion: @escaping (CachedURLResponse?) -> Void) {
        switch behavior {
        case .cache:
            completion(response)
        case .doNotCache:
            completion(nil)
        case let .modify(closure):
            let response = closure(task, response)
            completion(response)
        }
    }
}

extension CachedResponseHandler where Self == ResponseCacher {
    public static var cache: ResponseCacher { .cache }

    public static var doNotCache: ResponseCacher { .doNotCache }

    public static func modify(using closure: @escaping (@Sendable (URLSessionDataTask, CachedURLResponse) -> CachedURLResponse?)) -> ResponseCacher {
        ResponseCacher(behavior: .modify(closure))
    }
}
