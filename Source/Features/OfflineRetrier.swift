
#if canImport(Network)
import Foundation
import Network

@available(macOS 10.14, iOS 12, tvOS 12, watchOS 5, visionOS 1, *)
public final class OfflineRetrier: RequestAdapter, RequestRetrier, RequestInterceptor, Sendable {
    public static let defaultWait: DispatchTimeInterval = .seconds(5)
    public static let defaultURLErrorOfflineCodes: Set<URLError.Code> = [
        .notConnectedToInternet
    ]
    public static let defaultIsOfflineError: @Sendable (_ error: any Error) -> Bool = { error in
        if let error = error.asAFError?.underlyingError {
            defaultIsOfflineError(error)
        } else if let error = error as? URLError {
            defaultURLErrorOfflineCodes.contains(error.code)
        } else {
            false
        }
    }

    private static let monitorQueue = DispatchQueue(label: "org.alamofire.offlineRetrier.monitorQueue")

    fileprivate struct State {
        let maximumWait: DispatchTimeInterval
        let isOfflineError: (_ error: any Error) -> Bool
        let monitorCreator: () -> PathMonitor

        var timeoutWorkItem: DispatchWorkItem?
        var currentMonitor: PathMonitor?
        var pendingCompletions: [@Sendable (_ retryResult: RetryResult) -> Void] = []
    }

    private let state: Protected<State>

    public init(monitor: @autoclosure @escaping () -> NWPathMonitor = NWPathMonitor(),
                maximumWait: DispatchTimeInterval = OfflineRetrier.defaultWait,
                isOfflineError: @escaping @Sendable (_ error: any Error) -> Bool = OfflineRetrier.defaultIsOfflineError) {
        state = Protected(State(maximumWait: maximumWait, isOfflineError: isOfflineError) { PathMonitor(monitor()) })
    }

    public convenience init(requiredInterfaceType: NWInterface.InterfaceType,
                            maximumWait: DispatchTimeInterval = OfflineRetrier.defaultWait,
                            isOfflineError: @escaping @Sendable (_ error: any Error) -> Bool = OfflineRetrier.defaultIsOfflineError) {
        self.init(monitor: NWPathMonitor(requiredInterfaceType: requiredInterfaceType), maximumWait: maximumWait, isOfflineError: isOfflineError)
    }

    @available(macOS 11, iOS 14, tvOS 14, watchOS 7, visionOS 1, *)
    public convenience init(prohibitedInterfaceTypes: [NWInterface.InterfaceType],
                            maximumWait: DispatchTimeInterval = OfflineRetrier.defaultWait,
                            isOfflineError: @escaping @Sendable (_ error: any Error) -> Bool = OfflineRetrier.defaultIsOfflineError) {
        self.init(monitor: NWPathMonitor(prohibitedInterfaceTypes: prohibitedInterfaceTypes), maximumWait: maximumWait, isOfflineError: isOfflineError)
    }

    init(monitor: @autoclosure @escaping () -> PathMonitor,
         maximumWait: DispatchTimeInterval,
         isOfflineError: @escaping @Sendable (_ error: any Error) -> Bool = OfflineRetrier.defaultIsOfflineError) {
        state = Protected(State(maximumWait: maximumWait, isOfflineError: isOfflineError, monitorCreator: monitor))
    }

    deinit {
        state.write { state in
            state.cleanupMonitor()
        }
    }

    public func retry(_ request: Request,
                      for session: Session,
                      dueTo error: any Error,
                      completion: @escaping @Sendable (RetryResult) -> Void) {
        state.write { state in
            guard state.isOfflineError(error) else { completion(.doNotRetry); return }

            state.pendingCompletions.append(completion)

            guard state.currentMonitor == nil else { return }

            state.startListening { [unowned self] result in
                let retryResult: RetryResult = switch result {
                case .pathAvailable:
                    .retry
                case .timeout:
                    .doNotRetry
                }

                performResult(retryResult)
            }
        }
    }

    private func performResult(_ result: RetryResult) {
        state.write { state in
            let completions = state.pendingCompletions
            state.cleanupMonitor()
            for completion in completions {
                Self.monitorQueue.async {
                    completion(result)
                }
            }
        }
    }
}

