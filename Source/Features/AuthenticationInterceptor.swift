
import Foundation

public protocol AuthenticationCredential {
    var requiresRefresh: Bool { get }
}

public protocol Authenticator: AnyObject, Sendable {
    associatedtype Credential: AuthenticationCredential & Sendable

    func apply(_ credential: Credential, to urlRequest: inout URLRequest)

    func refresh(_ credential: Credential, for session: Session, completion: @escaping @Sendable (Result<Credential, any Error>) -> Void)

    func didRequest(_ urlRequest: URLRequest, with response: HTTPURLResponse, failDueToAuthenticationError error: any Error) -> Bool

    func isRequest(_ urlRequest: URLRequest, authenticatedWith credential: Credential) -> Bool
}

public enum AuthenticationError: Error {
    case missingCredential
    case excessiveRefresh
}

public final class AuthenticationInterceptor<AuthenticatorType>: RequestInterceptor, Sendable where AuthenticatorType: Authenticator {

    public typealias Credential = AuthenticatorType.Credential

    public struct RefreshWindow {
        public let interval: TimeInterval

        public let maximumAttempts: Int

        public init(interval: TimeInterval = 30.0, maximumAttempts: Int = 5) {
            self.interval = interval
            self.maximumAttempts = maximumAttempts
        }
    }

    private struct AdaptOperation {
        let urlRequest: URLRequest
        let session: Session
        let completion: @Sendable (Result<URLRequest, any Error>) -> Void
    }

    private enum AdaptResult {
        case adapt(Credential)
        case doNotAdapt(AuthenticationError)
        case adaptDeferred
    }

    private struct MutableState {
        var credential: Credential?

        var isRefreshing = false
        var refreshTimestamps: [TimeInterval] = []
        var refreshWindow: RefreshWindow?

        var adaptOperations: [AdaptOperation] = []
        var requestsToRetry: [@Sendable (RetryResult) -> Void] = []
    }

    public var credential: Credential? {
        get { mutableState.read(\.credential) }
        set { mutableState.write { $0.credential = newValue } }
    }

    let authenticator: AuthenticatorType
    let queue = DispatchQueue(label: "org.alamofire.authentication.inspector")

    private let mutableState: Protected<MutableState>

    public init(authenticator: AuthenticatorType,
                credential: Credential? = nil,
                refreshWindow: RefreshWindow? = RefreshWindow()) {
        self.authenticator = authenticator
        mutableState = Protected(MutableState(credential: credential, refreshWindow: refreshWindow))
    }

    public func adapt(_ urlRequest: URLRequest, for session: Session, completion: @escaping @Sendable (Result<URLRequest, any Error>) -> Void) {
        let adaptResult: AdaptResult = mutableState.write { mutableState in
            guard !mutableState.isRefreshing else {
                let operation = AdaptOperation(urlRequest: urlRequest, session: session, completion: completion)
                mutableState.adaptOperations.append(operation)
                return .adaptDeferred
            }

            guard let credential = mutableState.credential else {
                let error = AuthenticationError.missingCredential
                return .doNotAdapt(error)
            }

            guard !credential.requiresRefresh else {
                let operation = AdaptOperation(urlRequest: urlRequest, session: session, completion: completion)
                mutableState.adaptOperations.append(operation)
                refresh(credential, for: session, insideLock: &mutableState)
                return .adaptDeferred
            }

            return .adapt(credential)
        }

        switch adaptResult {
        case let .adapt(credential):
            var authenticatedRequest = urlRequest
            authenticator.apply(credential, to: &authenticatedRequest)
            completion(.success(authenticatedRequest))

        case let .doNotAdapt(adaptError):
            completion(.failure(adaptError))

        case .adaptDeferred:
            break
        }
    }

    public func retry(_ request: Request, for session: Session, dueTo error: any Error, completion: @escaping @Sendable (RetryResult) -> Void) {
        guard let urlRequest = request.request, let response = request.response else {
            completion(.doNotRetry)
            return
        }

        guard authenticator.didRequest(urlRequest, with: response, failDueToAuthenticationError: error) else {
            completion(.doNotRetry)
            return
        }

        guard let credential else {
            let error = AuthenticationError.missingCredential
            completion(.doNotRetryWithError(error))
            return
        }

        guard authenticator.isRequest(urlRequest, authenticatedWith: credential) else {
            completion(.retry)
            return
        }

        mutableState.write { mutableState in
            mutableState.requestsToRetry.append(completion)

            guard !mutableState.isRefreshing else { return }

            refresh(credential, for: session, insideLock: &mutableState)
        }
    }

    private func refresh(_ credential: Credential, for session: Session, insideLock mutableState: inout MutableState) {
        guard !isRefreshExcessive(insideLock: &mutableState) else {
            let error = AuthenticationError.excessiveRefresh
            handleRefreshFailure(error, insideLock: &mutableState)
            return
        }

        mutableState.refreshTimestamps.append(ProcessInfo.processInfo.systemUptime)
        mutableState.isRefreshing = true

        queue.async {
            self.authenticator.refresh(credential, for: session) { result in
                self.mutableState.write { mutableState in
                    switch result {
                    case let .success(credential):
                        self.handleRefreshSuccess(credential, insideLock: &mutableState)
                    case let .failure(error):
                        self.handleRefreshFailure(error, insideLock: &mutableState)
                    }
                }
            }
        }
    }

    private func isRefreshExcessive(insideLock mutableState: inout MutableState) -> Bool {
        guard let refreshWindow = mutableState.refreshWindow else { return false }

        let refreshWindowMin = ProcessInfo.processInfo.systemUptime - refreshWindow.interval

        let refreshAttemptsWithinWindow = mutableState.refreshTimestamps.reduce(into: 0) { attempts, refreshTimestamp in
            guard refreshWindowMin <= refreshTimestamp else { return }
            attempts += 1
        }

        let isRefreshExcessive = refreshAttemptsWithinWindow >= refreshWindow.maximumAttempts

        return isRefreshExcessive
    }

    private func handleRefreshSuccess(_ credential: Credential, insideLock mutableState: inout MutableState) {
        mutableState.credential = credential

        let adaptOperations = mutableState.adaptOperations
        let requestsToRetry = mutableState.requestsToRetry

        mutableState.adaptOperations.removeAll()
        mutableState.requestsToRetry.removeAll()

        mutableState.isRefreshing = false

        queue.async {
            adaptOperations.forEach { self.adapt($0.urlRequest, for: $0.session, completion: $0.completion) }
            requestsToRetry.forEach { $0(.retry) }
        }
    }

    private func handleRefreshFailure(_ error: any Error, insideLock mutableState: inout MutableState) {
        let adaptOperations = mutableState.adaptOperations
        let requestsToRetry = mutableState.requestsToRetry

        mutableState.adaptOperations.removeAll()
        mutableState.requestsToRetry.removeAll()

        mutableState.isRefreshing = false

        queue.async {
            adaptOperations.forEach { $0.completion(.failure(error)) }
            requestsToRetry.forEach { $0(.doNotRetryWithError(error)) }
        }
    }
}
