
import Foundation

public protocol EventMonitor: Sendable {
    var queue: DispatchQueue { get }

    func urlSession(_ session: URLSession, didBecomeInvalidWithError error: (any Error)?)

    func urlSession(_ session: URLSession, task: URLSessionTask, didReceive challenge: URLAuthenticationChallenge)

    func urlSession(_ session: URLSession,
                    task: URLSessionTask,
                    didSendBodyData bytesSent: Int64,
                    totalBytesSent: Int64,
                    totalBytesExpectedToSend: Int64)

    func urlSession(_ session: URLSession, taskNeedsNewBodyStream task: URLSessionTask)

    func urlSession(_ session: URLSession,
                    task: URLSessionTask,
                    willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest)

    func urlSession(_ session: URLSession, task: URLSessionTask, didFinishCollecting metrics: URLSessionTaskMetrics)

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: (any Error)?)

    func urlSession(_ session: URLSession, taskIsWaitingForConnectivity task: URLSessionTask)

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse)

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data)

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, willCacheResponse proposedResponse: CachedURLResponse)

    func urlSession(_ session: URLSession,
                    downloadTask: URLSessionDownloadTask,
                    didResumeAtOffset fileOffset: Int64,
                    expectedTotalBytes: Int64)

    func urlSession(_ session: URLSession,
                    downloadTask: URLSessionDownloadTask,
                    didWriteData bytesWritten: Int64,
                    totalBytesWritten: Int64,
                    totalBytesExpectedToWrite: Int64)

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL)

    func request(_ request: Request, didCreateInitialURLRequest urlRequest: URLRequest)

    func request(_ request: Request, didFailToCreateURLRequestWithError error: AFError)

    func request(_ request: Request, didAdaptInitialRequest initialRequest: URLRequest, to adaptedRequest: URLRequest)

    func request(_ request: Request, didFailToAdaptURLRequest initialRequest: URLRequest, withError error: AFError)

    func request(_ request: Request, didCreateURLRequest urlRequest: URLRequest)

    func request(_ request: Request, didCreateTask task: URLSessionTask)

    func request(_ request: Request, didGatherMetrics metrics: URLSessionTaskMetrics)

    func request(_ request: Request, didFailTask task: URLSessionTask, earlyWithError error: AFError)

    func request(_ request: Request, didCompleteTask task: URLSessionTask, with error: AFError?)

    func requestIsRetrying(_ request: Request)

    func requestDidFinish(_ request: Request)

    func requestDidResume(_ request: Request)

    func request(_ request: Request, didResumeTask task: URLSessionTask)

    func requestDidSuspend(_ request: Request)

    func request(_ request: Request, didSuspendTask task: URLSessionTask)

    func requestDidCancel(_ request: Request)

    func request(_ request: Request, didCancelTask task: URLSessionTask)

    func request(_ request: DataRequest,
                 didValidateRequest urlRequest: URLRequest?,
                 response: HTTPURLResponse,
                 data: Data?,
                 withResult result: Request.ValidationResult)

    func request(_ request: DataRequest, didParseResponse response: DataResponse<Data?, AFError>)

    func request<Value: Sendable>(_ request: DataRequest, didParseResponse response: DataResponse<Value, AFError>)

    func request(_ request: DataStreamRequest,
                 didValidateRequest urlRequest: URLRequest?,
                 response: HTTPURLResponse,
                 withResult result: Request.ValidationResult)

    func request<Value: Sendable>(_ request: DataStreamRequest, didParseStream result: Result<Value, AFError>)

    func request(_ request: UploadRequest, didCreateUploadable uploadable: UploadRequest.Uploadable)

    func request(_ request: UploadRequest, didFailToCreateUploadableWithError error: AFError)

    func request(_ request: UploadRequest, didProvideInputStream stream: InputStream)

    func request(_ request: DownloadRequest, didFinishDownloadingUsing task: URLSessionTask, with result: Result<URL, AFError>)

    func request(_ request: DownloadRequest, didCreateDestinationURL url: URL)

    func request(_ request: DownloadRequest,
                 didValidateRequest urlRequest: URLRequest?,
                 response: HTTPURLResponse,
                 fileURL: URL?,
                 withResult result: Request.ValidationResult)

    func request(_ request: DownloadRequest, didParseResponse response: DownloadResponse<URL?, AFError>)

    func request<Value: Sendable>(_ request: DownloadRequest, didParseResponse response: DownloadResponse<Value, AFError>)
}

