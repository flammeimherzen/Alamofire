
import Foundation

public protocol RedirectHandler: Sendable {
    func task(_ task: URLSessionTask,
              willBeRedirectedTo request: URLRequest,
              for response: HTTPURLResponse,
              completion: @escaping (URLRequest?) -> Void)
}

public struct Redirector {
    public enum Behavior: Sendable {
        case follow
        case doNotFollow
        case modify(@Sendable (_ task: URLSessionTask, _ request: URLRequest, _ response: HTTPURLResponse) -> URLRequest?)
    }

    public static let follow = Redirector(behavior: .follow)
    public static let doNotFollow = Redirector(behavior: .doNotFollow)

    public let behavior: Behavior

    public init(behavior: Behavior) {
        self.behavior = behavior
    }
}

extension Redirector: RedirectHandler {
    public func task(_ task: URLSessionTask,
                     willBeRedirectedTo request: URLRequest,
                     for response: HTTPURLResponse,
                     completion: @escaping (URLRequest?) -> Void) {
        switch behavior {
        case .follow:
            completion(request)
        case .doNotFollow:
            completion(nil)
        case let .modify(closure):
            let request = closure(task, request, response)
            completion(request)
        }
    }
}

extension RedirectHandler where Self == Redirector {
    public static var follow: Redirector { .follow }

    public static var doNotFollow: Redirector { .doNotFollow }

    public static func modify(using closure: @escaping @Sendable (URLSessionTask, URLRequest, HTTPURLResponse) -> URLRequest?) -> Redirector {
        Redirector(behavior: .modify(closure))
    }
}
