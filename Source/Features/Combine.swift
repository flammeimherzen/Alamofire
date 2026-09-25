
#if !((os(iOS) && (arch(i386) || arch(arm))) || os(Windows) || os(Linux) || os(Android))

import Combine
import Dispatch
import Foundation

@available(macOS 10.15, iOS 13, watchOS 6, tvOS 13, *)
public struct DataResponsePublisher<Value: Sendable>: Publisher {
    public typealias Output = DataResponse<Value, AFError>
    public typealias Failure = Never

    private typealias Handler = (@escaping @Sendable (_ response: DataResponse<Value, AFError>) -> Void) -> DataRequest

    private let request: DataRequest
    private let responseHandler: Handler

    public init<Serializer: ResponseSerializer>(_ request: DataRequest, queue: DispatchQueue, serializer: Serializer)
        where Value == Serializer.SerializedObject {
        self.request = request
        responseHandler = { request.response(queue: queue, responseSerializer: serializer, completionHandler: $0) }
    }

    public init<Serializer: DataResponseSerializerProtocol>(_ request: DataRequest,
                                                            queue: DispatchQueue,
                                                            serializer: Serializer)
        where Value == Serializer.SerializedObject {
        self.request = request
        responseHandler = { request.response(queue: queue, responseSerializer: serializer, completionHandler: $0) }
    }

    public func result() -> AnyPublisher<Result<Value, AFError>, Never> {
        map(\.result).eraseToAnyPublisher()
    }

    public func value() -> AnyPublisher<Value, AFError> {
        setFailureType(to: AFError.self).flatMap(\.result.publisher).eraseToAnyPublisher()
    }

    public func receive<S>(subscriber: S) where S: Subscriber & Sendable, DataResponsePublisher.Failure == S.Failure, DataResponsePublisher.Output == S.Input {
        subscriber.receive(subscription: Inner(request: request,
                                               responseHandler: responseHandler,
                                               downstream: subscriber))
    }

    private final class Inner<Downstream: Subscriber & Sendable>: Subscription
        where Downstream.Input == Output {
        typealias Failure = Downstream.Failure

        private let downstream: Protected<Downstream?>
        private let request: DataRequest
        private let responseHandler: Handler

        init(request: DataRequest, responseHandler: @escaping Handler, downstream: Downstream) {
            self.request = request
            self.responseHandler = responseHandler
            self.downstream = Protected(downstream)
        }

        func request(_ demand: Subscribers.Demand) {
            assert(demand > 0)

            guard let downstream = downstream.read({ $0 }) else { return }

            self.downstream.write(nil)
            responseHandler { response in
                _ = downstream.receive(response)
                downstream.receive(completion: .finished)
            }.resume()
        }

        func cancel() {
            request.cancel()
            downstream.write(nil)
        }
    }
}

@available(macOS 10.15, iOS 13, watchOS 6, tvOS 13, *)
extension DataResponsePublisher where Value == Data? {
    @available(macOS 10.15, iOS 13, watchOS 6, tvOS 13, *)
    public init(_ request: DataRequest, queue: DispatchQueue) {
        self.request = request
        responseHandler = { request.response(queue: queue, completionHandler: $0) }
    }
}

extension DataRequest {
    @available(macOS 10.15, iOS 13, watchOS 6, tvOS 13, *)
    public func publishResponse<Serializer: ResponseSerializer, T>(using serializer: Serializer, on queue: DispatchQueue = .main) -> DataResponsePublisher<T>
        where Serializer.SerializedObject == T {
        DataResponsePublisher(self, queue: queue, serializer: serializer)
    }

