
import Foundation

public final class DataStreamRequest: Request, @unchecked Sendable {
    public typealias Handler<Success, Failure: Error> = @Sendable (Stream<Success, Failure>) throws -> Void

    public struct Stream<Success, Failure: Error>: Sendable where Success: Sendable, Failure: Sendable {
        public let event: Event<Success, Failure>
        public let token: CancellationToken

        public func cancel() {
            token.cancel()
        }
    }

    public enum Event<Success, Failure: Error>: Sendable where Success: Sendable, Failure: Sendable {
        case stream(Result<Success, Failure>)
        case complete(Completion)
    }

    public struct Completion: Sendable {
        public let request: URLRequest?
        public let response: HTTPURLResponse?
        public let metrics: URLSessionTaskMetrics?
        public let error: AFError?
    }

    public struct CancellationToken: Sendable {
        weak var request: DataStreamRequest?

        init(_ request: DataStreamRequest) {
            self.request = request
        }

        public func cancel() {
            request?.cancel()
        }
    }

    public let convertible: any URLRequestConvertible
    public let automaticallyCancelOnStreamError: Bool

    struct StreamMutableState {
        var outputStream: OutputStream?
        var streams: [@Sendable (_ data: Data) -> Void] = []
        var numberOfExecutingStreams = 0
        var enqueuedCompletionEvents: [@Sendable () -> Void] = []
        var httpResponseHandler: (queue: DispatchQueue,
                                  handler: @Sendable (_ response: HTTPURLResponse,
                                                      _ completionHandler: @escaping @Sendable (ResponseDisposition) -> Void) -> Void)?
    }

    let streamMutableState = Protected(StreamMutableState())

    init(id: UUID = UUID(),
         convertible: any URLRequestConvertible,
         automaticallyCancelOnStreamError: Bool,
         underlyingQueue: DispatchQueue,
         serializationQueue: DispatchQueue,
         eventMonitor: (any EventMonitor)?,
         interceptor: (any RequestInterceptor)?,
         shouldAutomaticallyResume: Bool?,
         delegate: any RequestDelegate) {
        self.convertible = convertible
        self.automaticallyCancelOnStreamError = automaticallyCancelOnStreamError

        super.init(id: id,
                   underlyingQueue: underlyingQueue,
                   serializationQueue: serializationQueue,
                   eventMonitor: eventMonitor,
                   interceptor: interceptor,
                   shouldAutomaticallyResume: shouldAutomaticallyResume,
                   delegate: delegate)
    }

    override func task(for request: URLRequest, using session: URLSession) -> URLSessionTask {
        let copiedRequest = request
        return session.dataTask(with: copiedRequest)
    }

    override func finish(error: AFError? = nil) {
        streamMutableState.write { state in
            state.outputStream?.close()
        }

        super.finish(error: error)
    }

    func didReceive(data: Data) {
        streamMutableState.write { state in
            #if !canImport(FoundationNetworking)
            if let stream = state.outputStream {
                underlyingQueue.async {
                    var bytes = Array(data)
                    stream.write(&bytes, maxLength: bytes.count)
                }
            }
            #endif
            state.numberOfExecutingStreams += state.streams.count
            underlyingQueue.async { [streams = state.streams] in streams.forEach { $0(data) } }
        }
    }

