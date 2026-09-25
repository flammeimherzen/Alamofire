
import Foundation

public class DataRequest: Request, @unchecked Sendable {
    public let convertible: any URLRequestConvertible
    public var data: Data? { dataMutableState.read(\.data) }

    private struct DataMutableState {
        var data: Data?
        var httpResponseHandler: (queue: DispatchQueue,
                                  handler: @Sendable (_ response: HTTPURLResponse,
                                                      _ completionHandler: @escaping @Sendable (ResponseDisposition) -> Void) -> Void)?
    }

    private let dataMutableState = Protected(DataMutableState())

    init(id: UUID = UUID(),
         convertible: any URLRequestConvertible,
         underlyingQueue: DispatchQueue,
         serializationQueue: DispatchQueue,
         eventMonitor: (any EventMonitor)?,
         interceptor: (any RequestInterceptor)?,
         shouldAutomaticallyResume: Bool?,
         delegate: any RequestDelegate) {
        self.convertible = convertible

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

        dataMutableState.write { mutableState in
            mutableState.data = nil
        }
    }

    func didReceive(data: Data) {
        dataMutableState.write { mutableState in
            if mutableState.data == nil {
                mutableState.data = data
            } else {
                mutableState.data?.append(data)
            }
        }

        updateDownloadProgress()
    }

    func didReceiveResponse(_ response: HTTPURLResponse, completionHandler: @escaping @Sendable (URLSession.ResponseDisposition) -> Void) {
        dataMutableState.read { dataMutableState in
            guard let httpResponseHandler = dataMutableState.httpResponseHandler else {
                underlyingQueue.async { completionHandler(.allow) }
                return
            }

            httpResponseHandler.queue.async {
                httpResponseHandler.handler(response) { disposition in
                    if disposition == .cancel {
                        self.mutableState.write { mutableState in
                            mutableState.state = .cancelled
                            mutableState.error = mutableState.error ?? AFError.explicitlyCancelled
                        }
                    }

                    self.underlyingQueue.async {
                        completionHandler(disposition.sessionDisposition)
                    }
                }
            }
        }
    }

    override func task(for request: URLRequest, using session: URLSession) -> URLSessionTask {
        let copiedRequest = request
        return session.dataTask(with: copiedRequest)
    }

    func updateDownloadProgress() {
        let totalBytesReceived = Int64(data?.count ?? 0)
        let totalBytesExpected = task?.response?.expectedContentLength ?? NSURLSessionTransferSizeUnknown

        downloadProgress.totalUnitCount = totalBytesExpected
        downloadProgress.completedUnitCount = totalBytesReceived

        downloadProgressHandler?.queue.async { self.downloadProgressHandler?.handler(self.downloadProgress) }
    }

    @preconcurrency
    @discardableResult
    public func validate(_ validation: @escaping Validation) -> Self {
        let validator: @Sendable () -> Void = { [unowned self] in
            guard error == nil, let response else { return }

            let result = validation(request, response, data)

            if case let .failure(error) = result {
                self.error = error.asAFError(or: .responseValidationFailed(reason: .customValidationFailed(error: error)))
            }

            eventMonitor?.request(self,
                                  didValidateRequest: request,
                                  response: response,
                                  data: data,
                                  withResult: result)
        }

        validators.write { $0.append(validator) }

        return self
    }

    @_disfavoredOverload
    @preconcurrency
    @discardableResult
    public func onHTTPResponse(
        on queue: DispatchQueue = .main,
        perform handler: @escaping @Sendable (_ response: HTTPURLResponse,
                                              _ completionHandler: @escaping @Sendable (ResponseDisposition) -> Void) -> Void
    ) -> Self {
        dataMutableState.write { mutableState in
            mutableState.httpResponseHandler = (queue, handler)
        }

        return self
    }

    @preconcurrency
    @discardableResult
    public func onHTTPResponse(on queue: DispatchQueue = .main,
                               perform handler: @escaping @Sendable (HTTPURLResponse) -> Void) -> Self {
        onHTTPResponse(on: queue) { response, completionHandler in
            handler(response)
            completionHandler(.allow)
        }

        return self
    }

    @preconcurrency
    @discardableResult
    public func response(queue: DispatchQueue = .main, completionHandler: @escaping @Sendable (AFDataResponse<Data?>) -> Void) -> Self {
        appendResponseSerializer {
            let result = AFResult<Data?>(value: self.data, error: self.error)

            self.underlyingQueue.async {
                let response = DataResponse(request: self.request,
                                            response: self.response,
                                            data: self.data,
                                            metrics: self.metrics,
                                            serializationDuration: 0,
                                            result: result)

                self.eventMonitor?.request(self, didParseResponse: response)

                self.responseSerializerDidComplete { queue.async { completionHandler(response) } }
            }
        }

        return self
    }

