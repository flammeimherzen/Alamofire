
#if canImport(_Concurrency)

import Foundation

@available(macOS 10.15, iOS 13, tvOS 13, watchOS 6, *)
extension Request {
    public func uploadProgress(bufferingPolicy: StreamOf<Progress>.BufferingPolicy = .unbounded) -> StreamOf<Progress> {
        stream(bufferingPolicy: bufferingPolicy) { [unowned self] continuation in
            uploadProgress(queue: underlyingQueue) { progress in
                continuation.yield(progress)
            }
        }
    }

    public func downloadProgress(bufferingPolicy: StreamOf<Progress>.BufferingPolicy = .unbounded) -> StreamOf<Progress> {
        stream(bufferingPolicy: bufferingPolicy) { [unowned self] continuation in
            downloadProgress(queue: underlyingQueue) { progress in
                continuation.yield(progress)
            }
        }
    }

    public func urlRequests(bufferingPolicy: StreamOf<URLRequest>.BufferingPolicy = .unbounded) -> StreamOf<URLRequest> {
        stream(bufferingPolicy: bufferingPolicy) { [unowned self] continuation in
            onURLRequestCreation(on: underlyingQueue) { request in
                continuation.yield(request)
            }
        }
    }

    public func urlSessionTasks(bufferingPolicy: StreamOf<URLSessionTask>.BufferingPolicy = .unbounded) -> StreamOf<URLSessionTask> {
        stream(bufferingPolicy: bufferingPolicy) { [unowned self] continuation in
            onURLSessionTaskCreation(on: underlyingQueue) { task in
                continuation.yield(task)
            }
        }
    }

    public func cURLDescriptions(bufferingPolicy: StreamOf<String>.BufferingPolicy = .unbounded) -> StreamOf<String> {
        stream(bufferingPolicy: bufferingPolicy) { [unowned self] continuation in
            cURLDescription(on: underlyingQueue) { description in
                continuation.yield(description)
            }
        }
    }

    fileprivate func stream<T>(of type: T.Type = T.self,
                               bufferingPolicy: StreamOf<T>.BufferingPolicy = .unbounded,
                               yielder: @escaping (StreamOf<T>.Continuation) -> Void) -> StreamOf<T> {
        StreamOf<T>(bufferingPolicy: bufferingPolicy) { [unowned self] continuation in
            yielder(continuation)
            onFinish {
                continuation.finish()
            }
        }
    }
}

@available(macOS 10.15, iOS 13, tvOS 13, watchOS 6, *)
public struct DataTask<Value>: Sendable where Value: Sendable {
    public var response: DataResponse<Value, AFError> {
        get async {
            if shouldAutomaticallyCancel {
                await withTaskCancellationHandler {
                    await task.value
                } onCancel: {
                    cancel()
                }
            } else {
                await task.value
            }
        }
    }

    public var result: Result<Value, AFError> {
        get async { await response.result }
    }

    public var value: Value {
        get async throws {
            try await result.get()
        }
    }

    private let request: DataRequest
    private let task: Task<DataResponse<Value, AFError>, Never>
    private let shouldAutomaticallyCancel: Bool

    fileprivate init(request: DataRequest, task: Task<DataResponse<Value, AFError>, Never>, shouldAutomaticallyCancel: Bool) {
        self.request = request
        self.task = task
        self.shouldAutomaticallyCancel = shouldAutomaticallyCancel
    }

    public func cancel() {
        task.cancel()
    }

    public func resume() {
        request.resume()
    }

    public func suspend() {
        request.suspend()
    }
}

@available(macOS 10.15, iOS 13, tvOS 13, watchOS 6, *)
extension DataRequest {
    public func httpResponses(bufferingPolicy: StreamOf<HTTPURLResponse>.BufferingPolicy = .unbounded) -> StreamOf<HTTPURLResponse> {
        stream(bufferingPolicy: bufferingPolicy) { [unowned self] continuation in
            onHTTPResponse(on: underlyingQueue) { response in
                continuation.yield(response)
            }
        }
    }

    @_disfavoredOverload
    @discardableResult
    public func onHTTPResponse(
        perform handler: @escaping @Sendable (_ response: HTTPURLResponse) async -> ResponseDisposition
    ) -> Self {
        onHTTPResponse(on: underlyingQueue) { response, completionHandler in
            Task {
                let disposition = await handler(response)
                completionHandler(disposition)
            }
        }

        return self
    }