    func didReceiveResponse(_ response: HTTPURLResponse, completionHandler: @escaping @Sendable (URLSession.ResponseDisposition) -> Void) {
        streamMutableState.read { dataMutableState in
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

    @discardableResult
    public func validate(_ validation: @escaping Validation) -> Self {
        let validator: @Sendable () -> Void = { [unowned self] in
            guard error == nil, let response else { return }

            let result = validation(request, response)

            if case let .failure(error) = result {
                self.error = error.asAFError(or: .responseValidationFailed(reason: .customValidationFailed(error: error)))
            }

            eventMonitor?.request(self,
                                  didValidateRequest: request,
                                  response: response,
                                  withResult: result)
        }

        validators.write { $0.append(validator) }

        return self
    }

    #if !canImport(FoundationNetworking)
    public func asInputStream(bufferSize: Int = 1024) -> InputStream? {
        defer { resume() }

        var inputStream: InputStream?
        streamMutableState.write { state in
            Foundation.Stream.getBoundStreams(withBufferSize: bufferSize,
                                              inputStream: &inputStream,
                                              outputStream: &state.outputStream)
            state.outputStream?.open()
        }

        return inputStream
    }
    #endif

    @_disfavoredOverload
    @preconcurrency
    @discardableResult
    public func onHTTPResponse(
        on queue: DispatchQueue = .main,
        perform handler: @escaping @Sendable (_ response: HTTPURLResponse,
                                              _ completionHandler: @escaping @Sendable (ResponseDisposition) -> Void) -> Void
    ) -> Self {
        streamMutableState.write { mutableState in
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

    func capturingError(from closure: () throws -> Void) {
        do {
            try closure()
        } catch {
            self.error = error.asAFError(or: .responseSerializationFailed(reason: .customSerializationFailed(error: error)))
            cancel()
        }
    }

    func appendStreamCompletion<Success, Failure>(on queue: DispatchQueue,
                                                  stream: @escaping Handler<Success, Failure>) where Success: Sendable, Failure: Sendable {
        appendResponseSerializer {
            self.underlyingQueue.async {
                self.responseSerializerDidComplete {
                    self.streamMutableState.write { state in
                        guard state.numberOfExecutingStreams == 0 else {
                            state.enqueuedCompletionEvents.append {
                                self.enqueueCompletion(on: queue, stream: stream)
                            }

                            return
                        }

                        self.enqueueCompletion(on: queue, stream: stream)
                    }
                }
            }
        }
    }

    func enqueueCompletion<Success, Failure>(on queue: DispatchQueue,
                                             stream: @escaping Handler<Success, Failure>) where Success: Sendable, Failure: Sendable {
        queue.async {
            do {
                let completion = Completion(request: self.request,
                                            response: self.response,
                                            metrics: self.metrics,
                                            error: self.error)
                try stream(.init(event: .complete(completion), token: .init(self)))
            } catch {
            }
        }
    }

    @preconcurrency
    @discardableResult
    public func responseStream(on queue: DispatchQueue = .main, stream: @escaping Handler<Data, Never>) -> Self {
        let parser = { @Sendable [unowned self] (data: Data) in
            queue.async {
                self.capturingError {
                    try stream(.init(event: .stream(.success(data)), token: .init(self)))
                }

                self.updateAndCompleteIfPossible()
            }
        }

        streamMutableState.write { $0.streams.append(parser) }
        appendStreamCompletion(on: queue, stream: stream)

        return self
    }

    @preconcurrency
    @discardableResult
    public func responseStream<Serializer: DataStreamSerializer>(using serializer: Serializer,
                                                                 on queue: DispatchQueue = .main,
                                                                 stream: @escaping Handler<Serializer.SerializedObject, AFError>) -> Self {
        let parser = { @Sendable [unowned self] (data: Data) in
            serializationQueue.async {
                let result = Result { try serializer.serialize(data) }
                    .mapError { $0.asAFError(or: .responseSerializationFailed(reason: .customSerializationFailed(error: $0))) }
                self.underlyingQueue.async {
                    self.eventMonitor?.request(self, didParseStream: result)

                    if result.isFailure, self.automaticallyCancelOnStreamError {
                        self.cancel()
                    }

                    queue.async {
                        self.capturingError {
                            try stream(.init(event: .stream(result), token: .init(self)))
                        }

                        self.updateAndCompleteIfPossible()
                    }
                }
            }
        }

        streamMutableState.write { $0.streams.append(parser) }
        appendStreamCompletion(on: queue, stream: stream)

        return self
    }

    @preconcurrency
    @discardableResult
    public func responseStreamString(on queue: DispatchQueue = .main,
                                     stream: @escaping Handler<String, Never>) -> Self {
        let parser = { @Sendable [unowned self] (data: Data) in
            serializationQueue.async {
                let string = String(decoding: data, as: UTF8.self)
                self.underlyingQueue.async {
                    self.eventMonitor?.request(self, didParseStream: .success(string))

                    queue.async {
                        self.capturingError {
                            try stream(.init(event: .stream(.success(string)), token: .init(self)))
                        }

                        self.updateAndCompleteIfPossible()
                    }
                }
            }
        }

        streamMutableState.write { $0.streams.append(parser) }
        appendStreamCompletion(on: queue, stream: stream)

        return self
    }

    private func updateAndCompleteIfPossible() {
        streamMutableState.write { state in
            state.numberOfExecutingStreams -= 1

            guard state.numberOfExecutingStreams == 0, !state.enqueuedCompletionEvents.isEmpty else { return }

            let completionEvents = state.enqueuedCompletionEvents
            self.underlyingQueue.async { completionEvents.forEach { $0() } }
            state.enqueuedCompletionEvents.removeAll()
        }
    }

    @preconcurrency
    @discardableResult
    public func responseStreamDecodable<T: Decodable>(of type: T.Type = T.self,
                                                      on queue: DispatchQueue = .main,
                                                      using decoder: any DataDecoder = JSONDecoder(),
                                                      preprocessor: any DataPreprocessor = PassthroughPreprocessor(),
                                                      stream: @escaping Handler<T, AFError>) -> Self where T: Sendable {
        responseStream(using: DecodableStreamSerializer<T>(decoder: decoder, dataPreprocessor: preprocessor),
                       on: queue,
                       stream: stream)
    }
}

extension DataStreamRequest.Stream {
    public var result: Result<Success, Failure>? {
        guard case let .stream(result) = event else { return nil }

        return result
    }

    public var value: Success? {
        guard case let .success(value) = result else { return nil }

        return value
    }

    public var error: Failure? {
        guard case let .failure(error) = result else { return nil }

        return error
    }

    public var completion: DataStreamRequest.Completion? {
        guard case let .complete(completion) = event else { return nil }

        return completion
    }
}

public protocol DataStreamSerializer: Sendable {
    associatedtype SerializedObject: Sendable

    func serialize(_ data: Data) throws -> SerializedObject
}

public struct DecodableStreamSerializer<T: Decodable>: DataStreamSerializer where T: Sendable {
    public let decoder: any DataDecoder
    public let dataPreprocessor: any DataPreprocessor

    public init(decoder: any DataDecoder = JSONDecoder(), dataPreprocessor: any DataPreprocessor = PassthroughPreprocessor()) {
        self.decoder = decoder
        self.dataPreprocessor = dataPreprocessor
    }

    public func serialize(_ data: Data) throws -> T {
        let processedData = try dataPreprocessor.preprocess(data)
        do {
            return try decoder.decode(T.self, from: processedData)
        } catch {
            throw AFError.responseSerializationFailed(reason: .decodingFailed(error: error))
        }
    }
}

public struct PassthroughStreamSerializer: DataStreamSerializer {
    public init() {}

    public func serialize(_ data: Data) throws -> Data { data }
}

public struct StringStreamSerializer: DataStreamSerializer {
    public init() {}

    public func serialize(_ data: Data) throws -> String {
        String(decoding: data, as: UTF8.self)
    }
}

extension DataStreamSerializer {
    public static func decodable<T: Decodable>(of type: T.Type,
                                               decoder: any DataDecoder = JSONDecoder(),
                                               dataPreprocessor: any DataPreprocessor = PassthroughPreprocessor()) -> Self where Self == DecodableStreamSerializer<T> {
        DecodableStreamSerializer<T>(decoder: decoder, dataPreprocessor: dataPreprocessor)
    }
}

extension DataStreamSerializer where Self == PassthroughStreamSerializer {
    public static var passthrough: PassthroughStreamSerializer { PassthroughStreamSerializer() }
}

extension DataStreamSerializer where Self == StringStreamSerializer {
    public static var string: StringStreamSerializer { StringStreamSerializer() }
}
