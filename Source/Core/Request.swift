
import Foundation

public class Request: @unchecked Sendable {
    public enum State {
        case initialized
        case resumed
        case suspended
        case cancelled
        case finished

        func canTransitionTo(_ state: State) -> Bool {
            switch (self, state) {
            case (.initialized, _):
                true
            case (_, .initialized), (.cancelled, _), (.finished, _):
                false
            case (.resumed, .cancelled), (.suspended, .cancelled), (.resumed, .suspended), (.suspended, .resumed):
                true
            case (.suspended, .suspended), (.resumed, .resumed):
                false
            case (_, .finished):
                true
            }
        }
    }

    public let id: UUID
    public let underlyingQueue: DispatchQueue
    public let serializationQueue: DispatchQueue
    public var eventMonitor: (any EventMonitor)? {
        mutableState.read(\.eventMonitor)
    }

    public var interceptor: (any RequestInterceptor)? {
        mutableState.read(\.interceptor)
    }

    public let shouldAutomaticallyResume: Bool?
    public private(set) weak var delegate: (any RequestDelegate)?

    struct MutableState {
        var state: State = .initialized
        var uploadProgressHandler: (handler: ProgressHandler, queue: DispatchQueue)?
        var downloadProgressHandler: (handler: ProgressHandler, queue: DispatchQueue)?
        var redirectHandler: (any RedirectHandler)?
        var cachedResponseHandler: (any CachedResponseHandler)?
        var cURLHandler: (queue: DispatchQueue, handler: @Sendable (String) -> Void)?
        var urlRequestHandler: (queue: DispatchQueue, handler: @Sendable (URLRequest) -> Void)?
        var urlSessionTaskHandler: (queue: DispatchQueue, handler: @Sendable (URLSessionTask) -> Void)?
        var responseSerializers: [@Sendable () -> Void] = []
        var responseSerializerCompletions: [@Sendable () -> Void] = []
        var responseSerializerProcessingFinished = false
        var eventMonitor: (any EventMonitor)?
        var interceptor: (any RequestInterceptor)?
        var credential: URLCredential?
        var requests: [URLRequest] = []
        var tasks: [URLSessionTask] = []
        var metrics: [URLSessionTaskMetrics] = []
        var retryCount = 0
        var error: AFError?
        var isFinishing = false
        var finishHandlers: [() -> Void] = []
    }

    let mutableState: Protected<MutableState>

    public var state: State { mutableState.read(\.state) }
    public var isInitialized: Bool { state == .initialized }
    public var isResumed: Bool { state == .resumed }
    public var isSuspended: Bool { state == .suspended }
    public var isCancelled: Bool { state == .cancelled }
    public var isFinished: Bool { state == .finished }

    public typealias ProgressHandler = @Sendable (_ progress: Progress) -> Void

    public let uploadProgress = Progress(totalUnitCount: 0)
    public let downloadProgress = Progress(totalUnitCount: 0)
    public internal(set) var uploadProgressHandler: (handler: ProgressHandler, queue: DispatchQueue)? {
        get { mutableState.read(\.uploadProgressHandler) }
        set { mutableState.write { $0.uploadProgressHandler = newValue } }
    }

    public internal(set) var downloadProgressHandler: (handler: ProgressHandler, queue: DispatchQueue)? {
        get { mutableState.read(\.downloadProgressHandler) }
        set { mutableState.write { $0.downloadProgressHandler = newValue } }
    }

    public internal(set) var redirectHandler: (any RedirectHandler)? {
        get { mutableState.read(\.redirectHandler) }
        set { mutableState.write { $0.redirectHandler = newValue } }
    }

    public internal(set) var cachedResponseHandler: (any CachedResponseHandler)? {
        get { mutableState.read(\.cachedResponseHandler) }
        set { mutableState.write { $0.cachedResponseHandler = newValue } }
    }

    public internal(set) var credential: URLCredential? {
        get { mutableState.read(\.credential) }
        set { mutableState.write { $0.credential = newValue } }
    }

    let validators = Protected<[@Sendable () -> Void]>([])

    public var requests: [URLRequest] { mutableState.read(\.requests) }
    public var firstRequest: URLRequest? { requests.first }
    public var lastRequest: URLRequest? { requests.last }
    public var request: URLRequest? { lastRequest }