extension EventMonitor {
    public var queue: DispatchQueue { .main }

    public func urlSession(_ session: URLSession, didBecomeInvalidWithError error: (any Error)?) {}
    public func urlSession(_ session: URLSession,
                           task: URLSessionTask,
                           didReceive challenge: URLAuthenticationChallenge) {}
    public func urlSession(_ session: URLSession,
                           task: URLSessionTask,
                           didSendBodyData bytesSent: Int64,
                           totalBytesSent: Int64,
                           totalBytesExpectedToSend: Int64) {}
    public func urlSession(_ session: URLSession, taskNeedsNewBodyStream task: URLSessionTask) {}
    public func urlSession(_ session: URLSession,
                           task: URLSessionTask,
                           willPerformHTTPRedirection response: HTTPURLResponse,
                           newRequest request: URLRequest) {}
    public func urlSession(_ session: URLSession,
                           task: URLSessionTask,
                           didFinishCollecting metrics: URLSessionTaskMetrics) {}
    public func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: (any Error)?) {}
    public func urlSession(_ session: URLSession, taskIsWaitingForConnectivity task: URLSessionTask) {}
    public func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse) {}
    public func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {}
    public func urlSession(_ session: URLSession,
                           dataTask: URLSessionDataTask,
                           willCacheResponse proposedResponse: CachedURLResponse) {}
    public func urlSession(_ session: URLSession,
                           downloadTask: URLSessionDownloadTask,
                           didResumeAtOffset fileOffset: Int64,
                           expectedTotalBytes: Int64) {}
    public func urlSession(_ session: URLSession,
                           downloadTask: URLSessionDownloadTask,
                           didWriteData bytesWritten: Int64,
                           totalBytesWritten: Int64,
                           totalBytesExpectedToWrite: Int64) {}
    public func urlSession(_ session: URLSession,
                           downloadTask: URLSessionDownloadTask,
                           didFinishDownloadingTo location: URL) {}
    public func request(_ request: Request, didCreateInitialURLRequest urlRequest: URLRequest) {}
    public func request(_ request: Request, didFailToCreateURLRequestWithError error: AFError) {}
    public func request(_ request: Request,
                        didAdaptInitialRequest initialRequest: URLRequest,
                        to adaptedRequest: URLRequest) {}
    public func request(_ request: Request,
                        didFailToAdaptURLRequest initialRequest: URLRequest,
                        withError error: AFError) {}
    public func request(_ request: Request, didCreateURLRequest urlRequest: URLRequest) {}
    public func request(_ request: Request, didCreateTask task: URLSessionTask) {}
    public func request(_ request: Request, didGatherMetrics metrics: URLSessionTaskMetrics) {}
    public func request(_ request: Request, didFailTask task: URLSessionTask, earlyWithError error: AFError) {}
    public func request(_ request: Request, didCompleteTask task: URLSessionTask, with error: AFError?) {}
    public func requestIsRetrying(_ request: Request) {}
    public func requestDidFinish(_ request: Request) {}
    public func requestDidResume(_ request: Request) {}
    public func request(_ request: Request, didResumeTask task: URLSessionTask) {}
    public func requestDidSuspend(_ request: Request) {}
    public func request(_ request: Request, didSuspendTask task: URLSessionTask) {}
    public func requestDidCancel(_ request: Request) {}
    public func request(_ request: Request, didCancelTask task: URLSessionTask) {}
    public func request(_ request: DataRequest,
                        didValidateRequest urlRequest: URLRequest?,
                        response: HTTPURLResponse,
                        data: Data?,
                        withResult result: Request.ValidationResult) {}
    public func request(_ request: DataRequest, didParseResponse response: DataResponse<Data?, AFError>) {}
    public func request<Value: Sendable>(_ request: DataRequest, didParseResponse response: DataResponse<Value, AFError>) {}
    public func request(_ request: DataStreamRequest,
                        didValidateRequest urlRequest: URLRequest?,
                        response: HTTPURLResponse,
                        withResult result: Request.ValidationResult) {}
    public func request<Value: Sendable>(_ request: DataStreamRequest, didParseStream result: Result<Value, AFError>) {}
    public func request(_ request: UploadRequest, didCreateUploadable uploadable: UploadRequest.Uploadable) {}
    public func request(_ request: UploadRequest, didFailToCreateUploadableWithError error: AFError) {}
    public func request(_ request: UploadRequest, didProvideInputStream stream: InputStream) {}
    public func request(_ request: DownloadRequest, didFinishDownloadingUsing task: URLSessionTask, with result: Result<URL, AFError>) {}
    public func request(_ request: DownloadRequest, didCreateDestinationURL url: URL) {}
    public func request(_ request: DownloadRequest,
                        didValidateRequest urlRequest: URLRequest?,
                        response: HTTPURLResponse,
                        fileURL: URL?,
                        withResult result: Request.ValidationResult) {}
    public func request(_ request: DownloadRequest, didParseResponse response: DownloadResponse<URL?, AFError>) {}
    public func request<Value: Sendable>(_ request: DownloadRequest, didParseResponse response: DownloadResponse<Value, AFError>) {}
}

