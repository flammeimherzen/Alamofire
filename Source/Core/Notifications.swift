
import Foundation

extension Request {
    public static let didResumeNotification = Notification.Name(rawValue: "org.alamofire.notification.name.request.didResume")
    public static let didSuspendNotification = Notification.Name(rawValue: "org.alamofire.notification.name.request.didSuspend")
    public static let didCancelNotification = Notification.Name(rawValue: "org.alamofire.notification.name.request.didCancel")
    public static let didFinishNotification = Notification.Name(rawValue: "org.alamofire.notification.name.request.didFinish")

    public static let didResumeTaskNotification = Notification.Name(rawValue: "org.alamofire.notification.name.request.didResumeTask")
    public static let didSuspendTaskNotification = Notification.Name(rawValue: "org.alamofire.notification.name.request.didSuspendTask")
    public static let didCancelTaskNotification = Notification.Name(rawValue: "org.alamofire.notification.name.request.didCancelTask")
    public static let didCompleteTaskNotification = Notification.Name(rawValue: "org.alamofire.notification.name.request.didCompleteTask")
}

extension Notification {
    public var request: Request? {
        userInfo?[String.requestKey] as? Request
    }

    init(name: Notification.Name, request: Request) {
        self.init(name: name, object: nil, userInfo: [String.requestKey: request])
    }
}

extension NotificationCenter {
    func postNotification(named name: Notification.Name, with request: Request) {
        let notification = Notification(name: name, request: request)
        post(notification)
    }
}

extension String {
    fileprivate static let requestKey = "org.alamofire.notification.key.request"
}

public final class AlamofireNotifications: EventMonitor {
    public init() {}

    public func requestDidResume(_ request: Request) {
        NotificationCenter.default.postNotification(named: Request.didResumeNotification, with: request)
    }

    public func requestDidSuspend(_ request: Request) {
        NotificationCenter.default.postNotification(named: Request.didSuspendNotification, with: request)
    }

    public func requestDidCancel(_ request: Request) {
        NotificationCenter.default.postNotification(named: Request.didCancelNotification, with: request)
    }

    public func requestDidFinish(_ request: Request) {
        NotificationCenter.default.postNotification(named: Request.didFinishNotification, with: request)
    }

    public func request(_ request: Request, didResumeTask task: URLSessionTask) {
        NotificationCenter.default.postNotification(named: Request.didResumeTaskNotification, with: request)
    }

    public func request(_ request: Request, didSuspendTask task: URLSessionTask) {
        NotificationCenter.default.postNotification(named: Request.didSuspendTaskNotification, with: request)
    }

    public func request(_ request: Request, didCancelTask task: URLSessionTask) {
        NotificationCenter.default.postNotification(named: Request.didCancelTaskNotification, with: request)
    }

    public func request(_ request: Request, didCompleteTask task: URLSessionTask, with error: AFError?) {
        NotificationCenter.default.postNotification(named: Request.didCompleteTaskNotification, with: request)
    }
}