    public var performedRequests: [URLRequest] { mutableState.read { $0.tasks.compactMap(\.currentRequest) } }

    public var response: HTTPURLResponse? { lastTask?.response as? HTTPURLResponse }

    public var tasks: [URLSessionTask] { mutableState.read(\.tasks) }
    public var firstTask: URLSessionTask? { tasks.first }
    public var lastTask: URLSessionTask? { tasks.last }
    public var task: URLSessionTask? { lastTask }

    public var allMetrics: [URLSessionTaskMetrics] { mutableState.read(\.metrics) }
    public var firstMetrics: URLSessionTaskMetrics? { allMetrics.first }
    public var lastMetrics: URLSessionTaskMetrics? { allMetrics.last }
    public var metrics: URLSessionTaskMetrics? { lastMetrics }

    public var retryCount: Int { mutableState.read(\.retryCount) }

    public internal(set) var error: AFError? {
        get { mutableState.read(\.error) }
        set { mutableState.write { $0.error = newValue } }
    }

    init(id: UUID = UUID(),
         underlyingQueue: DispatchQueue,
         serializationQueue: DispatchQueue,
         eventMonitor: (any EventMonitor)?,
         interceptor: (any RequestInterceptor)?,
         shouldAutomaticallyResume: Bool?,
         delegate: any RequestDelegate) {
        self.id = id
        self.underlyingQueue = underlyingQueue
        self.serializationQueue = serializationQueue
        mutableState = Protected(MutableState(eventMonitor: eventMonitor,
                                              interceptor: interceptor))
        self.shouldAutomaticallyResume = shouldAutomaticallyResume
        self.delegate = delegate
    }

    func didCreateInitialURLRequest(_ request: URLRequest) {
        dispatchPrecondition(condition: .onQueue(underlyingQueue))

        mutableState.write { $0.requests.append(request) }

        eventMonitor?.request(self, didCreateInitialURLRequest: request)
    }

    func didFailToCreateURLRequest(with error: AFError) {
        dispatchPrecondition(condition: .onQueue(underlyingQueue))

        self.error = error

        eventMonitor?.request(self, didFailToCreateURLRequestWithError: error)

        callCURLHandlerIfNecessary()

        retryOrFinish(error: error)
    }

    func didAdaptInitialRequest(_ initialRequest: URLRequest, to adaptedRequest: URLRequest) {
        dispatchPrecondition(condition: .onQueue(underlyingQueue))

        mutableState.write { $0.requests.append(adaptedRequest) }

        eventMonitor?.request(self, didAdaptInitialRequest: initialRequest, to: adaptedRequest)
    }

    func didFailToAdaptURLRequest(_ request: URLRequest, withError error: AFError) {
        dispatchPrecondition(condition: .onQueue(underlyingQueue))

        self.error = error

        eventMonitor?.request(self, didFailToAdaptURLRequest: request, withError: error)

        callCURLHandlerIfNecessary()

        retryOrFinish(error: error)
    }

    func didCreateURLRequest(_ request: URLRequest) {
        dispatchPrecondition(condition: .onQueue(underlyingQueue))

        mutableState.read { state in
            guard let urlRequestHandler = state.urlRequestHandler else { return }

            urlRequestHandler.queue.async { urlRequestHandler.handler(request) }
        }

        eventMonitor?.request(self, didCreateURLRequest: request)

        callCURLHandlerIfNecessary()
    }

    private func callCURLHandlerIfNecessary() {
        mutableState.write { mutableState in
            guard let cURLHandler = mutableState.cURLHandler else { return }

            cURLHandler.queue.async { cURLHandler.handler(self.cURLDescription()) }

            mutableState.cURLHandler = nil
        }
    }

    func didCreateTask(_ task: URLSessionTask) {
        dispatchPrecondition(condition: .onQueue(underlyingQueue))

        mutableState.write { state in
            state.tasks.append(task)

            guard let urlSessionTaskHandler = state.urlSessionTaskHandler else { return }

            urlSessionTaskHandler.queue.async { urlSessionTaskHandler.handler(task) }
        }

        eventMonitor?.request(self, didCreateTask: task)
    }

    func didResume() {
        dispatchPrecondition(condition: .onQueue(underlyingQueue))

        eventMonitor?.requestDidResume(self)
    }

