
import Foundation

public protocol URLConvertible: Sendable {
    func asURL() throws -> URL
}

extension String: URLConvertible {
    public func asURL() throws -> URL {
        guard let url = URL(string: self) else { throw AFError.invalidURL(url: self) }

        return url
    }
}

extension URL: URLConvertible {
    public func asURL() throws -> URL { self }
}

extension URLComponents: URLConvertible {
    public func asURL() throws -> URL {
        guard let url else { throw AFError.invalidURL(url: self) }

        return url
    }
}

public protocol URLRequestConvertible: Sendable {
    func asURLRequest() throws -> URLRequest
}

extension URLRequestConvertible {
    public var urlRequest: URLRequest? { try? asURLRequest() }
}

extension URLRequest: URLRequestConvertible {
    public func asURLRequest() throws -> URLRequest { self }
}

extension URLRequest {
    public init(url: any URLConvertible, method: HTTPMethod, headers: HTTPHeaders? = nil) throws {
        let url = try url.asURL()

        self.init(url: url)

        httpMethod = method.rawValue
        allHTTPHeaderFields = headers?.dictionary
    }
}
