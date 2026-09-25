
#if canImport(Darwin) && !canImport(FoundationNetworking)

import Foundation

@available(macOS 10.15, iOS 13, tvOS 13, watchOS 6, *)
@_spi(WebSocket) public final class WebSocketRequest: Request, @unchecked Sendable {
    enum IncomingEvent {
        case connected(protocol: String?)
        case receivedMessage(URLSessionWebSocketTask.Message)
        case disconnected(closeCode: URLSessionWebSocketTask.CloseCode, reason: Data?)
        case completed(Completion)
    }

    public struct Event<Success: Sendable, Failure: Error>: Sendable {
        public enum Kind: Sendable {
            case connected(protocol: String?)
            case receivedMessage(Success)
            case serializerFailed(Failure)
            case disconnected(closeCode: URLSessionWebSocketTask.CloseCode, reason: Data?)
            case completed(Completion)
        }

        weak var socket: WebSocketRequest?

        public let kind: Kind
        public var message: Success? {
            guard case let .receivedMessage(message) = kind else { return nil }

            return message
        }

        init(socket: WebSocketRequest, kind: Kind) {
            self.socket = socket
            self.kind = kind
        }

        public func close(sending closeCode: URLSessionWebSocketTask.CloseCode, reason: Data? = nil) {
            socket?.close(sending: closeCode, reason: reason)
        }

        public func cancel() {
            socket?.cancel()
        }

        public func sendPing(respondingOn queue: DispatchQueue = .main, onResponse: @escaping @Sendable (PingResponse) -> Void) {
            socket?.sendPing(respondingOn: queue, onResponse: onResponse)
        }
    }

    public struct Completion: Sendable {
        public let request: URLRequest?
        public let response: HTTPURLResponse?
        public let metrics: URLSessionTaskMetrics?
        public let error: AFError?
    }

    public struct Configuration {
        public static var `default`: Self { Self() }

        public static func `protocol`(_ protocol: String) -> Self {
            Self(protocol: `protocol`)
        }

        public static func maximumMessageSize(_ maximumMessageSize: Int) -> Self {
            Self(maximumMessageSize: maximumMessageSize)
        }

        public static func pingInterval(_ pingInterval: TimeInterval) -> Self {
            Self(pingInterval: pingInterval)
        }

        public let `protocol`: String?
        public let maximumMessageSize: Int
        public let pingInterval: TimeInterval?

        init(protocol: String? = nil, maximumMessageSize: Int = 1_048_576, pingInterval: TimeInterval? = nil) {
            self.protocol = `protocol`
            self.maximumMessageSize = maximumMessageSize
            self.pingInterval = pingInterval
        }
    }

    public enum PingResponse: Sendable {
        public struct Pong: Sendable {
            let start: Date
            let end: Date
            let latency: TimeInterval
        }

        case pong(Pong)
        case error(any Error)
        case unsent
    }

    struct SocketMutableState {
        var enqueuedSends: [(message: URLSessionWebSocketTask.Message,
                             queue: DispatchQueue,
                             completionHandler: @Sendable (Result<Void, any Error>) -> Void)] = []
        var handlers: [(queue: DispatchQueue, handler: (_ event: IncomingEvent) -> Void)] = []
        var pingTimerItem: DispatchWorkItem?
    }

    let socketMutableState = Protected(SocketMutableState())

    var socket: URLSessionWebSocketTask? {
        task as? URLSessionWebSocketTask
    }

    public let convertible: any URLRequestConvertible
    public let configuration: Configuration

    init(id: UUID = UUID(),
         convertible: any URLRequestConvertible,
         configuration: Configuration,
         underlyingQueue: DispatchQueue,
         serializationQueue: DispatchQueue,
         eventMonitor: (any EventMonitor)?,
         interceptor: (any RequestInterceptor)?,
         shouldAutomaticallyResume: Bool?,
         delegate: any RequestDelegate) {
        self.convertible = convertible
        self.configuration = configuration

        super.init(id: id,
                   underlyingQueue: underlyingQueue,
                   serializationQueue: serializationQueue,
                   eventMonitor: eventMonitor,
                   interceptor: interceptor,
                   shouldAutomaticallyResume: shouldAutomaticallyResume,
                   delegate: delegate)
    }