    func didResumeTask(_ task: URLSessionTask) {
        dispatchPrecondition(condition: .onQueue(underlyingQueue))

        eventMonitor?.request(self, didResumeTask: task)
    }

    func didSuspend() {
        dispatchPrecondition(condition: .onQueue(underlyingQueue))

        eventMonitor?.requestDidSuspend(self)
    }

    func didSuspendTask(_ task: URLSessionTask) {
        dispatchPrecondition(condition: .onQueue(underlyingQueue))

        eventMonitor?.request(self, didSuspendTask: task)
    }

    func didCancel() {
        dispatchPrecondition(condition: .onQueue(underlyingQueue))

        mutableState.write { mutableState in
            mutableState.error = mutableState.error ?? AFError.explicitlyCancelled
        }

        eventMonitor?.requestDidCancel(self)
    }

    func didCancelTask(_ task: URLSessionTask) {
        dispatchPrecondition(condition: .onQueue(underlyingQueue))

        eventMonitor?.request(self, didCancelTask: task)
    }

    func didGatherMetrics(_ metrics: URLSessionTaskMetrics) {
        dispatchPrecondition(condition: .onQueue(underlyingQueue))

        mutableState.write { $0.metrics.append(metrics) }

        eventMonitor?.request(self, didGatherMetrics: metrics)
    }

    func didFailTask(_ task: URLSessionTask, earlyWithError error: AFError) {
        dispatchPrecondition(condition: .onQueue(underlyingQueue))

        self.error = error

        eventMonitor?.request(self, didFailTask: task, earlyWithError: error)
    }

    func didCompleteTask(_ task: URLSessionTask, with error: AFError?) {
        dispatchPrecondition(condition: .onQueue(underlyingQueue))

        mutableState.write { $0.error = $0.error ?? error }

        let validators = validators.read(\.self)
        validators.forEach { $0() }

        eventMonitor?.request(self, didCompleteTask: task, with: error)

        retryOrFinish(error: self.error)
    }

    func prepareForRetry() {
        dispatchPrecondition(condition: .onQueue(underlyingQueue))

        mutableState.write { $0.retryCount += 1 }

        reset()

        eventMonitor?.requestIsRetrying(self)
    }

    func retryOrFinish(error: AFError?) {
        dispatchPrecondition(condition: .onQueue(underlyingQueue))

        guard !isCancelled, let error, let delegate else { finish(); return }

        delegate.retryResult(for: self, dueTo: error) { retryResult in
            switch retryResult {
            case .doNotRetry:
                self.finish()
            case let .doNotRetryWithError(retryError):
                self.finish(error: retryError.asAFError(orFailWith: "Received retryError was not already AFError"))
            case .retry, .retryWithDelay:
                delegate.retryRequest(self, withDelay: retryResult.delay)
            }
        }
    }

    func finish(error: AFError? = nil) {
        dispatchPrecondition(condition: .onQueue(underlyingQueue))

        let shouldStartResponseSerializers = mutableState.write { mutableState in
            guard !mutableState.isFinishing else { return false }

            mutableState.isFinishing = true

            if let error { mutableState.error = error }

            return true
        }

        guard shouldStartResponseSerializers else { return }

        processNextResponseSerializer()

        eventMonitor?.requestDidFinish(self)
    }

    func appendResponseSerializer(_ closure: @escaping @Sendable () -> Void) {
        mutableState.write { mutableState in
            mutableState.responseSerializers.append(closure)

            if mutableState.state == .finished {
                mutableState.state = .resumed
            }

            if mutableState.responseSerializerProcessingFinished {
                underlyingQueue.async { self.processNextResponseSerializer() }
            }

            if mutableState.state.canTransitionTo(.resumed) {
                underlyingQueue.async { [self] in
                    if (shouldAutomaticallyResume ?? delegate?.startImmediately) == true {
                        resume()
                    }
                }
            }
        }
    }

    func processNextResponseSerializer() {
        let executeOutside: () -> Void = mutableState.write { mutableState in
            let responseSerializerIndex = mutableState.responseSerializerCompletions.count
            let isAvailableSerializer = responseSerializerIndex < mutableState.responseSerializers.count
            let responseSerializer = isAvailableSerializer ? mutableState.responseSerializers[responseSerializerIndex] : nil

            if let responseSerializer {
                return { self.serializationQueue.async { responseSerializer() } }
            } else {
                let completions = mutableState.responseSerializerCompletions
                mutableState.responseSerializers.removeAll()
                mutableState.responseSerializerCompletions.removeAll()

                if mutableState.state.canTransitionTo(.finished) {
                    mutableState.state = .finished
                }

                mutableState.responseSerializerProcessingFinished = true
                mutableState.isFinishing = false

                return {
                    completions.forEach { $0() }

                    self.cleanup()
                }
            }
        }

        executeOutside()
    }

