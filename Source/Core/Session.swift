
import Foundation

open class Session: @unchecked Sendable {
    public static let `default` = Session()

    public enum RequestSetup {
        case lazy
        case eager
    }

    public let session: URLSession
    public let delegate: SessionDelegate
    public let rootQueue: DispatchQueue
    public let startRequestsImmediately: Bool
    public let requestSetup: RequestSetup
    public let requestQueue: DispatchQueue
    public let serializationQueue: DispatchQueue
    public let interceptor: (any RequestInterceptor)?
    public let serverTrustManager: ServerTrustManager?
    public let redirectHandler: (any RedirectHandler)?
    public let cachedResponseHandler: (any CachedResponseHandler)?
    public let eventMonitor: CompositeEventMonitor
    @available(*, deprecated, message: "Use [AlamofireNotifications()] directly.")
    public let defaultEventMonitors: [any EventMonitor] = [AlamofireNotifications()]

    var requestTaskMap = RequestTaskMap()
    var activeRequests: Set<Request> = []
    var waitingCompletions: [URLSessionTask: () -> Void] = [:]

    public init(session: URLSession,
                delegate: SessionDelegate,
                rootQueue: DispatchQueue,
                startRequestsImmediately: Bool = true,
                requestSetup: RequestSetup = .lazy,
                requestQueue: DispatchQueue? = nil,
                serializationQueue: DispatchQueue? = nil,
                interceptor: (any RequestInterceptor)? = nil,
                serverTrustManager: ServerTrustManager? = nil,
                redirectHandler: (any RedirectHandler)? = nil,
                cachedResponseHandler: (any CachedResponseHandler)? = nil,
                eventMonitors: [any EventMonitor] = [AlamofireNotifications()]) {
        precondition(session.configuration.identifier == nil,
                     "Alamofire does not support background URLSessionConfigurations.")
        precondition(session.delegateQueue.underlyingQueue === rootQueue,
                     "Session(session:) initializer must be passed the DispatchQueue used as the delegateQueue's underlyingQueue as rootQueue.")

        self.session = session
        self.delegate = delegate
        self.rootQueue = rootQueue
        self.startRequestsImmediately = startRequestsImmediately
        self.requestSetup = requestSetup
        self.requestQueue = requestQueue ?? DispatchQueue(label: "\(rootQueue.label).requestQueue", target: rootQueue)
        self.serializationQueue = serializationQueue ?? DispatchQueue(label: "\(rootQueue.label).serializationQueue", target: rootQueue)
        self.interceptor = interceptor
        self.serverTrustManager = serverTrustManager
        self.redirectHandler = redirectHandler
        self.cachedResponseHandler = cachedResponseHandler
        eventMonitor = CompositeEventMonitor(queue: rootQueue, monitors: eventMonitors)
        delegate.eventMonitor = eventMonitor
        delegate.stateProvider = self
    }

    public convenience init(configuration: URLSessionConfiguration = URLSessionConfiguration.af.default,
                            delegate: SessionDelegate = SessionDelegate(),
                            rootQueue: DispatchQueue = DispatchQueue(label: "org.alamofire.session.rootQueue"),
                            startRequestsImmediately: Bool = true,
                            requestSetup: RequestSetup = .lazy,
                            requestQueue: DispatchQueue? = nil,
                            serializationQueue: DispatchQueue? = nil,
                            interceptor: (any RequestInterceptor)? = nil,
                            serverTrustManager: ServerTrustManager? = nil,
                            redirectHandler: (any RedirectHandler)? = nil,
                            cachedResponseHandler: (any CachedResponseHandler)? = nil,
                            eventMonitors: [any EventMonitor] = [AlamofireNotifications()]) {
        precondition(configuration.identifier == nil, "Alamofire does not support background URLSessionConfigurations.")

        let serialRootQueue = (rootQueue === DispatchQueue.main) ? rootQueue : DispatchQueue(label: rootQueue.label,
                                                                                             target: rootQueue)
        let delegateQueue = OperationQueue(maxConcurrentOperationCount: 1, underlyingQueue: serialRootQueue, name: "\(serialRootQueue.label).sessionDelegate")
        let session = URLSession(configuration: configuration, delegate: delegate, delegateQueue: delegateQueue)

        self.init(session: session,
                  delegate: delegate,
                  rootQueue: serialRootQueue,
                  startRequestsImmediately: startRequestsImmediately,
                  requestSetup: requestSetup,
                  requestQueue: requestQueue,
                  serializationQueue: serializationQueue,
                  interceptor: interceptor,
                  serverTrustManager: serverTrustManager,
                  redirectHandler: redirectHandler,
                  cachedResponseHandler: cachedResponseHandler,
                  eventMonitors: eventMonitors)
    }