    @discardableResult
    public func onHTTPResponse(perform handler: @escaping @Sendable (_ response: HTTPURLResponse) async -> Void) -> Self {
        onHTTPResponse { response in
            await handler(response)
            return .allow
        }

        return self
    }

    public func serializingData(automaticallyCancelling shouldAutomaticallyCancel: Bool = true,
                                dataPreprocessor: any DataPreprocessor = DataResponseSerializer.defaultDataPreprocessor,
                                emptyResponseCodes: Set<Int> = DataResponseSerializer.defaultEmptyResponseCodes,
                                emptyRequestMethods: Set<HTTPMethod> = DataResponseSerializer.defaultEmptyRequestMethods) -> DataTask<Data> {
        serializingResponse(using: DataResponseSerializer(dataPreprocessor: dataPreprocessor,
                                                          emptyResponseCodes: emptyResponseCodes,
                                                          emptyRequestMethods: emptyRequestMethods),
                            automaticallyCancelling: shouldAutomaticallyCancel)
    }

    public func serializingDecodable<Value: Decodable>(_ type: Value.Type = Value.self,
                                                       automaticallyCancelling shouldAutomaticallyCancel: Bool = true,
                                                       dataPreprocessor: any DataPreprocessor = DecodableResponseSerializer<Value>.defaultDataPreprocessor,
                                                       decoder: any DataDecoder = JSONDecoder(),
                                                       emptyResponseCodes: Set<Int> = DecodableResponseSerializer<Value>.defaultEmptyResponseCodes,
                                                       emptyRequestMethods: Set<HTTPMethod> = DecodableResponseSerializer<Value>.defaultEmptyRequestMethods) -> DataTask<Value> {
        serializingResponse(using: DecodableResponseSerializer<Value>(dataPreprocessor: dataPreprocessor,
                                                                      decoder: decoder,
                                                                      emptyResponseCodes: emptyResponseCodes,
                                                                      emptyRequestMethods: emptyRequestMethods),
                            automaticallyCancelling: shouldAutomaticallyCancel)
    }

    public func serializingString(automaticallyCancelling shouldAutomaticallyCancel: Bool = true,
                                  dataPreprocessor: any DataPreprocessor = StringResponseSerializer.defaultDataPreprocessor,
                                  encoding: String.Encoding? = nil,
                                  emptyResponseCodes: Set<Int> = StringResponseSerializer.defaultEmptyResponseCodes,
                                  emptyRequestMethods: Set<HTTPMethod> = StringResponseSerializer.defaultEmptyRequestMethods) -> DataTask<String> {
        serializingResponse(using: StringResponseSerializer(dataPreprocessor: dataPreprocessor,
                                                            encoding: encoding,
                                                            emptyResponseCodes: emptyResponseCodes,
                                                            emptyRequestMethods: emptyRequestMethods),
                            automaticallyCancelling: shouldAutomaticallyCancel)
    }

    public func serializingResponse<Serializer: ResponseSerializer>(using serializer: Serializer,
                                                                    automaticallyCancelling shouldAutomaticallyCancel: Bool = true)
        -> DataTask<Serializer.SerializedObject> {
        dataTask(automaticallyCancelling: shouldAutomaticallyCancel) { [self] in
            response(queue: underlyingQueue,
                     responseSerializer: serializer,
                     completionHandler: $0)
        }
    }

    public func serializingResponse<Serializer: DataResponseSerializerProtocol>(using serializer: Serializer,
                                                                                automaticallyCancelling shouldAutomaticallyCancel: Bool = true)
        -> DataTask<Serializer.SerializedObject> {
        dataTask(automaticallyCancelling: shouldAutomaticallyCancel) { [self] in
            response(queue: underlyingQueue,
                     responseSerializer: serializer,
                     completionHandler: $0)
        }
    }

    private func dataTask<Value>(automaticallyCancelling shouldAutomaticallyCancel: Bool,
                                 forResponse onResponse: @Sendable @escaping (@escaping @Sendable (DataResponse<Value, AFError>) -> Void) -> Void)
        -> DataTask<Value> {
        let task = Task {
            await withTaskCancellationHandler {
                await withCheckedContinuation { continuation in
                    onResponse {
                        continuation.resume(returning: $0)
                    }
                }
            } onCancel: {
                self.cancel()
            }
        }

        return DataTask<Value>(request: self, task: task, shouldAutomaticallyCancel: shouldAutomaticallyCancel)
    }
}