    func responseSerializerDidComplete(completion: @escaping @Sendable () -> Void) {
        mutableState.write { $0.responseSerializerCompletions.append(completion) }
        processNextResponseSerializer()
    }

    func reset() {
        uploadProgress.totalUnitCount = 0
        uploadProgress.completedUnitCount = 0
        downloadProgress.totalUnitCount = 0
        downloadProgress.completedUnitCount = 0

        mutableState.write { mutableState in
            mutableState.error = nil
            mutableState.isFinishing = false
            mutableState.responseSerializerCompletions = []
        }
    }

    func updateUploadProgress(totalBytesSent: Int64, totalBytesExpectedToSend: Int64) {
        uploadProgress.totalUnitCount = totalBytesExpectedToSend
        uploadProgress.completedUnitCount = totalBytesSent

        uploadProgressHandler?.queue.async { self.uploadProgressHandler?.handler(self.uploadProgress) }
    }

    func withState(perform: (State) -> Void) {
        mutableState.withState(perform: perform)
    }

    func task(for request: URLRequest, using session: URLSession) -> URLSessionTask {
        fatalError("Subclasses must override.")
    }

    @discardableResult
    public func cancel() -> Self {
        mutableState.write { mutableState in
            guard mutableState.state.canTransitionTo(.cancelled) else { return }

            mutableState.state = .cancelled

            underlyingQueue.async { self.didCancel() }

            guard let task = mutableState.tasks.last, task.state != .completed else {
                underlyingQueue.async { self.finish() }
                return
            }

            task.resume()
            task.cancel()
            underlyingQueue.async { self.didCancelTask(task) }
        }

        return self
    }

    @discardableResult
    public func suspend() -> Self {
        mutableState.write { mutableState in
            guard mutableState.state.canTransitionTo(.suspended) else { return }

            mutableState.state = .suspended

            underlyingQueue.async { self.didSuspend() }

            guard let task = mutableState.tasks.last, task.state != .completed else { return }

            task.suspend()
            underlyingQueue.async { self.didSuspendTask(task) }
        }

        return self
    }

    @discardableResult
    public func resume() -> Self {
        let needsToPerform = mutableState.write { mutableState in
            guard mutableState.state.canTransitionTo(.resumed) else { return false }

            mutableState.state = .resumed

            underlyingQueue.async { self.didResume() }

            guard let task = mutableState.tasks.last, task.state != .completed else { return true }

            task.resume()
            underlyingQueue.async { self.didResumeTask(task) }
            return true
        }

        if needsToPerform {
            delegate?.readyToPerform(request: self)
        }

        return self
    }

    @discardableResult
    public func authenticate(username: String, password: String, persistence: URLCredential.Persistence = .forSession) -> Self {
        let credential = URLCredential(user: username, password: password, persistence: persistence)

        return authenticate(with: credential)
    }

    @discardableResult
    public func authenticate(with credential: URLCredential) -> Self {
        self.credential = credential

        return self
    }

    @preconcurrency
    @discardableResult
    public func downloadProgress(queue: DispatchQueue = .main, closure: @escaping ProgressHandler) -> Self {
        downloadProgressHandler = (handler: closure, queue: queue)

        return self
    }

    @preconcurrency
    @discardableResult
    public func uploadProgress(queue: DispatchQueue = .main, closure: @escaping ProgressHandler) -> Self {
        uploadProgressHandler = (handler: closure, queue: queue)

        return self
    }

    @preconcurrency
    @discardableResult
    public func redirect(using handler: any RedirectHandler) -> Self {
        mutableState.write { mutableState in
            precondition(mutableState.redirectHandler == nil, "Redirect handler has already been set.")
            mutableState.redirectHandler = handler
        }

        return self
    }