    private func _response<Serializer: DataResponseSerializerProtocol>(queue: DispatchQueue = .main,
                                                                       responseSerializer: Serializer,
                                                                       completionHandler: @escaping @Sendable (AFDataResponse<Serializer.SerializedObject>) -> Void)
        -> Self {
        appendResponseSerializer {
            let start = ProcessInfo.processInfo.systemUptime
            let result: AFResult<Serializer.SerializedObject> = Result {
                try responseSerializer.serialize(request: self.request,
                                                 response: self.response,
                                                 data: self.data,
                                                 error: self.error)
            }.mapError { error in
                error.asAFError(or: .responseSerializationFailed(reason: .customSerializationFailed(error: error)))
            }

            let end = ProcessInfo.processInfo.systemUptime

            self.underlyingQueue.async {
                let response = DataResponse(request: self.request,
                                            response: self.response,
                                            data: self.data,
                                            metrics: self.metrics,
                                            serializationDuration: end - start,
                                            result: result)

                self.eventMonitor?.request(self, didParseResponse: response)

                guard !self.isCancelled, let serializerError = result.failure, let delegate = self.delegate else {
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

                        let response = DataResponse(request: self.request,
                                                    response: self.response,
                                                    data: self.data,
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

    @preconcurrency
    @discardableResult
    public func response<Serializer: DataResponseSerializerProtocol>(queue: DispatchQueue = .main,
                                                                     responseSerializer: Serializer,
                                                                     completionHandler: @escaping @Sendable (AFDataResponse<Serializer.SerializedObject>) -> Void)
        -> Self {
        _response(queue: queue, responseSerializer: responseSerializer, completionHandler: completionHandler)
    }

    @preconcurrency
    @discardableResult
    public func response<Serializer: ResponseSerializer>(queue: DispatchQueue = .main,
                                                         responseSerializer: Serializer,
                                                         completionHandler: @escaping @Sendable (AFDataResponse<Serializer.SerializedObject>) -> Void)
        -> Self {
        _response(queue: queue, responseSerializer: responseSerializer, completionHandler: completionHandler)
    }

    @preconcurrency
    @discardableResult
    public func responseData(queue: DispatchQueue = .main,
                             dataPreprocessor: any DataPreprocessor = DataResponseSerializer.defaultDataPreprocessor,
                             emptyResponseCodes: Set<Int> = DataResponseSerializer.defaultEmptyResponseCodes,
                             emptyRequestMethods: Set<HTTPMethod> = DataResponseSerializer.defaultEmptyRequestMethods,
                             completionHandler: @escaping @Sendable (AFDataResponse<Data>) -> Void) -> Self {
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
                               completionHandler: @escaping @Sendable (AFDataResponse<String>) -> Void) -> Self {
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
                             completionHandler: @escaping @Sendable (AFDataResponse<Any>) -> Void) -> Self {
        response(queue: queue,
                 responseSerializer: JSONResponseSerializer(dataPreprocessor: dataPreprocessor,
                                                            emptyResponseCodes: emptyResponseCodes,
                                                            emptyRequestMethods: emptyRequestMethods,
                                                            options: options),
                 completionHandler: completionHandler)
    }

    @preconcurrency
    @discardableResult
    public func responseDecodable<Value>(of type: Value.Type = Value.self,
                                         queue: DispatchQueue = .main,
                                         dataPreprocessor: any DataPreprocessor = DecodableResponseSerializer<Value>.defaultDataPreprocessor,
                                         decoder: any DataDecoder = JSONDecoder(),
                                         emptyResponseCodes: Set<Int> = DecodableResponseSerializer<Value>.defaultEmptyResponseCodes,
                                         emptyRequestMethods: Set<HTTPMethod> = DecodableResponseSerializer<Value>.defaultEmptyRequestMethods,
                                         completionHandler: @escaping @Sendable (AFDataResponse<Value>) -> Void) -> Self where Value: Decodable, Value: Sendable {
        response(queue: queue,
                 responseSerializer: DecodableResponseSerializer(dataPreprocessor: dataPreprocessor,
                                                                 decoder: decoder,
                                                                 emptyResponseCodes: emptyResponseCodes,
                                                                 emptyRequestMethods: emptyRequestMethods),
                 completionHandler: completionHandler)
    }
}