public final class CompositeEventMonitor: EventMonitor {
    public let queue: DispatchQueue
    public var monitors: [any EventMonitor] {
        _monitors.read(\.self)
    }

    let _monitors: Protected<[any EventMonitor]>

    init(queue: DispatchQueue = DispatchQueue(label: "org.alamofire.compositeEventMonitor"), monitors: [any EventMonitor]) {
        self.queue = queue
        _monitors = Protected(monitors)
    }

    func performEvent(_ event: sending @escaping (any EventMonitor) -> Void) {
        _monitors.read { monitors in
            for monitor in monitors {
                monitor.queue.async { event(monitor) }
            }
        }
    }

    public func urlSession(_ session: URLSession, didBecomeInvalidWithError error: (any Error)?) {
        performEvent { $0.urlSession(session, didBecomeInvalidWithError: error) }
    }

    public func urlSession(_ session: URLSession,
                           task: URLSessionTask,
                           didReceive challenge: URLAuthenticationChallenge) {
        performEvent { $0.urlSession(session, task: task, didReceive: challenge) }
    }

    public func urlSession(_ session: URLSession,
                           task: URLSessionTask,
                           didSendBodyData bytesSent: Int64,
                           totalBytesSent: Int64,
                           totalBytesExpectedToSend: Int64) {
        performEvent {
            $0.urlSession(session,
                          task: task,
                          didSendBodyData: bytesSent,
                          totalBytesSent: totalBytesSent,
                          totalBytesExpectedToSend: totalBytesExpectedToSend)
        }
    }

    public func urlSession(_ session: URLSession, taskNeedsNewBodyStream task: URLSessionTask) {
        performEvent {
            $0.urlSession(session, taskNeedsNewBodyStream: task)
        }
    }

    public func urlSession(_ session: URLSession,
                           task: URLSessionTask,
                           willPerformHTTPRedirection response: HTTPURLResponse,
                           newRequest request: URLRequest) {
        performEvent {
            $0.urlSession(session,
                          task: task,
                          willPerformHTTPRedirection: response,
                          newRequest: request)
        }
    }

    public func urlSession(_ session: URLSession, task: URLSessionTask, didFinishCollecting metrics: URLSessionTaskMetrics) {
        performEvent { $0.urlSession(session, task: task, didFinishCollecting: metrics) }
    }

