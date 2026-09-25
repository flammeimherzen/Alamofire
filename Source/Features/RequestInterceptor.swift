
import Foundation

public struct RequestAdapterState: Sendable {
    public let requestID: UUID

    public let session: Session
}

public protocol RequestAdapter: Sendable {
    func adapt(_ urlRequest: URLRequest, for session: Session, completion: @escaping @Sendable (_ result: Result<URLRequest, any Error>) -> Void)

    func adapt(_ urlRequest: URLRequest, using state: RequestAdapterState, completion: @escaping @Sendable (_ result: Result<URLRequest, any Error>) -> Void)
}

extension RequestAdapter {
    @preconcurrency
    public func adapt(_ urlRequest: URLRequest, using state: RequestAdapterState, completion: @escaping @Sendable (_ result: Result<URLRequest, any Error>) -> Void) {
        adapt(urlRequest, for: state.session, completion: completion)
    }
}

public enum RetryResult: Sendable {
    case retry
    case retryWithDelay(TimeInterval)
    case doNotRetry
    case doNotRetryWithError(any Error)
}

extension RetryResult {
    var retryRequired: Bool {
        switch self {
        case .retry, .retryWithDelay: true
        default: false
        }
    }

    var delay: TimeInterval? {
        switch self {
        case let .retryWithDelay(delay): delay
        default: nil
        }
    }

    var error: (any Error)? {
        guard case let .doNotRetryWithError(error) = self else { return nil }
        return error
    }
}

public protocol RequestRetrier: Sendable {
    func retry(_ request: Request, for session: Session, dueTo error: any Error, completion: @escaping @Sendable (RetryResult) -> Void)
}

public protocol RequestInterceptor: RequestAdapter, RequestRetrier {}

extension RequestInterceptor {
    @preconcurrency
    public func adapt(_ urlRequest: URLRequest, for session: Session, completion: @escaping @Sendable (Result<URLRequest, any Error>) -> Void) {
        completion(.success(urlRequest))
    }

    @preconcurrency
    public func retry(_ request: Request,
                      for session: Session,
                      dueTo error: any Error,
                      completion: @escaping @Sendable (RetryResult) -> Void) {
        completion(.doNotRetry)
    }
}

public typealias AdaptHandler = @Sendable (_ request: URLRequest,
                                           _ session: Session,
                                           _ completion: @escaping @Sendable (Result<URLRequest, any Error>) -> Void) -> Void

public typealias RetryHandler = @Sendable (_ request: Request,
                                           _ session: Session,
                                           _ error: any Error,
                                           _ completion: @escaping @Sendable (RetryResult) -> Void) -> Void

open class Adapter: @unchecked Sendable, RequestInterceptor {
    private let adaptHandler: AdaptHandler

    @preconcurrency
    public init(_ adaptHandler: @escaping AdaptHandler) {
        self.adaptHandler = adaptHandler
    }

    @preconcurrency
    open func adapt(_ urlRequest: URLRequest, for session: Session, completion: @escaping @Sendable (Result<URLRequest, any Error>) -> Void) {
        adaptHandler(urlRequest, session, completion)
    }

    @preconcurrency
    open func adapt(_ urlRequest: URLRequest, using state: RequestAdapterState, completion: @escaping @Sendable (Result<URLRequest, any Error>) -> Void) {
        adaptHandler(urlRequest, state.session, completion)
    }
}

extension RequestAdapter where Self == Adapter {
    @preconcurrency
    public static func adapter(using closure: @escaping AdaptHandler) -> Adapter {
        Adapter(closure)
    }
}

open class Retrier: @unchecked Sendable, RequestInterceptor {
    private let retryHandler: RetryHandler

    @preconcurrency
    public init(_ retryHandler: @escaping RetryHandler) {
        self.retryHandler = retryHandler
    }

    @preconcurrency
    open func retry(_ request: Request,
                    for session: Session,
                    dueTo error: any Error,
                    completion: @escaping @Sendable (RetryResult) -> Void) {
        retryHandler(request, session, error, completion)
    }
}

extension RequestRetrier where Self == Retrier {
    @preconcurrency
    public static func retrier(using closure: @escaping RetryHandler) -> Retrier {
        Retrier(closure)
    }
}

open class Interceptor: @unchecked Sendable, RequestInterceptor {
    public let adapters: [any RequestAdapter]
    public let retriers: [any RequestRetrier]