    deinit {
        finishRequestsForDeinit()
        session.invalidateAndCancel()
    }

    public func withAllRequests(perform action: @escaping @Sendable (Set<Request>) -> Void) {
        rootQueue.async {
            action(self.activeRequests)
        }
    }

    public func cancelAllRequests(completingOnQueue queue: DispatchQueue = .main, completion: (@Sendable () -> Void)? = nil) {
        withAllRequests { requests in
            requests.forEach { $0.cancel() }
            queue.async {
                completion?()
            }
        }
    }

    public typealias RequestModifier = @Sendable (inout URLRequest) throws -> Void

    struct RequestConvertible: URLRequestConvertible {
        let url: any URLConvertible
        let method: HTTPMethod
        let parameters: Parameters?
        let encoding: any ParameterEncoding
        let headers: HTTPHeaders?
        let requestModifier: RequestModifier?

        func asURLRequest() throws -> URLRequest {
            var request = try URLRequest(url: url, method: method, headers: headers)
            try requestModifier?(&request)

            return try encoding.encode(request, with: parameters)
        }
    }

    open func request(_ convertible: any URLConvertible,
                      method: HTTPMethod = .get,
                      parameters: Parameters? = nil,
                      encoding: any ParameterEncoding = URLEncoding.default,
                      headers: HTTPHeaders? = nil,
                      interceptor: (any RequestInterceptor)? = nil,
                      shouldAutomaticallyResume: Bool? = nil,
                      requestModifier: RequestModifier? = nil) -> DataRequest {
        let convertible = RequestConvertible(url: convertible,
                                             method: method,
                                             parameters: parameters,
                                             encoding: encoding,
                                             headers: headers,
                                             requestModifier: requestModifier)

        return request(convertible, interceptor: interceptor, shouldAutomaticallyResume: shouldAutomaticallyResume)
    }

    struct RequestEncodableConvertible<Parameters: Encodable & Sendable>: URLRequestConvertible {
        let url: any URLConvertible
        let method: HTTPMethod
        let parameters: Parameters?
        let encoder: any ParameterEncoder
        let headers: HTTPHeaders?
        let requestModifier: RequestModifier?

        func asURLRequest() throws -> URLRequest {
            var request = try URLRequest(url: url, method: method, headers: headers)
            try requestModifier?(&request)

            return try parameters.map { try encoder.encode($0, into: request) } ?? request
        }
    }

    open func request<Parameters: Encodable & Sendable>(_ convertible: any URLConvertible,
                                                        method: HTTPMethod = .get,
                                                        parameters: Parameters? = nil,
                                                        encoder: any ParameterEncoder = URLEncodedFormParameterEncoder.default,
                                                        headers: HTTPHeaders? = nil,
                                                        interceptor: (any RequestInterceptor)? = nil,
                                                        shouldAutomaticallyResume: Bool? = nil,
                                                        requestModifier: RequestModifier? = nil) -> DataRequest {
        let convertible = RequestEncodableConvertible(url: convertible,
                                                      method: method,
                                                      parameters: parameters,
                                                      encoder: encoder,
                                                      headers: headers,
                                                      requestModifier: requestModifier)

        return request(convertible, interceptor: interceptor, shouldAutomaticallyResume: shouldAutomaticallyResume)
    }

    open func request(_ convertible: any URLRequestConvertible,
                      interceptor: (any RequestInterceptor)? = nil,
                      shouldAutomaticallyResume: Bool? = nil) -> DataRequest {
        let request = DataRequest(convertible: convertible,
                                  underlyingQueue: rootQueue,
                                  serializationQueue: serializationQueue,
                                  eventMonitor: eventMonitor,
                                  interceptor: interceptor,
                                  shouldAutomaticallyResume: shouldAutomaticallyResume,
                                  delegate: self)

        performEagerlyIfNecessary(request)

        return request
    }