    @available(macOS 10.15, iOS 13, watchOS 6, tvOS 13, *)
    public func publishData(queue: DispatchQueue = .main,
                            preprocessor: any DataPreprocessor = DataResponseSerializer.defaultDataPreprocessor,
                            emptyResponseCodes: Set<Int> = DataResponseSerializer.defaultEmptyResponseCodes,
                            emptyRequestMethods: Set<HTTPMethod> = DataResponseSerializer.defaultEmptyRequestMethods) -> DataResponsePublisher<Data> {
        publishResponse(using: DataResponseSerializer(dataPreprocessor: preprocessor,
                                                      emptyResponseCodes: emptyResponseCodes,
                                                      emptyRequestMethods: emptyRequestMethods),
                        on: queue)
    }

    @available(macOS 10.15, iOS 13, watchOS 6, tvOS 13, *)
    public func publishString(queue: DispatchQueue = .main,
                              preprocessor: any DataPreprocessor = StringResponseSerializer.defaultDataPreprocessor,
                              encoding: String.Encoding? = nil,
                              emptyResponseCodes: Set<Int> = StringResponseSerializer.defaultEmptyResponseCodes,
                              emptyRequestMethods: Set<HTTPMethod> = StringResponseSerializer.defaultEmptyRequestMethods) -> DataResponsePublisher<String> {
        publishResponse(using: StringResponseSerializer(dataPreprocessor: preprocessor,
                                                        encoding: encoding,
                                                        emptyResponseCodes: emptyResponseCodes,
                                                        emptyRequestMethods: emptyRequestMethods),
                        on: queue)
    }

    @_disfavoredOverload
    @available(macOS 10.15, iOS 13, watchOS 6, tvOS 13, *)
    @available(*, deprecated, message: "Renamed publishDecodable(type:queue:preprocessor:decoder:emptyResponseCodes:emptyRequestMethods).")
    public func publishDecodable<T: Decodable>(type: T.Type = T.self,
                                               queue: DispatchQueue = .main,
                                               preprocessor: any DataPreprocessor = DecodableResponseSerializer<T>.defaultDataPreprocessor,
                                               decoder: any DataDecoder = JSONDecoder(),
                                               emptyResponseCodes: Set<Int> = DecodableResponseSerializer<T>.defaultEmptyResponseCodes,
                                               emptyResponseMethods: Set<HTTPMethod> = DecodableResponseSerializer<T>.defaultEmptyRequestMethods) -> DataResponsePublisher<T> {
        publishResponse(using: DecodableResponseSerializer(dataPreprocessor: preprocessor,
                                                           decoder: decoder,
                                                           emptyResponseCodes: emptyResponseCodes,
                                                           emptyRequestMethods: emptyResponseMethods),
                        on: queue)
    }

    @available(macOS 10.15, iOS 13, watchOS 6, tvOS 13, *)
    public func publishDecodable<T: Decodable>(type: T.Type = T.self,
                                               queue: DispatchQueue = .main,
                                               preprocessor: any DataPreprocessor = DecodableResponseSerializer<T>.defaultDataPreprocessor,
                                               decoder: any DataDecoder = JSONDecoder(),
                                               emptyResponseCodes: Set<Int> = DecodableResponseSerializer<T>.defaultEmptyResponseCodes,
                                               emptyRequestMethods: Set<HTTPMethod> = DecodableResponseSerializer<T>.defaultEmptyRequestMethods) -> DataResponsePublisher<T> {
        publishResponse(using: DecodableResponseSerializer(dataPreprocessor: preprocessor,
                                                           decoder: decoder,
                                                           emptyResponseCodes: emptyResponseCodes,
                                                           emptyRequestMethods: emptyRequestMethods),
                        on: queue)
    }

    @available(macOS 10.15, iOS 13, watchOS 6, tvOS 13, *)
    public func publishUnserialized(queue: DispatchQueue = .main) -> DataResponsePublisher<Data?> {
        DataResponsePublisher(self, queue: queue)
    }
}

@available(macOS 10.15, iOS 13, watchOS 6, tvOS 13, *)
public struct DataStreamPublisher<Value: Sendable>: Publisher {
    public typealias Output = DataStreamRequest.Stream<Value, AFError>
    public typealias Failure = Never

