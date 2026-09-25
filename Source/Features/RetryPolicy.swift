
import Foundation

open class RetryPolicy: @unchecked Sendable, RequestInterceptor {
    public static let defaultRetryLimit: UInt = 2

    public static let defaultExponentialBackoffBase: UInt = 2

    public static let defaultExponentialBackoffScale: Double = 0.5

    public static let defaultRetryableHTTPMethods: Set<HTTPMethod> = [.delete,
                                                                      .get,
                                                                      .head,
                                                                      .options,
                                                                      .put,
                                                                      .trace
    ]

    public static let defaultRetryableHTTPStatusCodes: Set<Int> = [408,
                                                                   500,
                                                                   502,
                                                                   503,
                                                                   504
    ]

    public static let defaultRetryableURLErrorCodes: Set<URLError.Code> = [

        .backgroundSessionInUseByAnotherProcess,

        .backgroundSessionWasDisconnected,

        .badServerResponse,

        .callIsActive,

        .cannotConnectToHost,

        .cannotFindHost,

        .cannotLoadFromNetwork,

        .dataNotAllowed,

        .dnsLookupFailed,

        .downloadDecodingFailedMidStream,

        .downloadDecodingFailedToComplete,

        .internationalRoamingOff,

        .networkConnectionLost,

        .notConnectedToInternet,

        .secureConnectionFailed,

        .serverCertificateHasBadDate,

        .serverCertificateNotYetValid,

        .timedOut

    ]

    public let retryLimit: UInt

    public let exponentialBackoffBase: UInt

    public let exponentialBackoffScale: Double

    public let retryableHTTPMethods: Set<HTTPMethod>

    public let retryableHTTPStatusCodes: Set<Int>

    public let retryableURLErrorCodes: Set<URLError.Code>

    public init(retryLimit: UInt = RetryPolicy.defaultRetryLimit,
                exponentialBackoffBase: UInt = RetryPolicy.defaultExponentialBackoffBase,
                exponentialBackoffScale: Double = RetryPolicy.defaultExponentialBackoffScale,
                retryableHTTPMethods: Set<HTTPMethod> = RetryPolicy.defaultRetryableHTTPMethods,
                retryableHTTPStatusCodes: Set<Int> = RetryPolicy.defaultRetryableHTTPStatusCodes,
                retryableURLErrorCodes: Set<URLError.Code> = RetryPolicy.defaultRetryableURLErrorCodes) {
        precondition(exponentialBackoffBase >= 2, "The `exponentialBackoffBase` must be a minimum of 2.")

        self.retryLimit = retryLimit
        self.exponentialBackoffBase = exponentialBackoffBase
        self.exponentialBackoffScale = exponentialBackoffScale
        self.retryableHTTPMethods = retryableHTTPMethods
        self.retryableHTTPStatusCodes = retryableHTTPStatusCodes
        self.retryableURLErrorCodes = retryableURLErrorCodes
    }

    open func retry(_ request: Request,
                    for session: Session,
                    dueTo error: any Error,
                    completion: @escaping @Sendable (RetryResult) -> Void) {
        if request.retryCount < retryLimit, shouldRetry(request: request, dueTo: error) {
            completion(.retryWithDelay(pow(Double(exponentialBackoffBase), Double(request.retryCount)) * exponentialBackoffScale))
        } else {
            completion(.doNotRetry)
        }
    }

    open func shouldRetry(request: Request, dueTo error: any Error) -> Bool {
        guard let httpMethod = request.request?.method, retryableHTTPMethods.contains(httpMethod) else { return false }

        if let statusCode = request.response?.statusCode, retryableHTTPStatusCodes.contains(statusCode) {
            return true
        } else {
            let errorCode = (error as? URLError)?.code
            let afErrorCode = (error.asAFError?.underlyingError as? URLError)?.code

            guard let code = errorCode ?? afErrorCode else { return false }

            return retryableURLErrorCodes.contains(code)
        }
    }
}

extension RequestInterceptor where Self == RetryPolicy {
    public static var retryPolicy: RetryPolicy { RetryPolicy() }

    public static func retryPolicy(retryLimit: UInt = RetryPolicy.defaultRetryLimit,
                                   exponentialBackoffBase: UInt = RetryPolicy.defaultExponentialBackoffBase,
                                   exponentialBackoffScale: Double = RetryPolicy.defaultExponentialBackoffScale,
                                   retryableHTTPMethods: Set<HTTPMethod> = RetryPolicy.defaultRetryableHTTPMethods,
                                   retryableHTTPStatusCodes: Set<Int> = RetryPolicy.defaultRetryableHTTPStatusCodes,
                                   retryableURLErrorCodes: Set<URLError.Code> = RetryPolicy.defaultRetryableURLErrorCodes) -> RetryPolicy {
        RetryPolicy(retryLimit: retryLimit,
                    exponentialBackoffBase: exponentialBackoffBase,
                    exponentialBackoffScale: exponentialBackoffScale,
                    retryableHTTPMethods: retryableHTTPMethods,
                    retryableHTTPStatusCodes: retryableHTTPStatusCodes,
                    retryableURLErrorCodes: retryableURLErrorCodes)
    }
}

open class ConnectionLostRetryPolicy: RetryPolicy, @unchecked Sendable {
    public init(retryLimit: UInt = RetryPolicy.defaultRetryLimit,
                exponentialBackoffBase: UInt = RetryPolicy.defaultExponentialBackoffBase,
                exponentialBackoffScale: Double = RetryPolicy.defaultExponentialBackoffScale,
                retryableHTTPMethods: Set<HTTPMethod> = RetryPolicy.defaultRetryableHTTPMethods) {
        super.init(retryLimit: retryLimit,
                   exponentialBackoffBase: exponentialBackoffBase,
                   exponentialBackoffScale: exponentialBackoffScale,
                   retryableHTTPMethods: retryableHTTPMethods,
                   retryableHTTPStatusCodes: [],
                   retryableURLErrorCodes: [.networkConnectionLost])
    }
}

extension RequestInterceptor where Self == ConnectionLostRetryPolicy {
    public static var connectionLostRetryPolicy: ConnectionLostRetryPolicy { ConnectionLostRetryPolicy() }

    public static func connectionLostRetryPolicy(retryLimit: UInt = RetryPolicy.defaultRetryLimit,
                                                 exponentialBackoffBase: UInt = RetryPolicy.defaultExponentialBackoffBase,
                                                 exponentialBackoffScale: Double = RetryPolicy.defaultExponentialBackoffScale,
                                                 retryableHTTPMethods: Set<HTTPMethod> = RetryPolicy.defaultRetryableHTTPMethods) -> ConnectionLostRetryPolicy {
        ConnectionLostRetryPolicy(retryLimit: retryLimit,
                                  exponentialBackoffBase: exponentialBackoffBase,
                                  exponentialBackoffScale: exponentialBackoffScale,
                                  retryableHTTPMethods: retryableHTTPMethods)
    }
}
