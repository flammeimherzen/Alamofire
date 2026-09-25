
import Foundation

public final class DownloadRequest: Request, @unchecked Sendable {
    public struct Options: OptionSet, Sendable {
        public static let createIntermediateDirectories = Options(rawValue: 1 << 0)
        public static let removePreviousFile = Options(rawValue: 1 << 1)

        public let rawValue: Int

        public init(rawValue: Int) {
            self.rawValue = rawValue
        }
    }

    public typealias Destination = @Sendable (_ temporaryURL: URL,
                                              _ response: HTTPURLResponse) -> (destinationURL: URL, options: Options)

    public class func suggestedDownloadDestination(for directory: FileManager.SearchPathDirectory = .documentDirectory,
                                                   in domain: FileManager.SearchPathDomainMask = .userDomainMask,
                                                   options: Options = []) -> Destination {
        { temporaryURL, response in
            let directoryURLs = FileManager.default.urls(for: directory, in: domain)
            let url = directoryURLs.first?.appendingPathComponent(response.suggestedFilename!) ?? temporaryURL

            return (url, options)
        }
    }

    static let defaultDestination: Destination = { url, _ in
        (defaultDestinationURL(url), [])
    }

    static let defaultDestinationURL: @Sendable (URL) -> URL = { url in
        let filename = "Alamofire_\(url.lastPathComponent)"
        let destination = url.deletingLastPathComponent().appendingPathComponent(filename)

        return destination
    }

    public enum Downloadable {
        case request(any URLRequestConvertible)
        case resumeData(Data)
    }

    private struct DownloadRequestMutableState {
        var resumeData: Data?
        var fileURL: URL?
    }

    private let mutableDownloadState = Protected(DownloadRequestMutableState())

    public var resumeData: Data? {
        #if !canImport(FoundationNetworking)
        return mutableDownloadState.read(\.resumeData) ?? error?.downloadResumeData
        #else
        return mutableDownloadState.read(\.resumeData)
        #endif
    }

    public var fileURL: URL? { mutableDownloadState.read(\.fileURL) }

    public let downloadable: Downloadable
    let destination: Destination

    init(id: UUID = UUID(),
         downloadable: Downloadable,
         underlyingQueue: DispatchQueue,
         serializationQueue: DispatchQueue,
         eventMonitor: (any EventMonitor)?,
         interceptor: (any RequestInterceptor)?,
         shouldAutomaticallyResume: Bool?,
         delegate: any RequestDelegate,
         destination: @escaping Destination) {
        self.downloadable = downloadable
        self.destination = destination

        super.init(id: id,
                   underlyingQueue: underlyingQueue,
                   serializationQueue: serializationQueue,
                   eventMonitor: eventMonitor,
                   interceptor: interceptor,
                   shouldAutomaticallyResume: shouldAutomaticallyResume,
                   delegate: delegate)
    }

    override func reset() {
        super.reset()

        mutableDownloadState.write {
            $0.resumeData = nil
            $0.fileURL = nil
        }
    }

    func didFinishDownloading(using task: URLSessionTask, with result: Result<URL, AFError>) {
        eventMonitor?.request(self, didFinishDownloadingUsing: task, with: result)

        switch result {
        case let .success(url): mutableDownloadState.write { $0.fileURL = url }
        case let .failure(error): self.error = error
        }
    }

    func updateDownloadProgress(bytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        downloadProgress.totalUnitCount = totalBytesExpectedToWrite
        downloadProgress.completedUnitCount += bytesWritten

        downloadProgressHandler?.queue.async { self.downloadProgressHandler?.handler(self.downloadProgress) }
    }

    override func task(for request: URLRequest, using session: URLSession) -> URLSessionTask {
        session.downloadTask(with: request)
    }

    public func task(forResumeData data: Data, using session: URLSession) -> URLSessionTask {
        session.downloadTask(withResumeData: data)
    }

    @discardableResult
    override public func cancel() -> Self {
        cancel(producingResumeData: false)
    }

    @discardableResult
    public func cancel(producingResumeData shouldProduceResumeData: Bool) -> Self {
        cancel(optionallyProducingResumeData: shouldProduceResumeData ? { @Sendable _ in } : nil)
    }

    @preconcurrency
    @discardableResult
    public func cancel(byProducingResumeData completionHandler: @escaping @Sendable (_ data: Data?) -> Void) -> Self {
        cancel(optionallyProducingResumeData: completionHandler)
    }