    open func streamRequest<Parameters: Encodable & Sendable>(_ convertible: any URLConvertible,
                                                              method: HTTPMethod = .get,
                                                              parameters: Parameters? = nil,
                                                              encoder: any ParameterEncoder = URLEncodedFormParameterEncoder.default,
                                                              headers: HTTPHeaders? = nil,
                                                              automaticallyCancelOnStreamError: Bool = false,
                                                              interceptor: (any RequestInterceptor)? = nil,
                                                              shouldAutomaticallyResume: Bool? = nil,
                                                              requestModifier: RequestModifier? = nil) -> DataStreamRequest {
        let convertible = RequestEncodableConvertible(url: convertible,
                                                      method: method,
                                                      parameters: parameters,
                                                      encoder: encoder,
                                                      headers: headers,
                                                      requestModifier: requestModifier)

        return streamRequest(convertible,
                             automaticallyCancelOnStreamError: automaticallyCancelOnStreamError,
                             interceptor: interceptor,
                             shouldAutomaticallyResume: shouldAutomaticallyResume)
    }

    open func streamRequest(_ convertible: any URLConvertible,
                            method: HTTPMethod = .get,
                            headers: HTTPHeaders? = nil,
                            automaticallyCancelOnStreamError: Bool = false,
                            interceptor: (any RequestInterceptor)? = nil,
                            shouldAutomaticallyResume: Bool? = nil,
                            requestModifier: RequestModifier? = nil) -> DataStreamRequest {
        let convertible = RequestEncodableConvertible(url: convertible,
                                                      method: method,
                                                      parameters: Empty?.none,
                                                      encoder: URLEncodedFormParameterEncoder.default,
                                                      headers: headers,
                                                      requestModifier: requestModifier)

        return streamRequest(convertible,
                             automaticallyCancelOnStreamError: automaticallyCancelOnStreamError,
                             interceptor: interceptor,
                             shouldAutomaticallyResume: shouldAutomaticallyResume)
    }

    open func streamRequest(_ convertible: any URLRequestConvertible,
                            automaticallyCancelOnStreamError: Bool = false,
                            interceptor: (any RequestInterceptor)? = nil,
                            shouldAutomaticallyResume: Bool? = nil) -> DataStreamRequest {
        let request = DataStreamRequest(convertible: convertible,
                                        automaticallyCancelOnStreamError: automaticallyCancelOnStreamError,
                                        underlyingQueue: rootQueue,
                                        serializationQueue: serializationQueue,
                                        eventMonitor: eventMonitor,
                                        interceptor: interceptor,
                                        shouldAutomaticallyResume: shouldAutomaticallyResume,
                                        delegate: self)

        performEagerlyIfNecessary(request)

        return request
    }

    #if canImport(Darwin) && !canImport(FoundationNetworking)
    @available(macOS 10.15, iOS 13, tvOS 13, watchOS 6, *)
    @_spi(WebSocket) open func webSocketRequest(
        to url: any URLConvertible,
        configuration: WebSocketRequest.Configuration = .default,
        headers: HTTPHeaders? = nil,
        interceptor: (any RequestInterceptor)? = nil,
        shouldAutomaticallyResume: Bool? = nil,
        requestModifier: RequestModifier? = nil
    ) -> WebSocketRequest {
        webSocketRequest(
            to: url,
            configuration: configuration,
            parameters: Empty?.none,
            encoder: URLEncodedFormParameterEncoder.default,
            headers: headers,
            interceptor: interceptor,
            requestModifier: requestModifier
        )
    }

    @available(macOS 10.15, iOS 13, tvOS 13, watchOS 6, *)
    @_spi(WebSocket) open func webSocketRequest<Parameters>(
        to url: any URLConvertible,
        configuration: WebSocketRequest.Configuration = .default,
        parameters: Parameters? = nil,
        encoder: any ParameterEncoder = URLEncodedFormParameterEncoder.default,
        headers: HTTPHeaders? = nil,
        interceptor: (any RequestInterceptor)? = nil,
        shouldAutomaticallyResume: Bool? = nil,
        requestModifier: RequestModifier? = nil
    ) -> WebSocketRequest where Parameters: Encodable & Sendable {
        let convertible = RequestEncodableConvertible(url: url,
                                                      method: .get,
                                                      parameters: parameters,
                                                      encoder: encoder,
                                                      headers: headers,
                                                      requestModifier: requestModifier)
        let request = WebSocketRequest(convertible: convertible,
                                       configuration: configuration,
                                       underlyingQueue: rootQueue,
                                       serializationQueue: serializationQueue,
                                       eventMonitor: eventMonitor,
                                       interceptor: interceptor,
                                       shouldAutomaticallyResume: shouldAutomaticallyResume,
                                       delegate: self)

        performEagerlyIfNecessary(request)

        return request
    }