    private typealias Handler = (@escaping DataStreamRequest.Handler<Value, AFError>) -> DataStreamRequest

    private let request: DataStreamRequest
    private let streamHandler: Handler

    public init<Serializer: DataStreamSerializer>(_ request: DataStreamRequest, queue: DispatchQueue, serializer: Serializer)
        where Value == Serializer.SerializedObject {
        self.request = request
        streamHandler = { request.responseStream(using: serializer, on: queue, stream: $0) }
    }

    public func result() -> AnyPublisher<Result<Value, AFError>, Never> {
        compactMap { stream in
            switch stream.event {
            case let .stream(result):
                result
            case let .complete(completion):
                completion.error.map(Result.failure)
            }
        }
        .eraseToAnyPublisher()
    }

    public func value() -> AnyPublisher<Value, AFError> {
        result().setFailureType(to: AFError.self).flatMap(\.publisher).eraseToAnyPublisher()
    }

    public func receive<S>(subscriber: S) where S: Subscriber & Sendable, DataStreamPublisher.Failure == S.Failure, DataStreamPublisher.Output == S.Input {
        subscriber.receive(subscription: Inner(request: request,
                                               streamHandler: streamHandler,
                                               downstream: subscriber))
    }

    private final class Inner<Downstream: Subscriber & Sendable>: Subscription
        where Downstream.Input == Output {
        typealias Failure = Downstream.Failure

        private let downstream: Protected<Downstream?>
        private let request: DataStreamRequest
        private let streamHandler: Handler

        init(request: DataStreamRequest, streamHandler: @escaping Handler, downstream: Downstream) {
            self.request = request
            self.streamHandler = streamHandler
            self.downstream = Protected(downstream)
        }

        func request(_ demand: Subscribers.Demand) {
            assert(demand > 0)

            guard let downstream = downstream.read({ $0 }) else { return }

            self.downstream.write(nil)
            streamHandler { stream in
                _ = downstream.receive(stream)
                if case .complete = stream.event {
                    downstream.receive(completion: .finished)
                }
            }.resume()
        }

        func cancel() {
            request.cancel()
            downstream.write(nil)
        }
    }
}

extension DataStreamRequest {
    @available(macOS 10.15, iOS 13, watchOS 6, tvOS 13, *)
    public func publishStream<Serializer: DataStreamSerializer>(using serializer: Serializer,
                                                                on queue: DispatchQueue = .main) -> DataStreamPublisher<Serializer.SerializedObject> {
        DataStreamPublisher(self, queue: queue, serializer: serializer)
    }

    @available(macOS 10.15, iOS 13, watchOS 6, tvOS 13, *)
    public func publishData(queue: DispatchQueue = .main) -> DataStreamPublisher<Data> {
        publishStream(using: PassthroughStreamSerializer(), on: queue)
    }

    @available(macOS 10.15, iOS 13, watchOS 6, tvOS 13, *)
    public func publishString(queue: DispatchQueue = .main) -> DataStreamPublisher<String> {
        publishStream(using: StringStreamSerializer(), on: queue)
    }

    @available(macOS 10.15, iOS 13, watchOS 6, tvOS 13, *)
    public func publishDecodable<T: Decodable>(type: T.Type = T.self,
                                               queue: DispatchQueue = .main,
                                               decoder: any DataDecoder = JSONDecoder(),
                                               preprocessor: any DataPreprocessor = PassthroughPreprocessor()) -> DataStreamPublisher<T> {
        publishStream(using: DecodableStreamSerializer(decoder: decoder,
                                                       dataPreprocessor: preprocessor),
                      on: queue)
    }
}

@available(macOS 10.15, iOS 13, watchOS 6, tvOS 13, *)
public struct DownloadResponsePublisher<Value: Sendable>: Publisher {
    public typealias Output = DownloadResponse<Value, AFError>
    public typealias Failure = Never

    private typealias Handler = (@escaping @Sendable (_ response: DownloadResponse<Value, AFError>) -> Void) -> DownloadRequest