    public init(adaptHandler: @escaping AdaptHandler, retryHandler: @escaping RetryHandler) {
        adapters = [Adapter(adaptHandler)]
        retriers = [Retrier(retryHandler)]
    }

    public init(adapter: any RequestAdapter, retrier: any RequestRetrier) {
        adapters = [adapter]
        retriers = [retrier]
    }

    public init(adapters: [any RequestAdapter] = [],
                retriers: [any RequestRetrier] = [],
                interceptors: [any RequestInterceptor] = []) {
        self.adapters = adapters + interceptors
        self.retriers = retriers + interceptors
    }

    @preconcurrency
    open func adapt(_ urlRequest: URLRequest, for session: Session, completion: @escaping @Sendable (Result<URLRequest, any Error>) -> Void) {
        adapt(urlRequest, for: session, using: adapters, completion: completion)
    }

    private func adapt(_ urlRequest: URLRequest,
                       for session: Session,
                       using adapters: [any RequestAdapter],
                       completion: @escaping @Sendable (Result<URLRequest, any Error>) -> Void) {
        var pendingAdapters = adapters

        guard !pendingAdapters.isEmpty else { completion(.success(urlRequest)); return }

        let adapter = pendingAdapters.removeFirst()

        adapter.adapt(urlRequest, for: session) { [pendingAdapters] result in
            switch result {
            case let .success(urlRequest):
                self.adapt(urlRequest, for: session, using: pendingAdapters, completion: completion)
            case .failure:
                completion(result)
            }
        }
    }

    @preconcurrency
    open func adapt(_ urlRequest: URLRequest, using state: RequestAdapterState, completion: @escaping @Sendable (Result<URLRequest, any Error>) -> Void) {
        adapt(urlRequest, using: state, adapters: adapters, completion: completion)
    }

    private func adapt(_ urlRequest: URLRequest,
                       using state: RequestAdapterState,
                       adapters: [any RequestAdapter],
                       completion: @escaping @Sendable (Result<URLRequest, any Error>) -> Void) {
        var pendingAdapters = adapters

        guard !pendingAdapters.isEmpty else { completion(.success(urlRequest)); return }

        let adapter = pendingAdapters.removeFirst()

        adapter.adapt(urlRequest, using: state) { [pendingAdapters] result in
            switch result {
            case let .success(urlRequest):
                self.adapt(urlRequest, using: state, adapters: pendingAdapters, completion: completion)
            case .failure:
                completion(result)
            }
        }
    }

    @preconcurrency
    open func retry(_ request: Request,
                    for session: Session,
                    dueTo error: any Error,
                    completion: @escaping @Sendable (RetryResult) -> Void) {
        retry(request, for: session, dueTo: error, using: retriers, completion: completion)
    }

    private func retry(_ request: Request,
                       for session: Session,
                       dueTo error: any Error,
                       using retriers: [any RequestRetrier],
                       completion: @escaping @Sendable (RetryResult) -> Void) {
        var pendingRetriers = retriers

        guard !pendingRetriers.isEmpty else { completion(.doNotRetry); return }

        let retrier = pendingRetriers.removeFirst()

        retrier.retry(request, for: session, dueTo: error) { [pendingRetriers] result in
            switch result {
            case .retry, .retryWithDelay, .doNotRetryWithError:
                completion(result)
            case .doNotRetry:
                self.retry(request, for: session, dueTo: error, using: pendingRetriers, completion: completion)
            }
        }
    }
}

extension RequestInterceptor where Self == Interceptor {
    @preconcurrency
    public static func interceptor(adapter: @escaping AdaptHandler, retrier: @escaping RetryHandler) -> Interceptor {
        Interceptor(adaptHandler: adapter, retryHandler: retrier)
    }

    @preconcurrency
    public static func interceptor(adapter: any RequestAdapter, retrier: any RequestRetrier) -> Interceptor {
        Interceptor(adapter: adapter, retrier: retrier)
    }

    @preconcurrency
    public static func interceptor(adapters: [any RequestAdapter] = [],
                                   retriers: [any RequestRetrier] = [],
                                   interceptors: [any RequestInterceptor] = []) -> Interceptor {
        Interceptor(adapters: adapters, retriers: retriers, interceptors: interceptors)
    }
}