    public func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: (any Error)?) {
        performEvent { $0.urlSession(session, task: task, didCompleteWithError: error) }
    }

    @available(macOS 10.13, iOS 11.0, tvOS 11.0, watchOS 4.0, *)
    public func urlSession(_ session: URLSession, taskIsWaitingForConnectivity task: URLSessionTask) {
        performEvent { $0.urlSession(session, taskIsWaitingForConnectivity: task) }
    }

    public func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse) {
        performEvent { $0.urlSession(session, dataTask: dataTask, didReceive: response) }
    }

    public func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        performEvent { $0.urlSession(session, dataTask: dataTask, didReceive: data) }
    }

    public func urlSession(_ session: URLSession,
                           dataTask: URLSessionDataTask,
                           willCacheResponse proposedResponse: CachedURLResponse) {
        performEvent { $0.urlSession(session, dataTask: dataTask, willCacheResponse: proposedResponse) }
    }

    public func urlSession(_ session: URLSession,
                           downloadTask: URLSessionDownloadTask,
                           didResumeAtOffset fileOffset: Int64,
                           expectedTotalBytes: Int64) {
        performEvent {
            $0.urlSession(session,
                          downloadTask: downloadTask,
                          didResumeAtOffset: fileOffset,
                          expectedTotalBytes: expectedTotalBytes)
        }
    }

    public func urlSession(_ session: URLSession,
                           downloadTask: URLSessionDownloadTask,
                           didWriteData bytesWritten: Int64,
                           totalBytesWritten: Int64,
                           totalBytesExpectedToWrite: Int64) {
        performEvent {
            $0.urlSession(session,
                          downloadTask: downloadTask,
                          didWriteData: bytesWritten,
                          totalBytesWritten: totalBytesWritten,
                          totalBytesExpectedToWrite: totalBytesExpectedToWrite)
        }
    }

    public func urlSession(_ session: URLSession,
                           downloadTask: URLSessionDownloadTask,
                           didFinishDownloadingTo location: URL) {
        performEvent { $0.urlSession(session, downloadTask: downloadTask, didFinishDownloadingTo: location) }
    }

    public func request(_ request: Request, didCreateInitialURLRequest urlRequest: URLRequest) {
        performEvent { $0.request(request, didCreateInitialURLRequest: urlRequest) }
    }

    public func request(_ request: Request, didFailToCreateURLRequestWithError error: AFError) {
        performEvent { $0.request(request, didFailToCreateURLRequestWithError: error) }
    }

    public func request(_ request: Request, didAdaptInitialRequest initialRequest: URLRequest, to adaptedRequest: URLRequest) {
        performEvent { $0.request(request, didAdaptInitialRequest: initialRequest, to: adaptedRequest) }
    }

    public func request(_ request: Request, didFailToAdaptURLRequest initialRequest: URLRequest, withError error: AFError) {
        performEvent { $0.request(request, didFailToAdaptURLRequest: initialRequest, withError: error) }
    }

    public func request(_ request: Request, didCreateURLRequest urlRequest: URLRequest) {
        performEvent { $0.request(request, didCreateURLRequest: urlRequest) }
    }

    public func request(_ request: Request, didCreateTask task: URLSessionTask) {
        performEvent { $0.request(request, didCreateTask: task) }
    }

    public func request(_ request: Request, didGatherMetrics metrics: URLSessionTaskMetrics) {
        performEvent { $0.request(request, didGatherMetrics: metrics) }
    }

    public func request(_ request: Request, didFailTask task: URLSessionTask, earlyWithError error: AFError) {
        performEvent { $0.request(request, didFailTask: task, earlyWithError: error) }
    }

    public func request(_ request: Request, didCompleteTask task: URLSessionTask, with error: AFError?) {
        performEvent { $0.request(request, didCompleteTask: task, with: error) }
    }

    public func requestIsRetrying(_ request: Request) {
        performEvent { $0.requestIsRetrying(request) }
    }

    public func requestDidFinish(_ request: Request) {
        performEvent { $0.requestDidFinish(request) }
    }

    public func requestDidResume(_ request: Request) {
        performEvent { $0.requestDidResume(request) }
    }

    public func request(_ request: Request, didResumeTask task: URLSessionTask) {
        performEvent { $0.request(request, didResumeTask: task) }
    }

    public func requestDidSuspend(_ request: Request) {
        performEvent { $0.requestDidSuspend(request) }
    }

    public func request(_ request: Request, didSuspendTask task: URLSessionTask) {
        performEvent { $0.request(request, didSuspendTask: task) }
    }

    public func requestDidCancel(_ request: Request) {
        performEvent { $0.requestDidCancel(request) }
    }

    public func request(_ request: Request, didCancelTask task: URLSessionTask) {
        performEvent { $0.request(request, didCancelTask: task) }
    }

    public func request(_ request: DataRequest,
                        didValidateRequest urlRequest: URLRequest?,
                        response: HTTPURLResponse,
                        data: Data?,
                        withResult result: Request.ValidationResult) {
        performEvent { $0.request(request,
                                  didValidateRequest: urlRequest,
                                  response: response,
                                  data: data,
                                  withResult: result)
        }
    }

    public func request(_ request: DataRequest, didParseResponse response: DataResponse<Data?, AFError>) {
        performEvent { $0.request(request, didParseResponse: response) }
    }

    public func request<Value>(_ request: DataRequest, didParseResponse response: DataResponse<Value, AFError>) {
        performEvent { $0.request(request, didParseResponse: response) }
    }

    public func request(_ request: DataStreamRequest,
                        didValidateRequest urlRequest: URLRequest?,
                        response: HTTPURLResponse,
                        withResult result: Request.ValidationResult) {
        performEvent { $0.request(request,
                                  didValidateRequest: urlRequest,
                                  response: response,
                                  withResult: result)
        }
    }

    public func request<Value: Sendable>(_ request: DataStreamRequest, didParseStream result: Result<Value, AFError>) {
        performEvent { $0.request(request, didParseStream: result) }
    }

    public func request(_ request: UploadRequest, didCreateUploadable uploadable: UploadRequest.Uploadable) {
        performEvent { $0.request(request, didCreateUploadable: uploadable) }
    }

    public func request(_ request: UploadRequest, didFailToCreateUploadableWithError error: AFError) {
        performEvent { $0.request(request, didFailToCreateUploadableWithError: error) }
    }

    public func request(_ request: UploadRequest, didProvideInputStream stream: InputStream) {
        performEvent { $0.request(request, didProvideInputStream: stream) }
    }

    public func request(_ request: DownloadRequest, didFinishDownloadingUsing task: URLSessionTask, with result: Result<URL, AFError>) {
        performEvent { $0.request(request, didFinishDownloadingUsing: task, with: result) }
    }

    public func request(_ request: DownloadRequest, didCreateDestinationURL url: URL) {
        performEvent { $0.request(request, didCreateDestinationURL: url) }
    }

    public func request(_ request: DownloadRequest,
                        didValidateRequest urlRequest: URLRequest?,
                        response: HTTPURLResponse,
                        fileURL: URL?,
                        withResult result: Request.ValidationResult) {
        performEvent { $0.request(request,
                                  didValidateRequest: urlRequest,
                                  response: response,
                                  fileURL: fileURL,
                                  withResult: result) }
    }

    public func request(_ request: DownloadRequest, didParseResponse response: DownloadResponse<URL?, AFError>) {
        performEvent { $0.request(request, didParseResponse: response) }
    }

    public func request<Value: Sendable>(_ request: DownloadRequest, didParseResponse response: DownloadResponse<Value, AFError>) {
        performEvent { $0.request(request, didParseResponse: response) }
    }
}

