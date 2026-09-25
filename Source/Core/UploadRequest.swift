
import Foundation

public final class UploadRequest: DataRequest, @unchecked Sendable {
    public enum Uploadable: @unchecked Sendable {
        case data(Data)
        case file(URL, shouldRemove: Bool)
        case stream(InputStream)
    }

    public let upload: any UploadableConvertible

    public let fileManager: FileManager

    public var uploadable: Uploadable?

    init(id: UUID = UUID(),
         convertible: any UploadConvertible,
         underlyingQueue: DispatchQueue,
         serializationQueue: DispatchQueue,
         eventMonitor: (any EventMonitor)?,
         interceptor: (any RequestInterceptor)?,
         shouldAutomaticallyResume: Bool?,
         fileManager: FileManager,
         delegate: any RequestDelegate) {
        upload = convertible
        self.fileManager = fileManager

        super.init(id: id,
                   convertible: convertible,
                   underlyingQueue: underlyingQueue,
                   serializationQueue: serializationQueue,
                   eventMonitor: eventMonitor,
                   interceptor: interceptor,
                   shouldAutomaticallyResume: shouldAutomaticallyResume,
                   delegate: delegate)
    }

    func didCreateUploadable(_ uploadable: Uploadable) {
        self.uploadable = uploadable

        eventMonitor?.request(self, didCreateUploadable: uploadable)
    }

    func didFailToCreateUploadable(with error: AFError) {
        self.error = error

        eventMonitor?.request(self, didFailToCreateUploadableWithError: error)

        retryOrFinish(error: error)
    }

    override func task(for request: URLRequest, using session: URLSession) -> URLSessionTask {
        guard let uploadable else {
            fatalError("Attempting to create a URLSessionUploadTask when Uploadable value doesn't exist.")
        }

        switch uploadable {
        case let .data(data): return session.uploadTask(with: request, from: data)
        case let .file(url, _): return session.uploadTask(with: request, fromFile: url)
        case .stream: return session.uploadTask(withStreamedRequest: request)
        }
    }

    override func reset() {
        uploadable = nil

        super.reset()
    }

    func inputStream() -> InputStream {
        guard let uploadable else {
            fatalError("Attempting to access the input stream but the uploadable doesn't exist.")
        }

        guard case let .stream(stream) = uploadable else {
            fatalError("Attempted to access the stream of an UploadRequest that wasn't created with one.")
        }

        eventMonitor?.request(self, didProvideInputStream: stream)

        return stream
    }

    override public func cleanup() {
        defer { super.cleanup() }

        guard
            let uploadable,
            case let .file(url, shouldRemove) = uploadable,
            shouldRemove
        else { return }

        try? fileManager.removeItem(at: url)
    }
}

public protocol UploadableConvertible: Sendable {
    func createUploadable() throws -> UploadRequest.Uploadable
}

extension UploadRequest.Uploadable: UploadableConvertible {
    public func createUploadable() throws -> UploadRequest.Uploadable {
        self
    }
}

public protocol UploadConvertible: UploadableConvertible & URLRequestConvertible {}