@available(macOS 10.15, iOS 13, tvOS 13, watchOS 6, *)
public struct DownloadTask<Value>: Sendable where Value: Sendable {
    public var response: DownloadResponse<Value, AFError> {
        get async {
            if shouldAutomaticallyCancel {
                await withTaskCancellationHandler {
                    await task.value
                } onCancel: {
                    cancel()
                }
            } else {
                await task.value
            }
        }
    }

    public var result: Result<Value, AFError> {
        get async { await response.result }
    }

    public var value: Value {
        get async throws {
            try await result.get()
        }
    }

    private let task: Task<AFDownloadResponse<Value>, Never>
    private let request: DownloadRequest
    private let shouldAutomaticallyCancel: Bool

    fileprivate init(request: DownloadRequest, task: Task<AFDownloadResponse<Value>, Never>, shouldAutomaticallyCancel: Bool) {
        self.request = request
        self.task = task
        self.shouldAutomaticallyCancel = shouldAutomaticallyCancel
    }

    public func cancel() {
        task.cancel()
    }

    public func resume() {
        request.resume()
    }

    public func suspend() {
        request.suspend()
    }
}

@available(macOS 10.15, iOS 13, tvOS 13, watchOS 6, *)
extension DownloadRequest {
    public func serializingData(automaticallyCancelling shouldAutomaticallyCancel: Bool = true,
                                dataPreprocessor: any DataPreprocessor = DataResponseSerializer.defaultDataPreprocessor,
                                emptyResponseCodes: Set<Int> = DataResponseSerializer.defaultEmptyResponseCodes,
                                emptyRequestMethods: Set<HTTPMethod> = DataResponseSerializer.defaultEmptyRequestMethods) -> DownloadTask<Data> {
        serializingDownload(using: DataResponseSerializer(dataPreprocessor: dataPreprocessor,
                                                          emptyResponseCodes: emptyResponseCodes,
                                                          emptyRequestMethods: emptyRequestMethods),
                            automaticallyCancelling: shouldAutomaticallyCancel)
    }

    public func serializingDecodable<Value: Decodable>(_ type: Value.Type = Value.self,
                                                       automaticallyCancelling shouldAutomaticallyCancel: Bool = true,
                                                       dataPreprocessor: any DataPreprocessor = DecodableResponseSerializer<Value>.defaultDataPreprocessor,
                                                       decoder: any DataDecoder = JSONDecoder(),
                                                       emptyResponseCodes: Set<Int> = DecodableResponseSerializer<Value>.defaultEmptyResponseCodes,
                                                       emptyRequestMethods: Set<HTTPMethod> = DecodableResponseSerializer<Value>.defaultEmptyRequestMethods) -> DownloadTask<Value> {
        serializingDownload(using: DecodableResponseSerializer<Value>(dataPreprocessor: dataPreprocessor,
                                                                      decoder: decoder,
                                                                      emptyResponseCodes: emptyResponseCodes,
                                                                      emptyRequestMethods: emptyRequestMethods),
                            automaticallyCancelling: shouldAutomaticallyCancel)
    }

    public func serializingDownloadedFileURL(automaticallyCancelling shouldAutomaticallyCancel: Bool = true) -> DownloadTask<URL> {
        serializingDownload(using: URLResponseSerializer(),
                            automaticallyCancelling: shouldAutomaticallyCancel)
    }

    public func serializingString(automaticallyCancelling shouldAutomaticallyCancel: Bool = true,
                                  dataPreprocessor: any DataPreprocessor = StringResponseSerializer.defaultDataPreprocessor,
                                  encoding: String.Encoding? = nil,
                                  emptyResponseCodes: Set<Int> = StringResponseSerializer.defaultEmptyResponseCodes,
                                  emptyRequestMethods: Set<HTTPMethod> = StringResponseSerializer.defaultEmptyRequestMethods) -> DownloadTask<String> {
        serializingDownload(using: StringResponseSerializer(dataPreprocessor: dataPreprocessor,
                                                            encoding: encoding,
                                                            emptyResponseCodes: emptyResponseCodes,
                                                            emptyRequestMethods: emptyRequestMethods),
                            automaticallyCancelling: shouldAutomaticallyCancel)
    }