open class ClosureEventMonitor: EventMonitor, @unchecked Sendable {
    open var sessionDidBecomeInvalidWithError: ((URLSession, (any Error)?) -> Void)?

    open var taskDidReceiveChallenge: ((URLSession, URLSessionTask, URLAuthenticationChallenge) -> Void)?

    open var taskDidSendBodyData: ((URLSession, URLSessionTask, Int64, Int64, Int64) -> Void)?

    open var taskNeedNewBodyStream: ((URLSession, URLSessionTask) -> Void)?

    open var taskWillPerformHTTPRedirection: ((URLSession, URLSessionTask, HTTPURLResponse, URLRequest) -> Void)?

    open var taskDidFinishCollectingMetrics: ((URLSession, URLSessionTask, URLSessionTaskMetrics) -> Void)?

    open var taskDidComplete: ((URLSession, URLSessionTask, (any Error)?) -> Void)?

    open var taskIsWaitingForConnectivity: ((URLSession, URLSessionTask) -> Void)?

    open var dataTaskDidReceiveResponse: ((URLSession, URLSessionDataTask, URLResponse) -> Void)?

    open var dataTaskDidReceiveData: ((URLSession, URLSessionDataTask, Data) -> Void)?

    open var dataTaskWillCacheResponse: ((URLSession, URLSessionDataTask, CachedURLResponse) -> Void)?