    override func task(for request: URLRequest, using session: URLSession) -> URLSessionTask {
        var copiedRequest = request
        let task: URLSessionWebSocketTask
        if let `protocol` = configuration.protocol {
            copiedRequest.headers.update(.websocketProtocol(`protocol`))
            task = session.webSocketTask(with: copiedRequest)
        } else {
            task = session.webSocketTask(with: copiedRequest)
        }
        task.maximumMessageSize = configuration.maximumMessageSize

        return task
    }

    override func didCreateTask(_ task: URLSessionTask) {
        super.didCreateTask(task)

        guard let webSocketTask = task as? URLSessionWebSocketTask else {
            fatalError("Invalid task of type \(task.self) created for WebSocketRequest.")
        }
        listen(to: webSocketTask)

        socketMutableState.write { state in
            guard !state.enqueuedSends.isEmpty else { return }

            let sends = state.enqueuedSends
            self.underlyingQueue.async {
                for send in sends {
                    webSocketTask.send(send.message) { error in
                        send.queue.async {
                            send.completionHandler(Result(value: (), error: error))
                        }
                    }
                }
            }

            state.enqueuedSends = []
        }
    }

    func didClose() {
        dispatchPrecondition(condition: .onQueue(underlyingQueue))

        mutableState.write { mutableState in
            if case let .sessionTaskFailed(error) = mutableState.error, (error as? URLError)?.code == .cancelled {
                mutableState.error = nil
            }
        }

        eventMonitor?.requestDidCancel(self)
    }

    @discardableResult
    public func close(sending closeCode: URLSessionWebSocketTask.CloseCode, reason: Data? = nil) -> Self {
        cancelAutomaticPing()

        mutableState.write { mutableState in
            guard mutableState.state.canTransitionTo(.cancelled) else { return }

            mutableState.state = .cancelled

            underlyingQueue.async { self.didClose() }

            guard let task = mutableState.tasks.last, task.state != .completed else {
                underlyingQueue.async { self.finish() }
                return
            }

            task.resume()
            (mutableState.tasks.last as? URLSessionWebSocketTask)?.cancel(with: closeCode, reason: reason)
            underlyingQueue.async { self.didCancelTask(task) }
        }

        return self
    }

    @discardableResult
    override public func cancel() -> Self {
        cancelAutomaticPing()

        return super.cancel()
    }

    func didConnect(protocol: String?) {
        dispatchPrecondition(condition: .onQueue(underlyingQueue))

        socketMutableState.read { state in
            for handler in state.handlers {
                handler.handler(.connected(protocol: `protocol`))
            }
        }

        if let pingInterval = configuration.pingInterval {
            startAutomaticPing(every: pingInterval)
        }
    }

    @preconcurrency
    public func sendPing(respondingOn queue: DispatchQueue = .main, onResponse: @escaping @Sendable (PingResponse) -> Void) {
        guard isResumed else {
            queue.async { onResponse(.unsent) }
            return
        }

        let start = Date()
        let startTimestamp = ProcessInfo.processInfo.systemUptime
        socket?.sendPing { error in
            if let error {
                queue.async {
                    onResponse(.error(error))
                }
            } else {
                let end = Date()
                let endTimestamp = ProcessInfo.processInfo.systemUptime
                let pong = PingResponse.Pong(start: start, end: end, latency: endTimestamp - startTimestamp)

                queue.async {
                    onResponse(.pong(pong))
                }
            }
        }
    }

    func startAutomaticPing(every pingInterval: TimeInterval) {
        socketMutableState.write { mutableState in
            guard isResumed else {
                defer { cancelAutomaticPing() }
                return
            }

            let item = DispatchWorkItem { [weak self] in
                guard let self, isResumed else { return }

                sendPing(respondingOn: underlyingQueue) { response in
                    guard case .pong = response else { return }

                    self.startAutomaticPing(every: pingInterval)
                }
            }

            mutableState.pingTimerItem = item
            underlyingQueue.asyncAfter(deadline: .now() + pingInterval, execute: item)
        }
    }