    @available(macOS 10.15, iOS 13, tvOS 13, watchOS 6, *)
    @_spi(WebSocket) open func webSocketRequest(performing convertible: any URLRequestConvertible,
                                                configuration: WebSocketRequest.Configuration = .default,
                                                interceptor: (any RequestInterceptor)? = nil,
                                                shouldAutomaticallyResume: Bool? = nil) -> WebSocketRequest {
        let request = WebSocketRequest(convertible: convertible,
                                       configuration: configuration,
                                       underlyingQueue: rootQueue,
                                       serializationQueue: serializationQueue,
                                       eventMonitor: eventMonitor,
                                       interceptor: interceptor,
                                       shouldAutomaticallyResume: shouldAutomaticallyResume,
                                       delegate: self)

        performEagerlyIfNecessary(request)

        return request
    }
    #endif

    open func download(_ convertible: any URLConvertible,
                       method: HTTPMethod = .get,
                       parameters: Parameters? = nil,
                       encoding: any ParameterEncoding = URLEncoding.default,
                       headers: HTTPHeaders? = nil,
                       interceptor: (any RequestInterceptor)? = nil,
                       shouldAutomaticallyResume: Bool? = nil,
                       requestModifier: RequestModifier? = nil,
                       to destination: DownloadRequest.Destination? = nil) -> DownloadRequest {
        let convertible = RequestConvertible(url: convertible,
                                             method: method,
                                             parameters: parameters,
                                             encoding: encoding,
                                             headers: headers,
                                             requestModifier: requestModifier)

        return download(convertible, interceptor: interceptor, shouldAutomaticallyResume: shouldAutomaticallyResume, to: destination)
    }

    open func download<Parameters: Encodable & Sendable>(_ convertible: any URLConvertible,
                                                         method: HTTPMethod = .get,
                                                         parameters: Parameters? = nil,
                                                         encoder: any ParameterEncoder = URLEncodedFormParameterEncoder.default,
                                                         headers: HTTPHeaders? = nil,
                                                         interceptor: (any RequestInterceptor)? = nil,
                                                         shouldAutomaticallyResume: Bool? = nil,
                                                         requestModifier: RequestModifier? = nil,
                                                         to destination: DownloadRequest.Destination? = nil) -> DownloadRequest {
        let convertible = RequestEncodableConvertible(url: convertible,
                                                      method: method,
                                                      parameters: parameters,
                                                      encoder: encoder,
                                                      headers: headers,
                                                      requestModifier: requestModifier)

        return download(convertible, interceptor: interceptor, shouldAutomaticallyResume: shouldAutomaticallyResume, to: destination)
    }

    open func download(_ convertible: any URLRequestConvertible,
                       interceptor: (any RequestInterceptor)? = nil,
                       shouldAutomaticallyResume: Bool? = nil,
                       to destination: DownloadRequest.Destination? = nil) -> DownloadRequest {
        let request = DownloadRequest(downloadable: .request(convertible),
                                      underlyingQueue: rootQueue,
                                      serializationQueue: serializationQueue,
                                      eventMonitor: eventMonitor,
                                      interceptor: interceptor,
                                      shouldAutomaticallyResume: shouldAutomaticallyResume,
                                      delegate: self,
                                      destination: destination ?? DownloadRequest.defaultDestination)

        performEagerlyIfNecessary(request)

        return request
    }

    open func download(resumingWith data: Data,
                       interceptor: (any RequestInterceptor)? = nil,
                       shouldAutomaticallyResume: Bool? = nil,
                       to destination: DownloadRequest.Destination? = nil) -> DownloadRequest {
        let request = DownloadRequest(downloadable: .resumeData(data),
                                      underlyingQueue: rootQueue,
                                      serializationQueue: serializationQueue,
                                      eventMonitor: eventMonitor,
                                      interceptor: interceptor,
                                      shouldAutomaticallyResume: shouldAutomaticallyResume,
                                      delegate: self,
                                      destination: destination ?? DownloadRequest.defaultDestination)

        performEagerlyIfNecessary(request)

        return request
    }

    struct ParameterlessRequestConvertible: URLRequestConvertible {
        let url: any URLConvertible
        let method: HTTPMethod
        let headers: HTTPHeaders?
        let requestModifier: RequestModifier?