    open var downloadTaskDidFinishDownloadingToURL: ((URLSession, URLSessionDownloadTask, URL) -> Void)?

    open var downloadTaskDidWriteData: ((URLSession, URLSessionDownloadTask, Int64, Int64, Int64) -> Void)?

    open var downloadTaskDidResumeAtOffset: ((URLSession, URLSessionDownloadTask, Int64, Int64) -> Void)?

    open var requestDidCreateInitialURLRequest: ((Request, URLRequest) -> Void)?

    open var requestDidFailToCreateURLRequestWithError: ((Request, AFError) -> Void)?

    open var requestDidAdaptInitialRequestToAdaptedRequest: ((Request, URLRequest, URLRequest) -> Void)?

    open var requestDidFailToAdaptURLRequestWithError: ((Request, URLRequest, AFError) -> Void)?

    open var requestDidCreateURLRequest: ((Request, URLRequest) -> Void)?

    open var requestDidCreateTask: ((Request, URLSessionTask) -> Void)?

    open var requestDidGatherMetrics: ((Request, URLSessionTaskMetrics) -> Void)?

    open var requestDidFailTaskEarlyWithError: ((Request, URLSessionTask, AFError) -> Void)?

    open var requestDidCompleteTaskWithError: ((Request, URLSessionTask, AFError?) -> Void)?

    open var requestIsRetrying: ((Request) -> Void)?

    open var requestDidFinish: ((Request) -> Void)?

    open var requestDidResume: ((Request) -> Void)?

    open var requestDidResumeTask: ((Request, URLSessionTask) -> Void)?

    open var requestDidSuspend: ((Request) -> Void)?

    open var requestDidSuspendTask: ((Request, URLSessionTask) -> Void)?

    open var requestDidCancel: ((Request) -> Void)?

    open var requestDidCancelTask: ((Request, URLSessionTask) -> Void)?

    open var requestDidValidateRequestResponseDataWithResult: ((DataRequest, URLRequest?, HTTPURLResponse, Data?, Request.ValidationResult) -> Void)?

    open var requestDidParseResponse: ((DataRequest, DataResponse<Data?, AFError>) -> Void)?

    open var requestDidValidateRequestResponseWithResult: ((DataStreamRequest, URLRequest?, HTTPURLResponse, Request.ValidationResult) -> Void)?

    open var requestDidCreateUploadable: ((UploadRequest, UploadRequest.Uploadable) -> Void)?

    open var requestDidFailToCreateUploadableWithError: ((UploadRequest, AFError) -> Void)?

    open var requestDidProvideInputStream: ((UploadRequest, InputStream) -> Void)?

    open var requestDidFinishDownloadingUsingTaskWithResult: ((DownloadRequest, URLSessionTask, Result<URL, AFError>) -> Void)?