    private func cancel(optionallyProducingResumeData completionHandler: (@Sendable (_ resumeData: Data?) -> Void)?) -> Self {
        mutableState.write { mutableState in
            guard mutableState.state.canTransitionTo(.cancelled) else { return }

            mutableState.state = .cancelled

            underlyingQueue.async { self.didCancel() }

            guard let task = mutableState.tasks.last as? URLSessionDownloadTask, task.state != .completed else {
                underlyingQueue.async { self.finish() }
                return
            }

            if let completionHandler {
                task.resume()
                task.cancel { resumeData in
                    self.mutableDownloadState.write { $0.resumeData = resumeData }
                    self.underlyingQueue.async { self.didCancelTask(task) }
                    completionHandler(resumeData)
                }
            } else {
                task.resume()
                task.cancel()
                self.underlyingQueue.async { self.didCancelTask(task) }
            }
        }

        return self
    }

    @discardableResult
    public func validate(_ validation: @escaping Validation) -> Self {
        let validator: @Sendable () -> Void = { [unowned self] in
            guard error == nil, let response else { return }

            let result = validation(request, response, fileURL)

            if case let .failure(error) = result {
                self.error = error.asAFError(or: .responseValidationFailed(reason: .customValidationFailed(error: error)))
            }

            eventMonitor?.request(self,
                                  didValidateRequest: request,
                                  response: response,
                                  fileURL: fileURL,
                                  withResult: result)
        }

        validators.write { $0.append(validator) }

        return self
    }

    @preconcurrency
    @discardableResult
    public func response(queue: DispatchQueue = .main,
                         completionHandler: @escaping @Sendable (AFDownloadResponse<URL?>) -> Void)
        -> Self {
        appendResponseSerializer {
            let result = AFResult<URL?>(value: self.fileURL, error: self.error)

            self.underlyingQueue.async {
                let response = DownloadResponse(request: self.request,
                                                response: self.response,
                                                fileURL: self.fileURL,
                                                resumeData: self.resumeData,
                                                metrics: self.metrics,
                                                serializationDuration: 0,
                                                result: result)

                self.eventMonitor?.request(self, didParseResponse: response)

                self.responseSerializerDidComplete { queue.async { completionHandler(response) } }
            }
        }

        return self
    }

    private func _response<Serializer: DownloadResponseSerializerProtocol>(queue: DispatchQueue = .main,
                                                                           responseSerializer: Serializer,
                                                                           completionHandler: @escaping @Sendable (AFDownloadResponse<Serializer.SerializedObject>) -> Void)
        -> Self {
        appendResponseSerializer {
            let start = ProcessInfo.processInfo.systemUptime
            let result: AFResult<Serializer.SerializedObject> = Result {
                try responseSerializer.serializeDownload(request: self.request,
                                                         response: self.response,
                                                         fileURL: self.fileURL,
                                                         error: self.error)
            }.mapError { error in
                error.asAFError(or: .responseSerializationFailed(reason: .customSerializationFailed(error: error)))
            }
            let end = ProcessInfo.processInfo.systemUptime

            self.underlyingQueue.async {
                let response = DownloadResponse(request: self.request,
                                                response: self.response,
                                                fileURL: self.fileURL,
                                                resumeData: self.resumeData,
                                                metrics: self.metrics,
                                                serializationDuration: end - start,
                                                result: result)

                self.eventMonitor?.request(self, didParseResponse: response)

                guard let serializerError = result.failure, let delegate = self.delegate else {
                    self.responseSerializerDidComplete { queue.async { completionHandler(response) } }
                    return
                }

                delegate.retryResult(for: self, dueTo: serializerError) { retryResult in
                    var didComplete: (@Sendable () -> Void)?

                    defer {
                        if let didComplete {
                            self.responseSerializerDidComplete { queue.async { didComplete() } }
                        }
                    }

                    switch retryResult {
                    case .doNotRetry:
                        didComplete = { completionHandler(response) }

                    case let .doNotRetryWithError(retryError):
                        let result: AFResult<Serializer.SerializedObject> = .failure(retryError.asAFError(orFailWith: "Received retryError was not already AFError"))

                        let response = DownloadResponse(request: self.request,
                                                        response: self.response,
                                                        fileURL: self.fileURL,
                                                        resumeData: self.resumeData,
                                                        metrics: self.metrics,
                                                        serializationDuration: end - start,
                                                        result: result)

                        didComplete = { completionHandler(response) }

                    case .retry, .retryWithDelay:
                        delegate.retryRequest(self, withDelay: retryResult.delay)
                    }
                }
            }
        }

        return self
    }

    @discardableResult
    public func response<Serializer: DownloadResponseSerializerProtocol>(queue: DispatchQueue = .main,
                                                                         responseSerializer: Serializer,
                                                                         completionHandler: @escaping @Sendable (AFDownloadResponse<Serializer.SerializedObject>) -> Void)
        -> Self {
        _response(queue: queue, responseSerializer: responseSerializer, completionHandler: completionHandler)
    }