    @preconcurrency
    @discardableResult
    public func cacheResponse(using handler: any CachedResponseHandler) -> Self {
        mutableState.write { mutableState in
            precondition(mutableState.cachedResponseHandler == nil, "Cached response handler has already been set.")
            mutableState.cachedResponseHandler = handler
        }

        return self
    }

    @preconcurrency
    @discardableResult
    public func cURLDescription(on queue: DispatchQueue, calling handler: @escaping @Sendable (String) -> Void) -> Self {
        mutableState.write { mutableState in
            if mutableState.requests.last != nil {
                queue.async { handler(self.cURLDescription()) }
            } else {
                mutableState.cURLHandler = (queue, handler)
            }
        }

        return self
    }

    @preconcurrency
    @discardableResult
    public func cURLDescription(calling handler: @escaping @Sendable (String) -> Void) -> Self {
        cURLDescription(on: underlyingQueue, calling: handler)

        return self
    }

    @preconcurrency
    @discardableResult
    public func onURLRequestCreation(on queue: DispatchQueue = .main, perform handler: @escaping @Sendable (URLRequest) -> Void) -> Self {
        mutableState.write { state in
            if let request = state.requests.last {
                queue.async { handler(request) }
            }

            state.urlRequestHandler = (queue, handler)
        }

        return self
    }

    @preconcurrency
    @discardableResult
    public func onURLSessionTaskCreation(on queue: DispatchQueue = .main, perform handler: @escaping @Sendable (URLSessionTask) -> Void) -> Self {
        mutableState.write { state in
            if let task = state.tasks.last {
                queue.async { handler(task) }
            }

            state.urlSessionTaskHandler = (queue, handler)
        }

        return self
    }

    @preconcurrency
    @discardableResult
    public func interceptor(_ interceptor: any RequestInterceptor) -> Self {
        mutableState.write { mutableState in
            if let existingInterceptor = mutableState.interceptor {
                if let existingInterceptor = existingInterceptor as? Interceptor {
                    mutableState.interceptor = Interceptor(adapters: existingInterceptor.adapters,
                                                           retriers: existingInterceptor.retriers,
                                                           interceptors: [interceptor])
                } else {
                    mutableState.interceptor = Interceptor(interceptors: [existingInterceptor, interceptor])
                }
            } else {
                mutableState.interceptor = Interceptor(interceptors: [interceptor])
            }
        }

        return self
    }

    @preconcurrency
    @discardableResult
    public func adapt(using adapter: any RequestAdapter) -> Self {
        mutableState.write { mutableState in
            if let existingInterceptor = mutableState.interceptor {
                if let existingInterceptor = existingInterceptor as? Interceptor {
                    mutableState.interceptor = Interceptor(adapters: existingInterceptor.adapters + [adapter],
                                                           retriers: existingInterceptor.retriers)
                } else {
                    mutableState.interceptor = Interceptor(adapters: [adapter], interceptors: [existingInterceptor])
                }
            } else {
                mutableState.interceptor = Interceptor(adapters: [adapter])
            }
        }

        return self
    }

    @preconcurrency
    @discardableResult
    public func retry(using retrier: any RequestRetrier) -> Self {
        mutableState.write { mutableState in
            if let existingInterceptor = mutableState.interceptor {
                if let existingInterceptor = existingInterceptor as? Interceptor {
                    mutableState.interceptor = Interceptor(adapters: existingInterceptor.adapters,
                                                           retriers: existingInterceptor.retriers + [retrier])
                } else {
                    mutableState.interceptor = Interceptor(retriers: [retrier], interceptors: [existingInterceptor])
                }
            } else {
                mutableState.interceptor = Interceptor(retriers: [retrier])
            }
        }

        return self
    }

    @preconcurrency
    @discardableResult
    public func eventMonitor(_ eventMonitor: any EventMonitor) -> Self {
        mutableState.write { mutableState in
            if let existingMonitor = mutableState.eventMonitor {
                if let existingMonitor = existingMonitor as? CompositeEventMonitor {
                    mutableState.eventMonitor = CompositeEventMonitor(queue: existingMonitor.queue,
                                                                      monitors: existingMonitor.monitors + [eventMonitor])
                } else {
                    mutableState.eventMonitor = CompositeEventMonitor(queue: underlyingQueue,
                                                                      monitors: [existingMonitor, eventMonitor])
                }
            } else {
                mutableState.eventMonitor = CompositeEventMonitor(queue: underlyingQueue, monitors: [eventMonitor])
            }
        }

        return self
    }