    private let request: DownloadRequest
    private let responseHandler: Handler

    public init<Serializer: ResponseSerializer>(_ request: DownloadRequest, queue: DispatchQueue, serializer: Serializer)
        where Value == Serializer.SerializedObject {
        self.request = request
        responseHandler = { request.response(queue: queue, responseSerializer: serializer, completionHandler: $0) }
    }

    @available(macOS 10.15, iOS 13, watchOS 6, tvOS 13, *)
    public init<Serializer: DownloadResponseSerializerProtocol>(_ request: DownloadRequest,
                                                                queue: DispatchQueue,
                                                                serializer: Serializer)
        where Value == Serializer.SerializedObject {
        self.request = request
        responseHandler = { request.response(queue: queue, responseSerializer: serializer, completionHandler: $0) }
    }

    public func result() -> AnyPublisher<Result<Value, AFError>, Never> {
        map(\.result).eraseToAnyPublisher()
    }

    public func value() -> AnyPublisher<Value, AFError> {
        setFailureType(to: AFError.self).flatMap(\.result.publisher).eraseToAnyPublisher()
    }

    public func receive<S>(subscriber: S) where S: Subscriber & Sendable, DownloadResponsePublisher.Failure == S.Failure, DownloadResponsePublisher.Output == S.Input {
        subscriber.receive(subscription: Inner(request: request,
                                               responseHandler: responseHandler,
                                               downstream: subscriber))
    }

    private final class Inner<Downstream: Subscriber & Sendable>: Subscription
        where Downstream.Input == Output {
        typealias Failure = Downstream.Failure

        private let downstream: Protected<Downstream?>
        private let request: DownloadRequest
        private let responseHandler: Handler

        init(request: DownloadRequest, responseHandler: @escaping Handler, downstream: Downstream) {
            self.request = request
            self.responseHandler = responseHandler
            self.downstream = Protected(downstream)
        }

        func request(_ demand: Subscribers.Demand) {
            assert(demand > 0)

            guard let downstream = downstream.read({ $0 }) else { return }

            self.downstream.write(nil)
            responseHandler { response in
                _ = downstream.receive(response)
                downstream.receive(completion: .finished)
            }.resume()
        }

        func cancel() {
            request.cancel()
            downstream.write(nil)
        }
    }
}

extension DownloadRequest {
    @available(macOS 10.15, iOS 13, watchOS 6, tvOS 13, *)
    public func publishResponse<Serializer: ResponseSerializer, T>(using serializer: Serializer, on queue: DispatchQueue = .main) -> DownloadResponsePublisher<T>
        where Serializer.SerializedObject == T {
        DownloadResponsePublisher(self, queue: queue, serializer: serializer)
    }

    @available(macOS 10.15, iOS 13, watchOS 6, tvOS 13, *)
    public func publishResponse<Serializer: DownloadResponseSerializerProtocol, T>(using serializer: Serializer, on queue: DispatchQueue = .main) -> DownloadResponsePublisher<T>
        where Serializer.SerializedObject == T {
        DownloadResponsePublisher(self, queue: queue, serializer: serializer)
    }

    @available(macOS 10.15, iOS 13, watchOS 6, tvOS 13, *)
    public func publishURL(queue: DispatchQueue = .main) -> DownloadResponsePublisher<URL> {
        publishResponse(using: URLResponseSerializer(), on: queue)
    }

    @available(macOS 10.15, iOS 13, watchOS 6, tvOS 13, *)
    public func publishData(queue: DispatchQueue = .main,
                            preprocessor: any DataPreprocessor = DataResponseSerializer.defaultDataPreprocessor,
                            emptyResponseCodes: Set<Int> = DataResponseSerializer.defaultEmptyResponseCodes,
                            emptyRequestMethods: Set<HTTPMethod> = DataResponseSerializer.defaultEmptyRequestMethods) -> DownloadResponsePublisher<Data> {
        publishResponse(using: DataResponseSerializer(dataPreprocessor: preprocessor,
                                                      emptyResponseCodes: emptyResponseCodes,
                                                      emptyRequestMethods: emptyRequestMethods),
                        on: queue)
    }