    public func serializingDownload<Serializer: ResponseSerializer>(using serializer: Serializer,
                                                                    automaticallyCancelling shouldAutomaticallyCancel: Bool = true)
        -> DownloadTask<Serializer.SerializedObject> {
        downloadTask(automaticallyCancelling: shouldAutomaticallyCancel) { [self] in
            response(queue: underlyingQueue,
                     responseSerializer: serializer,
                     completionHandler: $0)
        }
    }

    public func serializingDownload<Serializer: DownloadResponseSerializerProtocol>(using serializer: Serializer,
                                                                                    automaticallyCancelling shouldAutomaticallyCancel: Bool = true)
        -> DownloadTask<Serializer.SerializedObject> {
        downloadTask(automaticallyCancelling: shouldAutomaticallyCancel) { [self] in
            response(queue: underlyingQueue,
                     responseSerializer: serializer,
                     completionHandler: $0)
        }
    }

    private func downloadTask<Value>(automaticallyCancelling shouldAutomaticallyCancel: Bool,
                                     forResponse onResponse: @Sendable @escaping (@escaping @Sendable (DownloadResponse<Value, AFError>) -> Void) -> Void)
        -> DownloadTask<Value> {
        let task = Task {
            await withTaskCancellationHandler {
                await withCheckedContinuation { continuation in
                    onResponse {
                        continuation.resume(returning: $0)
                    }
                }
            } onCancel: {
                self.cancel()
            }
        }

        return DownloadTask<Value>(request: self, task: task, shouldAutomaticallyCancel: shouldAutomaticallyCancel)
    }
}

@available(macOS 10.15, iOS 13, tvOS 13, watchOS 6, *)
public struct DataStreamTask: Sendable {
    public typealias Stream<Success, Failure: Error> = StreamOf<DataStreamRequest.Stream<Success, Failure>>

    private let request: DataStreamRequest

    fileprivate init(request: DataStreamRequest) {
        self.request = request
    }

    public func streamingData(automaticallyCancelling shouldAutomaticallyCancel: Bool = true, bufferingPolicy: Stream<Data, Never>.BufferingPolicy = .unbounded) -> Stream<Data, Never> {
        createStream(automaticallyCancelling: shouldAutomaticallyCancel, bufferingPolicy: bufferingPolicy) { onStream in
            request.responseStream(on: .streamCompletionQueue(forRequestID: request.id), stream: onStream)
        }
    }

    public func streamingStrings(automaticallyCancelling shouldAutomaticallyCancel: Bool = true, bufferingPolicy: Stream<String, Never>.BufferingPolicy = .unbounded) -> Stream<String, Never> {
        createStream(automaticallyCancelling: shouldAutomaticallyCancel, bufferingPolicy: bufferingPolicy) { onStream in
            request.responseStreamString(on: .streamCompletionQueue(forRequestID: request.id), stream: onStream)
        }
    }

    public func streamingDecodables<T>(_ type: T.Type = T.self,
                                       automaticallyCancelling shouldAutomaticallyCancel: Bool = true,
                                       bufferingPolicy: Stream<T, AFError>.BufferingPolicy = .unbounded)
        -> Stream<T, AFError> where T: Decodable & Sendable {
        streamingResponses(serializedUsing: DecodableStreamSerializer<T>(),
                           automaticallyCancelling: shouldAutomaticallyCancel,
                           bufferingPolicy: bufferingPolicy)
    }

    public func streamingResponses<Serializer: DataStreamSerializer>(serializedUsing serializer: Serializer,
                                                                     automaticallyCancelling shouldAutomaticallyCancel: Bool = true,
                                                                     bufferingPolicy: Stream<Serializer.SerializedObject, AFError>.BufferingPolicy = .unbounded)
        -> Stream<Serializer.SerializedObject, AFError> {
        createStream(automaticallyCancelling: shouldAutomaticallyCancel, bufferingPolicy: bufferingPolicy) { onStream in
            request.responseStream(using: serializer,
                                   on: .streamCompletionQueue(forRequestID: request.id),
                                   stream: onStream)
        }
    }

    private func createStream<Success, Failure: Error>(automaticallyCancelling shouldAutomaticallyCancel: Bool = true,
                                                       bufferingPolicy: Stream<Success, Failure>.BufferingPolicy = .unbounded,
                                                       forResponse onResponse: @Sendable @escaping (@escaping @Sendable (DataStreamRequest.Stream<Success, Failure>) -> Void) -> Void)
        -> Stream<Success, Failure> {
        StreamOf(bufferingPolicy: bufferingPolicy) {
            guard shouldAutomaticallyCancel,
                  request.isInitialized || request.isResumed || request.isSuspended else { return }

            cancel()
        } builder: { continuation in
            onResponse { stream in
                continuation.yield(stream)
                if case .complete = stream.event {
                    continuation.finish()
                }
            }
        }
    }