        func asURLRequest() throws -> URLRequest {
            var request = try URLRequest(url: url, method: method, headers: headers)
            try requestModifier?(&request)

            return request
        }
    }

    struct Upload: UploadConvertible {
        let request: any URLRequestConvertible
        let uploadable: any UploadableConvertible

        func createUploadable() throws -> UploadRequest.Uploadable {
            try uploadable.createUploadable()
        }

        func asURLRequest() throws -> URLRequest {
            try request.asURLRequest()
        }
    }

    open func upload(_ data: Data,
                     to convertible: any URLConvertible,
                     method: HTTPMethod = .post,
                     headers: HTTPHeaders? = nil,
                     interceptor: (any RequestInterceptor)? = nil,
                     shouldAutomaticallyResume: Bool? = nil,
                     fileManager: FileManager = .default,
                     requestModifier: RequestModifier? = nil) -> UploadRequest {
        let convertible = ParameterlessRequestConvertible(url: convertible,
                                                          method: method,
                                                          headers: headers,
                                                          requestModifier: requestModifier)

        return upload(data,
                      with: convertible,
                      interceptor: interceptor,
                      shouldAutomaticallyResume: shouldAutomaticallyResume,
                      fileManager: fileManager)
    }

    open func upload(_ data: Data,
                     with convertible: any URLRequestConvertible,
                     interceptor: (any RequestInterceptor)? = nil,
                     shouldAutomaticallyResume: Bool? = nil,
                     fileManager: FileManager = .default) -> UploadRequest {
        upload(.data(data),
               with: convertible,
               interceptor: interceptor,
               shouldAutomaticallyResume: shouldAutomaticallyResume,
               fileManager: fileManager)
    }

    open func upload(_ fileURL: URL,
                     to convertible: any URLConvertible,
                     method: HTTPMethod = .post,
                     headers: HTTPHeaders? = nil,
                     interceptor: (any RequestInterceptor)? = nil,
                     shouldAutomaticallyResume: Bool? = nil,
                     fileManager: FileManager = .default,
                     requestModifier: RequestModifier? = nil) -> UploadRequest {
        let convertible = ParameterlessRequestConvertible(url: convertible,
                                                          method: method,
                                                          headers: headers,
                                                          requestModifier: requestModifier)

        return upload(fileURL,
                      with: convertible,
                      interceptor: interceptor,
                      shouldAutomaticallyResume: shouldAutomaticallyResume,
                      fileManager: fileManager)
    }

    open func upload(_ fileURL: URL,
                     with convertible: any URLRequestConvertible,
                     interceptor: (any RequestInterceptor)? = nil,
                     shouldAutomaticallyResume: Bool? = nil,
                     fileManager: FileManager = .default) -> UploadRequest {
        upload(.file(fileURL, shouldRemove: false),
               with: convertible,
               interceptor: interceptor,
               shouldAutomaticallyResume: shouldAutomaticallyResume,
               fileManager: fileManager)
    }

    open func upload(_ stream: InputStream,
                     to convertible: any URLConvertible,
                     method: HTTPMethod = .post,
                     headers: HTTPHeaders? = nil,
                     interceptor: (any RequestInterceptor)? = nil,
                     fileManager: FileManager = .default,
                     requestModifier: RequestModifier? = nil) -> UploadRequest {
        let convertible = ParameterlessRequestConvertible(url: convertible,
                                                          method: method,
                                                          headers: headers,
                                                          requestModifier: requestModifier)

        return upload(stream, with: convertible, interceptor: interceptor, fileManager: fileManager)
    }

    open func upload(_ stream: InputStream,
                     with convertible: any URLRequestConvertible,
                     interceptor: (any RequestInterceptor)? = nil,
                     shouldAutomaticallyResume: Bool? = nil,
                     fileManager: FileManager = .default) -> UploadRequest {
        upload(.stream(stream), with: convertible, interceptor: interceptor, shouldAutomaticallyResume: shouldAutomaticallyResume, fileManager: fileManager)
    }