    @available(macOS 10.15, iOS 13, watchOS 6, tvOS 13, *)
    public func publishString(queue: DispatchQueue = .main,
                              preprocessor: any DataPreprocessor = StringResponseSerializer.defaultDataPreprocessor,
                              encoding: String.Encoding? = nil,
                              emptyResponseCodes: Set<Int> = StringResponseSerializer.defaultEmptyResponseCodes,
                              emptyRequestMethods: Set<HTTPMethod> = StringResponseSerializer.defaultEmptyRequestMethods) -> DownloadResponsePublisher<String> {
        publishResponse(using: StringResponseSerializer(dataPreprocessor: preprocessor,
                                                        encoding: encoding,
                                                        emptyResponseCodes: emptyResponseCodes,
                                                        emptyRequestMethods: emptyRequestMethods),
                        on: queue)
    }

    @_disfavoredOverload
    @available(macOS 10.15, iOS 13, watchOS 6, tvOS 13, *)
    @available(*, deprecated, message: "Renamed publishDecodable(type:queue:preprocessor:decoder:emptyResponseCodes:emptyRequestMethods).")
    public func publishDecodable<T: Decodable>(type: T.Type = T.self,
                                               queue: DispatchQueue = .main,
                                               preprocessor: any DataPreprocessor = DecodableResponseSerializer<T>.defaultDataPreprocessor,
                                               decoder: any DataDecoder = JSONDecoder(),
                                               emptyResponseCodes: Set<Int> = DecodableResponseSerializer<T>.defaultEmptyResponseCodes,
                                               emptyResponseMethods: Set<HTTPMethod> = DecodableResponseSerializer<T>.defaultEmptyRequestMethods) -> DownloadResponsePublisher<T> {
        publishResponse(using: DecodableResponseSerializer(dataPreprocessor: preprocessor,
                                                           decoder: decoder,
                                                           emptyResponseCodes: emptyResponseCodes,
                                                           emptyRequestMethods: emptyResponseMethods),
                        on: queue)
    }

    @available(macOS 10.15, iOS 13, watchOS 6, tvOS 13, *)
    public func publishDecodable<T: Decodable>(type: T.Type = T.self,
                                               queue: DispatchQueue = .main,
                                               preprocessor: any DataPreprocessor = DecodableResponseSerializer<T>.defaultDataPreprocessor,
                                               decoder: any DataDecoder = JSONDecoder(),
                                               emptyResponseCodes: Set<Int> = DecodableResponseSerializer<T>.defaultEmptyResponseCodes,
                                               emptyRequestMethods: Set<HTTPMethod> = DecodableResponseSerializer<T>.defaultEmptyRequestMethods) -> DownloadResponsePublisher<T> {
        publishResponse(using: DecodableResponseSerializer(dataPreprocessor: preprocessor,
                                                           decoder: decoder,
                                                           emptyResponseCodes: emptyResponseCodes,
                                                           emptyRequestMethods: emptyRequestMethods),
                        on: queue)
    }
}

@available(macOS 10.15, iOS 13, watchOS 6, tvOS 13, *)
extension DownloadResponsePublisher where Value == URL? {
    @available(macOS 10.15, iOS 13, watchOS 6, tvOS 13, *)
    public init(_ request: DownloadRequest, queue: DispatchQueue) {
        self.request = request
        responseHandler = { request.response(queue: queue, completionHandler: $0) }
    }
}

extension DownloadRequest {
    @available(macOS 10.15, iOS 13, watchOS 6, tvOS 13, *)
    public func publishUnserialized(on queue: DispatchQueue = .main) -> DownloadResponsePublisher<URL?> {
        DownloadResponsePublisher(self, queue: queue)
    }
}

#endif