    public func cancel() {
        request.cancel()
    }

    public func resume() {
        request.resume()
    }

    public func suspend() {
        request.suspend()
    }
}

@available(macOS 10.15, iOS 13, tvOS 13, watchOS 6, *)
extension DataStreamRequest {
    public func httpResponses(bufferingPolicy: StreamOf<HTTPURLResponse>.BufferingPolicy = .unbounded) -> StreamOf<HTTPURLResponse> {
        stream(bufferingPolicy: bufferingPolicy) { [unowned self] continuation in
            onHTTPResponse(on: underlyingQueue) { response in
                continuation.yield(response)
            }
        }
    }

    @_disfavoredOverload
    @discardableResult
    public func onHTTPResponse(perform handler: @escaping @Sendable (HTTPURLResponse) async -> ResponseDisposition) -> Self {
        onHTTPResponse(on: underlyingQueue) { response, completionHandler in
            Task {
                let disposition = await handler(response)
                completionHandler(disposition)
            }
        }

        return self
    }

    @discardableResult
    public func onHTTPResponse(perform handler: @escaping @Sendable (HTTPURLResponse) async -> Void) -> Self {
        onHTTPResponse { response in
            await handler(response)
            return .allow
        }

        return self
    }

    public func streamTask() -> DataStreamTask {
        DataStreamTask(request: self)
    }
}

#if canImport(Darwin) && !canImport(FoundationNetworking)

@available(macOS 10.15, iOS 13, tvOS 13, watchOS 6, *)
@_spi(WebSocket) public struct WebSocketTask: Sendable {
    private let request: WebSocketRequest

    fileprivate init(request: WebSocketRequest) {
        self.request = request
    }

    public typealias EventStreamOf<Success, Failure: Error> = StreamOf<WebSocketRequest.Event<Success, Failure>>

    public func streamingMessageEvents(
        automaticallyCancelling shouldAutomaticallyCancel: Bool = true,
        bufferingPolicy: EventStreamOf<URLSessionWebSocketTask.Message, Never>.BufferingPolicy = .unbounded
    ) -> EventStreamOf<URLSessionWebSocketTask.Message, Never> {
        createStream(automaticallyCancelling: shouldAutomaticallyCancel,
                     bufferingPolicy: bufferingPolicy,
                     transform: { $0 }) { onEvent in
            request.streamMessageEvents(on: .streamCompletionQueue(forRequestID: request.id), handler: onEvent)
        }
    }

    public func streamingMessages(
        automaticallyCancelling shouldAutomaticallyCancel: Bool = true,
        bufferingPolicy: StreamOf<URLSessionWebSocketTask.Message>.BufferingPolicy = .unbounded
    ) -> StreamOf<URLSessionWebSocketTask.Message> {
        createStream(automaticallyCancelling: shouldAutomaticallyCancel,
                     bufferingPolicy: bufferingPolicy,
                     transform: { $0.message }) { onEvent in
            request.streamMessageEvents(on: .streamCompletionQueue(forRequestID: request.id), handler: onEvent)
        }
    }

    public func streamingDecodableEvents<Value: Decodable & Sendable>(
        _ type: Value.Type = Value.self,
        automaticallyCancelling shouldAutomaticallyCancel: Bool = true,
        using decoder: any DataDecoder = JSONDecoder(),
        bufferingPolicy: EventStreamOf<Value, any Error>.BufferingPolicy = .unbounded
    ) -> EventStreamOf<Value, any Error> {
        createStream(automaticallyCancelling: shouldAutomaticallyCancel,
                     bufferingPolicy: bufferingPolicy,
                     transform: { $0 }) { onEvent in
            request.streamDecodableEvents(Value.self,
                                          on: .streamCompletionQueue(forRequestID: request.id),
                                          using: decoder,
                                          handler: onEvent)
        }
    }