    open func upload(multipartFormData: @escaping (MultipartFormData) -> Void,
                     to url: any URLConvertible,
                     usingThreshold encodingMemoryThreshold: UInt64 = MultipartFormData.encodingMemoryThreshold,
                     method: HTTPMethod = .post,
                     headers: HTTPHeaders? = nil,
                     interceptor: (any RequestInterceptor)? = nil,
                     fileManager: FileManager = .default,
                     requestModifier: RequestModifier? = nil) -> UploadRequest {
        let convertible = ParameterlessRequestConvertible(url: url,
                                                          method: method,
                                                          headers: headers,
                                                          requestModifier: requestModifier)

        let formData = MultipartFormData(fileManager: fileManager)
        multipartFormData(formData)

        return upload(multipartFormData: formData,
                      with: convertible,
                      usingThreshold: encodingMemoryThreshold,
                      interceptor: interceptor,
                      fileManager: fileManager)
    }

    open func upload(multipartFormData: @escaping (MultipartFormData) -> Void,
                     with request: any URLRequestConvertible,
                     usingThreshold encodingMemoryThreshold: UInt64 = MultipartFormData.encodingMemoryThreshold,
                     interceptor: (any RequestInterceptor)? = nil,
                     fileManager: FileManager = .default) -> UploadRequest {
        let formData = MultipartFormData(fileManager: fileManager)
        multipartFormData(formData)

        return upload(multipartFormData: formData,
                      with: request,
                      usingThreshold: encodingMemoryThreshold,
                      interceptor: interceptor,
                      fileManager: fileManager)
    }

    open func upload(multipartFormData: MultipartFormData,
                     to url: any URLConvertible,
                     usingThreshold encodingMemoryThreshold: UInt64 = MultipartFormData.encodingMemoryThreshold,
                     method: HTTPMethod = .post,
                     headers: HTTPHeaders? = nil,
                     interceptor: (any RequestInterceptor)? = nil,
                     shouldAutomaticallyResume: Bool? = nil,
                     fileManager: FileManager = .default,
                     requestModifier: RequestModifier? = nil) -> UploadRequest {
        let convertible = ParameterlessRequestConvertible(url: url,
                                                          method: method,
                                                          headers: headers,
                                                          requestModifier: requestModifier)

        let multipartUpload = MultipartUpload(encodingMemoryThreshold: encodingMemoryThreshold,
                                              request: convertible,
                                              multipartFormData: multipartFormData)

        return upload(multipartUpload, interceptor: interceptor, shouldAutomaticallyResume: shouldAutomaticallyResume, fileManager: fileManager)
    }

    open func upload(multipartFormData: MultipartFormData,
                     with request: any URLRequestConvertible,
                     usingThreshold encodingMemoryThreshold: UInt64 = MultipartFormData.encodingMemoryThreshold,
                     interceptor: (any RequestInterceptor)? = nil,
                     shouldAutomaticallyResume: Bool? = nil,
                     fileManager: FileManager = .default) -> UploadRequest {
        let multipartUpload = MultipartUpload(encodingMemoryThreshold: encodingMemoryThreshold,
                                              request: request,
                                              multipartFormData: multipartFormData)

        return upload(multipartUpload, interceptor: interceptor, shouldAutomaticallyResume: shouldAutomaticallyResume, fileManager: fileManager)
    }

    func upload(_ uploadable: UploadRequest.Uploadable,
                with convertible: any URLRequestConvertible,
                interceptor: (any RequestInterceptor)?,
                shouldAutomaticallyResume: Bool?,
                fileManager: FileManager) -> UploadRequest {
        let uploadable = Upload(request: convertible, uploadable: uploadable)

        return upload(uploadable, interceptor: interceptor, shouldAutomaticallyResume: shouldAutomaticallyResume, fileManager: fileManager)
    }

    func upload(_ upload: any UploadConvertible,
                interceptor: (any RequestInterceptor)?,
                shouldAutomaticallyResume: Bool?,
                fileManager: FileManager) -> UploadRequest {
        let request = UploadRequest(convertible: upload,
                                    underlyingQueue: rootQueue,
                                    serializationQueue: serializationQueue,
                                    eventMonitor: eventMonitor,
                                    interceptor: interceptor,
                                    shouldAutomaticallyResume: shouldAutomaticallyResume,
                                    fileManager: fileManager,
                                    delegate: self)

        performEagerlyIfNecessary(request)

        return request
    }

    func performEagerlyIfNecessary(_ request: Request) {
        guard requestSetup == .eager else { return }

        perform(request)
    }