    @discardableResult
    public func response<Serializer: ResponseSerializer>(queue: DispatchQueue = .main,
                                                         responseSerializer: Serializer,
                                                         completionHandler: @escaping @Sendable (AFDownloadResponse<Serializer.SerializedObject>) -> Void)
        -> Self {
        _response(queue: queue, responseSerializer: responseSerializer, completionHandler: completionHandler)
    }

    @preconcurrency
    @discardableResult
    public func responseURL(queue: DispatchQueue = .main,
                            completionHandler: @escaping @Sendable (AFDownloadResponse<URL>) -> Void) -> Self {
        response(queue: queue, responseSerializer: URLResponseSerializer(), completionHandler: completionHandler)
    }

    @preconcurrency
    @discardableResult
    public func responseData(queue: DispatchQueue = .main,
                             dataPreprocessor: any DataPreprocessor = DataResponseSerializer.defaultDataPreprocessor,
                             emptyResponseCodes: Set<Int> = DataResponseSerializer.defaultEmptyResponseCodes,
                             emptyRequestMethods: Set<HTTPMethod> = DataResponseSerializer.defaultEmptyRequestMethods,
                             completionHandler: @escaping @Sendable (AFDownloadResponse<Data>) -> Void) -> Self {
        response(queue: queue,
                 responseSerializer: DataResponseSerializer(dataPreprocessor: dataPreprocessor,
                                                            emptyResponseCodes: emptyResponseCodes,
                                                            emptyRequestMethods: emptyRequestMethods),
                 completionHandler: completionHandler)
    }

    @preconcurrency
    @discardableResult
    public func responseString(queue: DispatchQueue = .main,
                               dataPreprocessor: any DataPreprocessor = StringResponseSerializer.defaultDataPreprocessor,
                               encoding: String.Encoding? = nil,
                               emptyResponseCodes: Set<Int> = StringResponseSerializer.defaultEmptyResponseCodes,
                               emptyRequestMethods: Set<HTTPMethod> = StringResponseSerializer.defaultEmptyRequestMethods,
                               completionHandler: @escaping @Sendable (AFDownloadResponse<String>) -> Void) -> Self {
        response(queue: queue,
                 responseSerializer: StringResponseSerializer(dataPreprocessor: dataPreprocessor,
                                                              encoding: encoding,
                                                              emptyResponseCodes: emptyResponseCodes,
                                                              emptyRequestMethods: emptyRequestMethods),
                 completionHandler: completionHandler)
    }

    @available(*, deprecated, message: "responseJSON deprecated and will be removed in Alamofire 6. Use responseDecodable instead.")
    @preconcurrency
    @discardableResult
    public func responseJSON(queue: DispatchQueue = .main,
                             dataPreprocessor: any DataPreprocessor = JSONResponseSerializer.defaultDataPreprocessor,
                             emptyResponseCodes: Set<Int> = JSONResponseSerializer.defaultEmptyResponseCodes,
                             emptyRequestMethods: Set<HTTPMethod> = JSONResponseSerializer.defaultEmptyRequestMethods,
                             options: JSONSerialization.ReadingOptions = .allowFragments,
                             completionHandler: @escaping @Sendable (AFDownloadResponse<Any>) -> Void) -> Self {
        response(queue: queue,
                 responseSerializer: JSONResponseSerializer(dataPreprocessor: dataPreprocessor,
                                                            emptyResponseCodes: emptyResponseCodes,
                                                            emptyRequestMethods: emptyRequestMethods,
                                                            options: options),
                 completionHandler: completionHandler)
    }

    @preconcurrency
    @discardableResult
    public func responseDecodable<T: Decodable>(of type: T.Type = T.self,
                                                queue: DispatchQueue = .main,
                                                dataPreprocessor: any DataPreprocessor = DecodableResponseSerializer<T>.defaultDataPreprocessor,
                                                decoder: any DataDecoder = JSONDecoder(),
                                                emptyResponseCodes: Set<Int> = DecodableResponseSerializer<T>.defaultEmptyResponseCodes,
                                                emptyRequestMethods: Set<HTTPMethod> = DecodableResponseSerializer<T>.defaultEmptyRequestMethods,
                                                completionHandler: @escaping @Sendable (AFDownloadResponse<T>) -> Void) -> Self where T: Sendable {
        response(queue: queue,
                 responseSerializer: DecodableResponseSerializer(dataPreprocessor: dataPreprocessor,
                                                                 decoder: decoder,
                                                                 emptyResponseCodes: emptyResponseCodes,
                                                                 emptyRequestMethods: emptyRequestMethods),
                 completionHandler: completionHandler)
    }
}