    public func streamingDecodable<Value: Decodable & Sendable>(
        _ type: Value.Type = Value.self,
        automaticallyCancelling shouldAutomaticallyCancel: Bool = true,
        using decoder: any DataDecoder = JSONDecoder(),
        bufferingPolicy: StreamOf<Value>.BufferingPolicy = .unbounded
    ) -> StreamOf<Value> {
        createStream(automaticallyCancelling: shouldAutomaticallyCancel,
                     bufferingPolicy: bufferingPolicy,
                     transform: { $0.message }) { onEvent in
            request.streamDecodableEvents(Value.self,
                                          on: .streamCompletionQueue(forRequestID: request.id),
                                          using: decoder,
                                          handler: onEvent)
        }
    }

    private func createStream<Success, Value, Failure: Error>(
        automaticallyCancelling shouldAutomaticallyCancel: Bool,
        bufferingPolicy: StreamOf<Value>.BufferingPolicy,
        transform: @escaping @Sendable (WebSocketRequest.Event<Success, Failure>) -> Value?,
        forResponse onResponse: @Sendable @escaping (@escaping @Sendable (WebSocketRequest.Event<Success, Failure>) -> Void) -> Void
    ) -> StreamOf<Value> {
        StreamOf(bufferingPolicy: bufferingPolicy) {
            guard shouldAutomaticallyCancel,
                  request.isInitialized || request.isResumed || request.isSuspended else { return }

            cancel()
        } builder: { continuation in
            onResponse { event in
                if let value = transform(event) {
                    continuation.yield(value)
                }

                if case .completed = event.kind {
                    continuation.finish()
                }
            }
        }
    }

    public func send(_ message: URLSessionWebSocketTask.Message) async throws {
        try await withCheckedThrowingContinuation { continuation in
            request.send(message, queue: .streamCompletionQueue(forRequestID: request.id)) { result in
                continuation.resume(with: result)
            }
        }
    }

    public func close(sending closeCode: URLSessionWebSocketTask.CloseCode, reason: Data? = nil) {
        request.close(sending: closeCode, reason: reason)
    }

    public func cancel() {
        request.cancel()
    }

    public func resume() {
        request.resume()
    }

    public func suspend() {
        request.suspend()
    }
}

@available(macOS 10.15, iOS 13, tvOS 13, watchOS 6, *)
extension WebSocketRequest {
    public func webSocketTask() -> WebSocketTask {
        WebSocketTask(request: self)
    }
}
#endif

extension DispatchQueue {
    fileprivate static let singleEventQueue = DispatchQueue(label: "org.alamofire.concurrencySingleEventQueue",
                                                            attributes: .concurrent)

    fileprivate static func streamCompletionQueue(forRequestID id: UUID) -> DispatchQueue {
        DispatchQueue(label: "org.alamofire.concurrencyStreamCompletionQueue-\(id)", target: .singleEventQueue)
    }
}

@available(macOS 10.15, iOS 13, tvOS 13, watchOS 6, *)
public struct StreamOf<Element>: AsyncSequence {
    public typealias AsyncIterator = Iterator
    public typealias BufferingPolicy = AsyncStream<Element>.Continuation.BufferingPolicy
    fileprivate typealias Continuation = AsyncStream<Element>.Continuation

    private let bufferingPolicy: BufferingPolicy
    private let onTermination: (() -> Void)?
    private let builder: (Continuation) -> Void

    fileprivate init(bufferingPolicy: BufferingPolicy = .unbounded,
                     onTermination: (() -> Void)? = nil,
                     builder: @escaping (Continuation) -> Void) {
        self.bufferingPolicy = bufferingPolicy
        self.onTermination = onTermination
        self.builder = builder
    }

    public func makeAsyncIterator() -> Iterator {
        var continuation: AsyncStream<Element>.Continuation?
        let stream = AsyncStream<Element>(bufferingPolicy: bufferingPolicy) { innerContinuation in
            continuation = innerContinuation
            builder(innerContinuation)
        }

        return Iterator(iterator: stream.makeAsyncIterator()) {
            continuation?.finish()
            onTermination?()
        }
    }

    public struct Iterator: AsyncIteratorProtocol {
        private final class Token {
            private let onDeinit: () -> Void

            init(onDeinit: @escaping () -> Void) {
                self.onDeinit = onDeinit
            }

            deinit {
                onDeinit()
            }
        }

        private var iterator: AsyncStream<Element>.AsyncIterator
        private let token: Token

        init(iterator: AsyncStream<Element>.AsyncIterator, onCancellation: @escaping () -> Void) {
            self.iterator = iterator
            token = Token(onDeinit: onCancellation)
        }

        public mutating func next() async -> Element? {
            await iterator.next()
        }
    }
}

#endif
