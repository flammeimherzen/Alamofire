
import Foundation

public protocol ParameterEncoder: Sendable {
    func encode<Parameters: Encodable & Sendable>(_ parameters: Parameters?, into request: URLRequest) throws -> URLRequest
}

open class JSONParameterEncoder: @unchecked Sendable, ParameterEncoder {
    public static var `default`: JSONParameterEncoder { JSONParameterEncoder() }

    public static var prettyPrinted: JSONParameterEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .prettyPrinted

        return JSONParameterEncoder(encoder: encoder)
    }

    @available(macOS 10.13, iOS 11.0, tvOS 11.0, watchOS 4.0, *)
    public static var sortedKeys: JSONParameterEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys

        return JSONParameterEncoder(encoder: encoder)
    }

    public let encoder: JSONEncoder

    public init(encoder: JSONEncoder = JSONEncoder()) {
        self.encoder = encoder
    }

    open func encode<Parameters: Encodable>(_ parameters: Parameters?,
                                            into request: URLRequest) throws -> URLRequest {
        guard let parameters else { return request }

        var request = request

        do {
            let data = try encoder.encode(parameters)
            request.httpBody = data
            if request.headers["Content-Type"] == nil {
                request.headers.update(.contentType("application/json"))
            }
        } catch {
            throw AFError.parameterEncodingFailed(reason: .jsonEncodingFailed(error: error))
        }

        return request
    }
}

extension ParameterEncoder where Self == JSONParameterEncoder {
    public static var json: JSONParameterEncoder { JSONParameterEncoder() }

    public static func json(encoder: JSONEncoder = JSONEncoder()) -> JSONParameterEncoder {
        JSONParameterEncoder(encoder: encoder)
    }
}

open class URLEncodedFormParameterEncoder: @unchecked Sendable, ParameterEncoder {
    public enum Destination {
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

    public static var `default`: URLEncodedFormParameterEncoder { URLEncodedFormParameterEncoder() }

    public let encoder: URLEncodedFormEncoder

    public let destination: Destination

    public init(encoder: URLEncodedFormEncoder = URLEncodedFormEncoder(), destination: Destination = .methodDependent) {
        self.encoder = encoder
        self.destination = destination
    }

    open func encode<Parameters: Encodable>(_ parameters: Parameters?,
                                            into request: URLRequest) throws -> URLRequest {
        guard let parameters else { return request }

        var request = request

        guard let url = request.url else {
            throw AFError.parameterEncoderFailed(reason: .missingRequiredComponent(.url))
        }

        guard let method = request.method else {
            let rawValue = request.method?.rawValue ?? "nil"
            throw AFError.parameterEncoderFailed(reason: .missingRequiredComponent(.httpMethod(rawValue: rawValue)))
        }

        if destination.encodesParametersInURL(for: method),
           var components = URLComponents(url: url, resolvingAgainstBaseURL: false) {
            let query: String = try Result<String, any Error> { try encoder.encode(parameters) }
                .mapError { AFError.parameterEncoderFailed(reason: .encoderFailed(error: $0)) }.get()
            let newQueryString = [components.percentEncodedQuery, query].compactMap(\.self).joinedWithAmpersands()
            components.percentEncodedQuery = newQueryString.isEmpty ? nil : newQueryString

            guard let newURL = components.url else {
                throw AFError.parameterEncoderFailed(reason: .missingRequiredComponent(.url))
            }

            request.url = newURL
        } else {
            if request.headers["Content-Type"] == nil {
                request.headers.update(.contentType("application/x-www-form-urlencoded; charset=utf-8"))
            }

            request.httpBody = try Result<Data, any Error> { try encoder.encode(parameters) }
                .mapError { AFError.parameterEncoderFailed(reason: .encoderFailed(error: $0)) }.get()
        }

        return request
    }
}

extension ParameterEncoder where Self == URLEncodedFormParameterEncoder {
    public static var urlEncodedForm: URLEncodedFormParameterEncoder { URLEncodedFormParameterEncoder() }

    public static func urlEncodedForm(encoder: URLEncodedFormEncoder = URLEncodedFormEncoder(),
                                      destination: URLEncodedFormParameterEncoder.Destination = .methodDependent) -> URLEncodedFormParameterEncoder {
        URLEncodedFormParameterEncoder(encoder: encoder, destination: destination)
    }
}