    @available(macOS 13, iOS 16, tvOS 16, watchOS 9, *)
    func startAutomaticPing(every duration: Duration) {
        let interval = TimeInterval(duration.components.seconds) + (Double(duration.components.attoseconds) / 1e18)
        startAutomaticPing(every: interval)
    }

    func cancelAutomaticPing() {
        socketMutableState.write { mutableState in
            mutableState.pingTimerItem?.cancel()
            mutableState.pingTimerItem = nil
        }
    }

    func didDisconnect(closeCode: URLSessionWebSocketTask.CloseCode, reason: Data?) {
        dispatchPrecondition(condition: .onQueue(underlyingQueue))

        cancelAutomaticPing()
        socketMutableState.read { state in
            for handler in state.handlers {
                handler.handler(.disconnected(closeCode: closeCode, reason: reason))
            }
        }
    }

    private func listen(to task: URLSessionWebSocketTask) {
        task.receive { result in
            switch result {
            case let .success(message):
                self.socketMutableState.read { state in
                    for handler in state.handlers {
                        handler.handler(.receivedMessage(message))
                    }
                }

                self.listen(to: task)
            case .failure:
                break
            }
        }
    }

    @preconcurrency
    @discardableResult
    public func streamSerializer<Serializer>(
        _ serializer: Serializer,
        on queue: DispatchQueue = .main,
        handler: @escaping @Sendable (_ event: Event<Serializer.Output, Serializer.Failure>) -> Void
    ) -> Self where Serializer: WebSocketMessageSerializer, Serializer.Failure == any Error {
        forIncomingEvent(on: queue) { [unowned self] incomingEvent in
            let event: Event<Serializer.Output, Serializer.Failure>
            switch incomingEvent {
            case let .connected(`protocol`):
                event = .init(socket: self, kind: .connected(protocol: `protocol`))
            case let .receivedMessage(message):
                do {
                    let serializedMessage = try serializer.decode(message)
                    event = .init(socket: self, kind: .receivedMessage(serializedMessage))
                } catch {
                    event = .init(socket: self, kind: .serializerFailed(error))
                }
            case let .disconnected(closeCode, reason):
                event = .init(socket: self, kind: .disconnected(closeCode: closeCode, reason: reason))
            case let .completed(completion):
                event = .init(socket: self, kind: .completed(completion))
            }

            queue.async { handler(event) }
        }
    }

    @preconcurrency
    @discardableResult
    public func streamDecodableEvents<Value>(
        _ type: Value.Type = Value.self,
        on queue: DispatchQueue = .main,
        using decoder: any DataDecoder = JSONDecoder(),
        handler: @escaping @Sendable (_ event: Event<Value, any Error>) -> Void
    ) -> Self where Value: Decodable {
        streamSerializer(DecodableWebSocketMessageDecoder<Value>(decoder: decoder), on: queue, handler: handler)
    }

    @preconcurrency
    @discardableResult
    public func streamDecodable<Value>(
        _ type: Value.Type = Value.self,
        on queue: DispatchQueue = .main,
        using decoder: any DataDecoder = JSONDecoder(),
        handler: @escaping @Sendable (_ value: Value) -> Void
    ) -> Self where Value: Decodable & Sendable {
        streamDecodableEvents(Value.self, on: queue) { event in
            event.message.map(handler)
        }
    }

    @preconcurrency
    @discardableResult
    public func streamMessageEvents(
        on queue: DispatchQueue = .main,
        handler: @escaping @Sendable (_ event: Event<URLSessionWebSocketTask.Message, Never>) -> Void
    ) -> Self {
        forIncomingEvent(on: queue) { [unowned self] incomingEvent in
            let event: Event<URLSessionWebSocketTask.Message, Never> = switch incomingEvent {
            case let .connected(`protocol`):
                .init(socket: self, kind: .connected(protocol: `protocol`))
            case let .receivedMessage(message):
                .init(socket: self, kind: .receivedMessage(message))
            case let .disconnected(closeCode, reason):
                .init(socket: self, kind: .disconnected(closeCode: closeCode, reason: reason))
            case let .completed(completion):
                .init(socket: self, kind: .completed(completion))
            }

            queue.async { handler(event) }
        }
    }