    func onFinish(perform finishHandler: @escaping () -> Void) {
        let shouldImmediatelyExecute = mutableState.write { mutableState in
            if mutableState.state == .finished {
                return true
            } else {
                mutableState.finishHandlers.append(finishHandler)
                return false
            }
        }

        if shouldImmediatelyExecute {
            finishHandler()
        }
    }

    func cleanup() {
        let finishHandlers = mutableState.write { mutableState in
            let handlers = mutableState.finishHandlers
            mutableState.finishHandlers.removeAll()
            return handlers
        }
        finishHandlers.forEach { $0() }

        delegate?.cleanup(after: self)
    }
}

extension Request {
    public enum ResponseDisposition: Sendable {
        case allow
        case cancel

        var sessionDisposition: URLSession.ResponseDisposition {
            switch self {
            case .allow: .allow
            case .cancel: .cancel
            }
        }
    }
}

extension Request: Equatable {
    public static func ==(lhs: Request, rhs: Request) -> Bool {
        lhs.id == rhs.id
    }
}

extension Request: Hashable {
    public func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

extension Request: CustomStringConvertible {
    public var description: String {
        guard let request = performedRequests.last ?? lastRequest,
              let url = request.url,
              let method = request.httpMethod else { return "No request created yet." }

        let requestDescription = "\(method) \(url.absoluteString)"

        return response.map { "\(requestDescription) (\($0.statusCode))" } ?? requestDescription
    }
}

extension Request {
    public func cURLDescription() -> String {
        guard
            let request = lastRequest,
            let url = request.url,
            let host = url.host,
            let method = request.httpMethod else { return "$ curl command could not be created" }

        var components = ["$ curl -v"]

        components.append("-X \(method)")

        if let credentialStorage = delegate?.sessionConfiguration.urlCredentialStorage {
            let protectionSpace = URLProtectionSpace(host: host,
                                                     port: url.port ?? 0,
                                                     protocol: url.scheme,
                                                     realm: host,
                                                     authenticationMethod: NSURLAuthenticationMethodHTTPBasic)

            if let credentials = credentialStorage.credentials(for: protectionSpace)?.values {
                for credential in credentials {
                    guard let user = credential.user, let password = credential.password else { continue }
                    components.append("-u \(user):\(password)")
                }
            } else {
                if let credential, let user = credential.user, let password = credential.password {
                    components.append("-u \(user):\(password)")
                }
            }
        }

        if let configuration = delegate?.sessionConfiguration, configuration.httpShouldSetCookies {
            if
                let cookieStorage = configuration.httpCookieStorage,
                let cookies = cookieStorage.cookies(for: url), !cookies.isEmpty {
                let allCookies = cookies.map { "\($0.name)=\($0.value)" }.joined(separator: ";")

                components.append("-b \"\(allCookies)\"")
            }
        }

        var headers = HTTPHeaders()

        if let sessionHeaders = delegate?.sessionConfiguration.headers {
            for header in sessionHeaders where header.name != "Cookie" {
                headers[header.name] = header.value
            }
        }

        for header in request.headers where header.name != "Cookie" {
            headers[header.name] = header.value
        }

        for header in headers {
            let escapedValue = header.value.replacingOccurrences(of: "\"", with: "\\\"")
            components.append("-H \"\(header.name): \(escapedValue)\"")
        }

        if let httpBodyData = request.httpBody {
            let httpBody = String(decoding: httpBodyData, as: UTF8.self)
            var escapedBody = httpBody.replacingOccurrences(of: "\\\"", with: "\\\\\"")
            escapedBody = escapedBody.replacingOccurrences(of: "\"", with: "\\\"")

            components.append("-d \"\(escapedBody)\"")
        }

        components.append("\"\(url.absoluteString)\"")

        return components.joined(separator: " \\\n\t")
    }
}

public protocol RequestDelegate: AnyObject, Sendable {
    var sessionConfiguration: URLSessionConfiguration { get }

    var startImmediately: Bool { get }

    func readyToPerform(request: Request)

    func cleanup(after request: Request)

    func retryResult(for request: Request, dueTo error: AFError, completion: @escaping @Sendable (RetryResult) -> Void)

    func retryRequest(_ request: Request, withDelay timeDelay: TimeInterval?)
}