    func perform(_ request: Request) {
        rootQueue.async {
            guard !request.isCancelled else { return }

            self.activeRequests.insert(request)

            self.requestQueue.async {
                switch request {
                case let r as UploadRequest: self.performUploadRequest(r)
                case let r as DataRequest: self.performDataRequest(r)
                case let r as DownloadRequest: self.performDownloadRequest(r)
                case let r as DataStreamRequest: self.performDataStreamRequest(r)
                default:
                    #if canImport(Darwin) && !canImport(FoundationNetworking)
                    if #available(macOS 10.15, iOS 13, tvOS 13, watchOS 6, *),
                       let request = request as? WebSocketRequest {
                        self.performWebSocketRequest(request)
                    } else {
                        fatalError("Attempted to perform unsupported Request subclass: \(type(of: request))")
                    }
                    #else
                    fatalError("Attempted to perform unsupported Request subclass: \(type(of: request))")
                    #endif
                }
            }
        }
    }

    func performDataRequest(_ request: DataRequest) {
        dispatchPrecondition(condition: .onQueue(requestQueue))

        performSetupOperations(for: request, convertible: request.convertible)
    }

    func performDataStreamRequest(_ request: DataStreamRequest) {
        dispatchPrecondition(condition: .onQueue(requestQueue))

        performSetupOperations(for: request, convertible: request.convertible)
    }

    #if canImport(Darwin) && !canImport(FoundationNetworking)
    @available(macOS 10.15, iOS 13, tvOS 13, watchOS 6, *)
    func performWebSocketRequest(_ request: WebSocketRequest) {
        dispatchPrecondition(condition: .onQueue(requestQueue))

        performSetupOperations(for: request, convertible: request.convertible)
    }
    #endif

    func performUploadRequest(_ request: UploadRequest) {
        dispatchPrecondition(condition: .onQueue(requestQueue))

        performSetupOperations(for: request, convertible: request.convertible) {
            do {
                let uploadable = try request.upload.createUploadable()
                self.rootQueue.async { request.didCreateUploadable(uploadable) }
                return true
            } catch {
                self.rootQueue.async { request.didFailToCreateUploadable(with: error.asAFError(or: .createUploadableFailed(error: error))) }
                return false
            }
        }
    }

    func performDownloadRequest(_ request: DownloadRequest) {
        dispatchPrecondition(condition: .onQueue(requestQueue))

        switch request.downloadable {
        case let .request(convertible):
            performSetupOperations(for: request, convertible: convertible)
        case let .resumeData(resumeData):
            rootQueue.async { self.didReceiveResumeData(resumeData, for: request) }
        }
    }

    func performSetupOperations(for request: Request,
                                convertible: any URLRequestConvertible,
                                shouldCreateTask: @escaping @Sendable () -> Bool = { true }) {
        dispatchPrecondition(condition: .onQueue(requestQueue))

        let initialRequest: URLRequest

        do {
            initialRequest = try convertible.asURLRequest()
            try initialRequest.validate()
        } catch {
            rootQueue.async { request.didFailToCreateURLRequest(with: error.asAFError(or: .createURLRequestFailed(error: error))) }
            return
        }

        rootQueue.async { request.didCreateInitialURLRequest(initialRequest) }

        guard !request.isCancelled else { return }

        guard let adapter = adapter(for: request) else {
            guard shouldCreateTask() else { return }
            rootQueue.async { self.didCreateURLRequest(initialRequest, for: request) }
            return
        }

        let adapterState = RequestAdapterState(requestID: request.id, session: self)

        adapter.adapt(initialRequest, using: adapterState) { result in
            do {
                let adaptedRequest = try result.get()
                try adaptedRequest.validate()

                self.rootQueue.async { request.didAdaptInitialRequest(initialRequest, to: adaptedRequest) }

                guard shouldCreateTask() else { return }

                self.rootQueue.async { self.didCreateURLRequest(adaptedRequest, for: request) }
            } catch {
                self.rootQueue.async { request.didFailToAdaptURLRequest(initialRequest, withError: .requestAdaptationFailed(error: error)) }
            }
        }
    }

    func didCreateURLRequest(_ urlRequest: URLRequest, for request: Request) {
        dispatchPrecondition(condition: .onQueue(rootQueue))

        request.didCreateURLRequest(urlRequest)

        guard !request.isCancelled else { return }

        let task = request.task(for: urlRequest, using: session)
        requestTaskMap[request] = task
        request.didCreateTask(task)

        updateStatesForTask(task, request: request)
    }

    func didReceiveResumeData(_ data: Data, for request: DownloadRequest) {
        dispatchPrecondition(condition: .onQueue(rootQueue))

        guard !request.isCancelled else { return }

        let task = request.task(forResumeData: data, using: session)
        requestTaskMap[request] = task
        request.didCreateTask(task)

        updateStatesForTask(task, request: request)
    }