    @preconcurrency
    @discardableResult
    public func streamMessages(
        on queue: DispatchQueue = .main,
        handler: @escaping @Sendable (_ message: URLSessionWebSocketTask.Message) -> Void
    ) -> Self {
        streamMessageEvents(on: queue) { event in
            event.message.map(handler)
        }
    }

    func forIncomingEvent(on queue: DispatchQueue, handler: @escaping @Sendable (IncomingEvent) -> Void) -> Self {
        socketMutableState.write { state in
            state.handlers.append((queue: queue, handler: { [unowned self] incomingEvent in
                serializationQueue.async {
                    handler(incomingEvent)
                }
            }))
        }

        appendResponseSerializer {
            self.responseSerializerDidComplete {
                self.serializationQueue.async {
                    handler(.completed(.init(request: self.request,
                                             response: self.response,
                                             metrics: self.metrics,
                                             error: self.error)))
                }
            }
        }

        return self
    }

    @preconcurrency
    public func send(_ message: URLSessionWebSocketTask.Message,
                     queue: DispatchQueue = .main,
                     completionHandler: @escaping @Sendable (Result<Void, any Error>) -> Void) {
        guard !(isCancelled || isFinished) else { return }

        guard let socket else {
            socketMutableState.write { mutableState in
                mutableState.enqueuedSends.append((message, queue, completionHandler))
            }

            return
        }

        socket.send(message) { error in
            queue.async {
                completionHandler(Result(value: (), error: error))
            }
        }
    }
}

@available(macOS 10.15, iOS 13, tvOS 13, watchOS 6, *)
public protocol WebSocketMessageSerializer<Output, Failure>: Sendable {
    associatedtype Output: Sendable
    associatedtype Failure: Error = any Error

    func decode(_ message: URLSessionWebSocketTask.Message) throws -> Output
}

@available(macOS 10.15, iOS 13, tvOS 13, watchOS 6, *)
extension WebSocketMessageSerializer {
    public static func json<Value>(
        decoding _: Value.Type = Value.self,
        using decoder: JSONDecoder = JSONDecoder()
    ) -> DecodableWebSocketMessageDecoder<Value> where Self == DecodableWebSocketMessageDecoder<Value> {
        Self(decoder: decoder)
    }

    static var passthrough: PassthroughWebSocketMessageDecoder {
        PassthroughWebSocketMessageDecoder()
    }
}

@available(macOS 10.15, iOS 13, tvOS 13, watchOS 6, *)
struct PassthroughWebSocketMessageDecoder: WebSocketMessageSerializer {
    typealias Failure = Never

    func decode(_ message: URLSessionWebSocketTask.Message) -> URLSessionWebSocketTask.Message {
        message
    }
}

@available(macOS 10.15, iOS 13, tvOS 13, watchOS 6, *)
public struct DecodableWebSocketMessageDecoder<Value: Decodable & Sendable>: WebSocketMessageSerializer {
    public enum Error: Swift.Error {
        case decoding(any Swift.Error)
        case unknownMessage(description: String)
    }

    public let decoder: any DataDecoder

    public init(decoder: any DataDecoder) {
        self.decoder = decoder
    }

    public func decode(_ message: URLSessionWebSocketTask.Message) throws -> Value {
        let data: Data
        switch message {
        case let .data(messageData):
            data = messageData
        case let .string(string):
            data = Data(string.utf8)
        @unknown default:
            throw Error.unknownMessage(description: String(describing: message))
        }

        do {
            return try decoder.decode(Value.self, from: data)
        } catch {
            throw Error.decoding(error)
        }
    }
}

#endif