@available(macOS 10.14, iOS 12, tvOS 12, watchOS 5, visionOS 1, *)
extension OfflineRetrier.State {
    fileprivate mutating func startListening(onResult: @escaping @Sendable (_ result: PathMonitor.Result) -> Void) {
        let timeout = DispatchWorkItem {
            onResult(.timeout)
        }
        timeoutWorkItem = timeout
        OfflineRetrier.monitorQueue.asyncAfter(deadline: .now() + maximumWait, execute: timeout)

        currentMonitor = monitorCreator()
        currentMonitor?.startListening(on: OfflineRetrier.monitorQueue, onResult: onResult)
    }

    fileprivate mutating func cleanupMonitor() {
        pendingCompletions.removeAll()
        timeoutWorkItem?.cancel()
        timeoutWorkItem = nil
        currentMonitor?.stopListening()
        currentMonitor = nil
    }
}

@available(macOS 10.14, iOS 12, tvOS 12, watchOS 5, visionOS 1, *)
extension RequestInterceptor where Self == OfflineRetrier {
    public static func offlineRetrier(
        monitor: @autoclosure @escaping () -> NWPathMonitor = NWPathMonitor(),
        maximumWait: DispatchTimeInterval = OfflineRetrier.defaultWait,
        isOfflineError: @escaping @Sendable (_ error: any Error) -> Bool = OfflineRetrier.defaultIsOfflineError
    ) -> OfflineRetrier {
        OfflineRetrier(monitor: monitor(), maximumWait: maximumWait, isOfflineError: isOfflineError)
    }

    public static func offlineRetrier(
        requiredInterfaceType: NWInterface.InterfaceType,
        maximumWait: DispatchTimeInterval = OfflineRetrier.defaultWait,
        isOfflineError: @escaping @Sendable (_ error: any Error) -> Bool = OfflineRetrier.defaultIsOfflineError
    ) -> OfflineRetrier {
        OfflineRetrier(requiredInterfaceType: requiredInterfaceType, maximumWait: maximumWait, isOfflineError: isOfflineError)
    }

    @available(macOS 11, iOS 14, tvOS 14, watchOS 7, visionOS 1, *)
    public static func offlineRetrier(
        prohibitedInterfaceTypes: [NWInterface.InterfaceType],
        maximumWait: DispatchTimeInterval = OfflineRetrier.defaultWait,
        isOfflineError: @escaping @Sendable (_ error: any Error) -> Bool = OfflineRetrier.defaultIsOfflineError
    ) -> OfflineRetrier {
        OfflineRetrier(prohibitedInterfaceTypes: prohibitedInterfaceTypes, maximumWait: maximumWait, isOfflineError: isOfflineError)
    }

    static func offlineRetrier(
        monitor: @autoclosure @escaping () -> PathMonitor,
        maximumWait: DispatchTimeInterval
    ) -> OfflineRetrier {
        OfflineRetrier(monitor: monitor(), maximumWait: maximumWait)
    }
}

@available(macOS 10.14, iOS 12, tvOS 12, watchOS 5, visionOS 1, *)
struct PathMonitor {
    enum Result {
        case pathAvailable, timeout
    }

    var start: (_ queue: DispatchQueue, _ onResult: @escaping @Sendable (_ result: Result) -> Void) -> Void
    var stop: () -> Void

    func startListening(on queue: DispatchQueue, onResult: @escaping @Sendable (_ result: Result) -> Void) {
        start(queue, onResult)
    }

    func stopListening() {
        stop()
    }
}

@available(macOS 10.14, iOS 12, tvOS 12, watchOS 5, visionOS 1, *)
extension PathMonitor {
    init(_ pathMonitor: NWPathMonitor) {
        start = { queue, onResult in
            pathMonitor.pathUpdateHandler = { path in
                if path.status != .unsatisfied {
                    onResult(.pathAvailable)
                }
            }
            pathMonitor.start(queue: queue)
        }

        stop = {
            pathMonitor.cancel()
            pathMonitor.pathUpdateHandler = nil
        }
    }
}
#endif