    func updateStatesForTask(_ task: URLSessionTask, request: Request) {
        dispatchPrecondition(condition: .onQueue(rootQueue))

        request.withState { state in
            switch state {
            case .initialized, .finished:
                break
            case .resumed:
                task.resume()
                rootQueue.async { request.didResumeTask(task) }
            case .suspended:
                task.suspend()
                rootQueue.async { request.didSuspendTask(task) }
            case .cancelled:
                task.resume()
                task.cancel()
                rootQueue.async { request.didCancelTask(task) }
            }
        }
    }

    func adapter(for request: Request) -> (any RequestAdapter)? {
        if let requestInterceptor = request.interceptor, let sessionInterceptor = interceptor {
            Interceptor(adapters: [sessionInterceptor, requestInterceptor])
        } else {
            request.interceptor ?? interceptor
        }
    }

    func retrier(for request: Request) -> (any RequestRetrier)? {
        if let requestInterceptor = request.interceptor, let sessionInterceptor = interceptor {
            Interceptor(retriers: [sessionInterceptor, requestInterceptor])
        } else {
            request.interceptor ?? interceptor
        }
    }

    func finishRequestsForDeinit() {
        for request in requestTaskMap.requests {
            rootQueue.async {
                request.finish(error: AFError.sessionDeinitialized)
            }
        }
    }
}

extension Session: RequestDelegate {
    public var sessionConfiguration: URLSessionConfiguration {
        session.configuration
    }

    public var startImmediately: Bool { startRequestsImmediately }

    public func readyToPerform(request: Request) {
        rootQueue.async { [self] in
            if requestTaskMap[request] == nil {
                perform(request)
            }
        }
    }

    public func cleanup(after request: Request) {
        activeRequests.remove(request)
    }

    public func retryResult(for request: Request, dueTo error: AFError, completion: @escaping @Sendable (RetryResult) -> Void) {
        guard let retrier = retrier(for: request) else {
            rootQueue.async { completion(.doNotRetry) }
            return
        }

        retrier.retry(request, for: self, dueTo: error) { retryResult in
            self.rootQueue.async {
                guard let retryResultError = retryResult.error else { completion(retryResult); return }

                let retryError = AFError.requestRetryFailed(retryError: retryResultError, originalError: error)
                completion(.doNotRetryWithError(retryError))
            }
        }
    }

    public func retryRequest(_ request: Request, withDelay timeDelay: TimeInterval?) {
        rootQueue.async {
            let retry: @Sendable () -> Void = {
                guard !request.isCancelled else { return }

                request.prepareForRetry()
                self.perform(request)
            }

            if let retryDelay = timeDelay {
                self.rootQueue.after(retryDelay) { retry() }
            } else {
                retry()
            }
        }
    }
}

extension Session: SessionStateProvider {
    func request(for task: URLSessionTask) -> Request? {
        dispatchPrecondition(condition: .onQueue(rootQueue))

        return requestTaskMap[task]
    }

    func didGatherMetricsForTask(_ task: URLSessionTask) {
        dispatchPrecondition(condition: .onQueue(rootQueue))

        let didDisassociate = requestTaskMap.disassociateIfNecessaryAfterGatheringMetricsForTask(task)

        if didDisassociate {
            waitingCompletions[task]?()
            waitingCompletions[task] = nil
        }
    }

    func didCompleteTask(_ task: URLSessionTask, completion: @escaping () -> Void) {
        dispatchPrecondition(condition: .onQueue(rootQueue))

        let didDisassociate = requestTaskMap.disassociateIfNecessaryAfterCompletingTask(task)

        if didDisassociate {
            completion()
        } else {
            waitingCompletions[task] = completion
        }
    }

    func credential(for task: URLSessionTask, in protectionSpace: URLProtectionSpace) -> URLCredential? {
        dispatchPrecondition(condition: .onQueue(rootQueue))

        return requestTaskMap[task]?.credential ??
            session.configuration.urlCredentialStorage?.defaultCredential(for: protectionSpace)
    }

    func cancelRequestsForSessionInvalidation(with error: (any Error)?) {
        dispatchPrecondition(condition: .onQueue(rootQueue))

        requestTaskMap.requests.forEach { $0.finish(error: AFError.sessionInvalidated(error: error)) }
    }
}
