
import Foundation

public typealias Parameters = [String: any Any & Sendable]

public protocol ParameterEncoding: Sendable {
    func encode(_ urlRequest: any URLRequestConvertible, with parameters: Parameters?) throws -> URLRequest
}

public struct URLEncoding: ParameterEncoding {

    public enum Destination: Sendable {
        case methodDependent
        case queryString
        case httpBody

        func encodesParametersInURL(for method: HTTPMethod) -> Bool {
            switch self {
            case .methodDependent: [.get, .head, .delete].contains(method)
            case .queryString: true
            case .httpBody: false
            }
        }
    }

    public enum ArrayEncoding: Sendable {
        case brackets
        case noBrackets
        case indexInBrackets
        case custom(@Sendable (_ key: String, _ index: Int) -> String)

        func encode(key: String, atIndex index: Int) -> String {
            switch self {
            case .brackets:
                "\(key)[]"
            case .noBrackets:
                key
            case .indexInBrackets:
                "\(key)[\(index)]"
            case let .custom(encoding):
                encoding(key, index)
            }
        }
    }

    public enum BoolEncoding: Sendable {
        case numeric
        case literal

        func encode(value: Bool) -> String {
            switch self {
            case .numeric:
                value ? "1" : "0"
            case .literal:
                value ? "true" : "false"
            }
        }
    }

    public static var `default`: URLEncoding { URLEncoding() }

    public static var queryString: URLEncoding { URLEncoding(destination: .queryString) }

    public static var httpBody: URLEncoding { URLEncoding(destination: .httpBody) }

    public let destination: Destination

    public let arrayEncoding: ArrayEncoding

    public let boolEncoding: BoolEncoding

    public init(destination: Destination = .methodDependent,
                arrayEncoding: ArrayEncoding = .brackets,
                boolEncoding: BoolEncoding = .numeric) {
        self.destination = destination
        self.arrayEncoding = arrayEncoding
        self.boolEncoding = boolEncoding
    }

    public func encode(_ urlRequest: any URLRequestConvertible, with parameters: Parameters?) throws -> URLRequest {
        var urlRequest = try urlRequest.asURLRequest()

        guard let parameters else { return urlRequest }

        if let method = urlRequest.method, destination.encodesParametersInURL(for: method) {
            guard let url = urlRequest.url else {
                throw AFError.parameterEncodingFailed(reason: .missingURL)
            }

            if var urlComponents = URLComponents(url: url, resolvingAgainstBaseURL: false), !parameters.isEmpty {
                let percentEncodedQuery = (urlComponents.percentEncodedQuery.map { $0 + "&" } ?? "") + query(parameters)
                urlComponents.percentEncodedQuery = percentEncodedQuery
                urlRequest.url = urlComponents.url
            }
        } else {
            if urlRequest.headers["Content-Type"] == nil {
                urlRequest.headers.update(.contentType("application/x-www-form-urlencoded; charset=utf-8"))
            }

            urlRequest.httpBody = Data(query(parameters).utf8)
        }

        return urlRequest
    }

    public func queryComponents(fromKey key: String, value: Any) -> [(String, String)] {
        var components: [(String, String)] = []
        switch value {
        case let dictionary as [String: Any]:
            for (nestedKey, value) in dictionary {
                components += queryComponents(fromKey: "\(key)[\(nestedKey)]", value: value)
            }
        case let array as [Any]:
            for (index, value) in array.enumerated() {
                components += queryComponents(fromKey: arrayEncoding.encode(key: key, atIndex: index), value: value)
            }
        case let number as NSNumber:
            if number.isBool {
                components.append((escape(key), escape(boolEncoding.encode(value: number.boolValue))))
            } else {
                components.append((escape(key), escape("\(number)")))
            }
        case let bool as Bool:
            components.append((escape(key), escape(boolEncoding.encode(value: bool))))
        default:
            components.append((escape(key), escape("\(value)")))
        }
        return components
    }

    public func escape(_ string: String) -> String {
        string.addingPercentEncoding(withAllowedCharacters: .afURLQueryAllowed) ?? string
    }

    private func query(_ parameters: [String: Any]) -> String {
        var components: [(String, String)] = []

        for key in parameters.keys.sorted(by: <) {
            let value = parameters[key]!
            components += queryComponents(fromKey: key, value: value)
        }
        return components.map { "\($0)=\($1)" }.joined(separator: "&")
    }
}

public struct JSONEncoding: ParameterEncoding {
    public enum Error: Swift.Error {
        case invalidJSONObject
    }

    public static var `default`: JSONEncoding { JSONEncoding() }

    public static var prettyPrinted: JSONEncoding { JSONEncoding(options: .prettyPrinted) }

    public let options: JSONSerialization.WritingOptions

    public init(options: JSONSerialization.WritingOptions = []) {
        self.options = options
    }

    public func encode(_ urlRequest: any URLRequestConvertible, with parameters: Parameters?) throws -> URLRequest {
        var urlRequest = try urlRequest.asURLRequest()

        guard let parameters else { return urlRequest }

        guard JSONSerialization.isValidJSONObject(parameters) else {
            throw AFError.parameterEncodingFailed(reason: .jsonEncodingFailed(error: Error.invalidJSONObject))
        }

        do {
            let data = try JSONSerialization.data(withJSONObject: parameters, options: options)

            if urlRequest.headers["Content-Type"] == nil {
                urlRequest.headers.update(.contentType("application/json"))
            }

            urlRequest.httpBody = data
        } catch {
            throw AFError.parameterEncodingFailed(reason: .jsonEncodingFailed(error: error))
        }

        return urlRequest
    }

    public func encode(_ urlRequest: any URLRequestConvertible, withJSONObject jsonObject: Any? = nil) throws -> URLRequest {
        var urlRequest = try urlRequest.asURLRequest()

        guard let jsonObject else { return urlRequest }

        guard JSONSerialization.isValidJSONObject(jsonObject) else {
            throw AFError.parameterEncodingFailed(reason: .jsonEncodingFailed(error: Error.invalidJSONObject))
        }

        do {
            let data = try JSONSerialization.data(withJSONObject: jsonObject, options: options)

            if urlRequest.headers["Content-Type"] == nil {
                urlRequest.headers.update(.contentType("application/json"))
            }

            urlRequest.httpBody = data
        } catch {
            throw AFError.parameterEncodingFailed(reason: .jsonEncodingFailed(error: error))
        }

        return urlRequest
    }
}

extension JSONEncoding.Error {
    public var localizedDescription: String {
        """
        Invalid JSON object provided for parameter or object encoding. \
        This is most likely due to a value which can't be represented in Objective-C.
        """
    }
}

extension NSNumber {
    fileprivate var isBool: Bool {
        String(cString: objCType) == "c"
    }
}