    open var requestDidCreateDestinationURL: ((DownloadRequest, URL) -> Void)?

    open var requestDidValidateRequestResponseFileURLWithResult: ((DownloadRequest, URLRequest?, HTTPURLResponse, URL?, Request.ValidationResult) -> Void)?

    open var requestDidParseDownloadResponse: ((DownloadRequest, DownloadResponse<URL?, AFError>) -> Void)?

    public let queue: DispatchQueue

    public init(queue: DispatchQueue = .main) {
        self.queue = queue
    }

    open func urlSession(_ session: URLSession, didBecomeInvalidWithError error: (any Error)?) {
        sessionDidBecomeInvalidWithError?(session, error)
    }

    open func urlSession(_ session: URLSession, task: URLSessionTask, didReceive challenge: URLAuthenticationChallenge) {
        taskDidReceiveChallenge?(session, task, challenge)
    }

    open func urlSession(_ session: URLSession,
                         task: URLSessionTask,
                         didSendBodyData bytesSent: Int64,
                         totalBytesSent: Int64,
                         totalBytesExpectedToSend: Int64) {
        taskDidSendBodyData?(session, task, bytesSent, totalBytesSent, totalBytesExpectedToSend)
    }

    open func urlSession(_ session: URLSession, taskNeedsNewBodyStream task: URLSessionTask) {
        taskNeedNewBodyStream?(session, task)
    }

    open func urlSession(_ session: URLSession,
                         task: URLSessionTask,
                         willPerformHTTPRedirection response: HTTPURLResponse,
                         newRequest request: URLRequest) {
        taskWillPerformHTTPRedirection?(session, task, response, request)
    }

    open func urlSession(_ session: URLSession, task: URLSessionTask, didFinishCollecting metrics: URLSessionTaskMetrics) {
        taskDidFinishCollectingMetrics?(session, task, metrics)
    }

    open func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: (any Error)?) {
        taskDidComplete?(session, task, error)
    }

    @available(macOS 10.13, iOS 11.0, tvOS 11.0, watchOS 4.0, *)
    open func urlSession(_ session: URLSession, taskIsWaitingForConnectivity task: URLSessionTask) {
        taskIsWaitingForConnectivity?(session, task)
    }

    open func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse) {
        dataTaskDidReceiveResponse?(session, dataTask, response)
    }

    open func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        dataTaskDidReceiveData?(session, dataTask, data)
    }

    open func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, willCacheResponse proposedResponse: CachedURLResponse) {
        dataTaskWillCacheResponse?(session, dataTask, proposedResponse)
    }

    open func urlSession(_ session: URLSession,
                         downloadTask: URLSessionDownloadTask,
                         didResumeAtOffset fileOffset: Int64,
                         expectedTotalBytes: Int64) {
        downloadTaskDidResumeAtOffset?(session, downloadTask, fileOffset, expectedTotalBytes)
    }

    open func urlSession(_ session: URLSession,
                         downloadTask: URLSessionDownloadTask,
                         didWriteData bytesWritten: Int64,
                         totalBytesWritten: Int64,
                         totalBytesExpectedToWrite: Int64) {
        downloadTaskDidWriteData?(session, downloadTask, bytesWritten, totalBytesWritten, totalBytesExpectedToWrite)
    }

    open func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        downloadTaskDidFinishDownloadingToURL?(session, downloadTask, location)
    }

    open func request(_ request: Request, didCreateInitialURLRequest urlRequest: URLRequest) {
        requestDidCreateInitialURLRequest?(request, urlRequest)
    }

    open func request(_ request: Request, didFailToCreateURLRequestWithError error: AFError) {
        requestDidFailToCreateURLRequestWithError?(request, error)
    }

    open func request(_ request: Request, didAdaptInitialRequest initialRequest: URLRequest, to adaptedRequest: URLRequest) {
        requestDidAdaptInitialRequestToAdaptedRequest?(request, initialRequest, adaptedRequest)
    }

    open func request(_ request: Request, didFailToAdaptURLRequest initialRequest: URLRequest, withError error: AFError) {
        requestDidFailToAdaptURLRequestWithError?(request, initialRequest, error)
    }

    open func request(_ request: Request, didCreateURLRequest urlRequest: URLRequest) {
        requestDidCreateURLRequest?(request, urlRequest)
    }

    open func request(_ request: Request, didCreateTask task: URLSessionTask) {
        requestDidCreateTask?(request, task)
    }

    open func request(_ request: Request, didGatherMetrics metrics: URLSessionTaskMetrics) {
        requestDidGatherMetrics?(request, metrics)
    }

    open func request(_ request: Request, didFailTask task: URLSessionTask, earlyWithError error: AFError) {
        requestDidFailTaskEarlyWithError?(request, task, error)
    }

    open func request(_ request: Request, didCompleteTask task: URLSessionTask, with error: AFError?) {
        requestDidCompleteTaskWithError?(request, task, error)
    }

    open func requestIsRetrying(_ request: Request) {
        requestIsRetrying?(request)
    }

    open func requestDidFinish(_ request: Request) {
        requestDidFinish?(request)
    }

    open func requestDidResume(_ request: Request) {
        requestDidResume?(request)
    }

    public func request(_ request: Request, didResumeTask task: URLSessionTask) {
        requestDidResumeTask?(request, task)
    }

    open func requestDidSuspend(_ request: Request) {
        requestDidSuspend?(request)
    }

    public func request(_ request: Request, didSuspendTask task: URLSessionTask) {
        requestDidSuspendTask?(request, task)
    }

    open func requestDidCancel(_ request: Request) {
        requestDidCancel?(request)
    }

    public func request(_ request: Request, didCancelTask task: URLSessionTask) {
        requestDidCancelTask?(request, task)
    }

    open func request(_ request: DataRequest,
                      didValidateRequest urlRequest: URLRequest?,
                      response: HTTPURLResponse,
                      data: Data?,
                      withResult result: Request.ValidationResult) {
        requestDidValidateRequestResponseDataWithResult?(request, urlRequest, response, data, result)
    }

    open func request(_ request: DataRequest, didParseResponse response: DataResponse<Data?, AFError>) {
        requestDidParseResponse?(request, response)
    }

    public func request(_ request: DataStreamRequest, didValidateRequest urlRequest: URLRequest?, response: HTTPURLResponse, withResult result: Request.ValidationResult) {
        requestDidValidateRequestResponseWithResult?(request, urlRequest, response, result)
    }

    open func request(_ request: UploadRequest, didCreateUploadable uploadable: UploadRequest.Uploadable) {
        requestDidCreateUploadable?(request, uploadable)
    }

    open func request(_ request: UploadRequest, didFailToCreateUploadableWithError error: AFError) {
        requestDidFailToCreateUploadableWithError?(request, error)
    }

    open func request(_ request: UploadRequest, didProvideInputStream stream: InputStream) {
        requestDidProvideInputStream?(request, stream)
    }

    open func request(_ request: DownloadRequest, didFinishDownloadingUsing task: URLSessionTask, with result: Result<URL, AFError>) {
        requestDidFinishDownloadingUsingTaskWithResult?(request, task, result)
    }

    open func request(_ request: DownloadRequest, didCreateDestinationURL url: URL) {
        requestDidCreateDestinationURL?(request, url)
    }

    open func request(_ request: DownloadRequest,
                      didValidateRequest urlRequest: URLRequest?,
                      response: HTTPURLResponse,
                      fileURL: URL?,
                      withResult result: Request.ValidationResult) {
        requestDidValidateRequestResponseFileURLWithResult?(request,
                                                            urlRequest,
                                                            response,
                                                            fileURL,
                                                            result)
    }

    open func request(_ request: DownloadRequest, didParseResponse response: DownloadResponse<URL?, AFError>) {
        requestDidParseDownloadResponse?(request, response)
    }
}
