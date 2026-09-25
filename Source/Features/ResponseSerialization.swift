
import Foundation

public protocol DataResponseSerializerProtocol<SerializedObject>: Sendable {
    associatedtype SerializedObject: Sendable

    func serialize(request: URLRequest?, response: HTTPURLResponse?, data: Data?, error: (any Error)?) throws -> SerializedObject
}

public protocol DownloadResponseSerializerProtocol<SerializedObject>: Sendable {
    associatedtype SerializedObject: Sendable

    func serializeDownload(request: URLRequest?, response: HTTPURLResponse?, fileURL: URL?, error: (any Error)?) throws -> SerializedObject
}

public protocol ResponseSerializer<SerializedObject>: DataResponseSerializerProtocol & DownloadResponseSerializerProtocol {
    var dataPreprocessor: any DataPreprocessor { get }
    var emptyRequestMethods: Set<HTTPMethod> { get }
    var emptyResponseCodes: Set<Int> { get }
}

public protocol DataPreprocessor: Sendable {
    func preprocess(_ data: Data) throws -> Data
}

public struct PassthroughPreprocessor: DataPreprocessor {
    public init() {}

    public func preprocess(_ data: Data) throws -> Data { data }
}

public struct GoogleXSSIPreprocessor: DataPreprocessor {
    public init() {}

    public func preprocess(_ data: Data) throws -> Data {
        (data.prefix(6) == Data(")]}',\n".utf8)) ? data.dropFirst(6) : data
    }
}

extension DataPreprocessor where Self == PassthroughPreprocessor {
    public static var passthrough: PassthroughPreprocessor { PassthroughPreprocessor() }
}

extension DataPreprocessor where Self == GoogleXSSIPreprocessor {
    public static var googleXSSI: GoogleXSSIPreprocessor { GoogleXSSIPreprocessor() }
}

extension ResponseSerializer {
    public static var defaultDataPreprocessor: any DataPreprocessor { PassthroughPreprocessor() }
    public static var defaultEmptyRequestMethods: Set<HTTPMethod> { [.head] }
    public static var defaultEmptyResponseCodes: Set<Int> { [204, 205] }

    public var dataPreprocessor: any DataPreprocessor { Self.defaultDataPreprocessor }
    public var emptyRequestMethods: Set<HTTPMethod> { Self.defaultEmptyRequestMethods }
    public var emptyResponseCodes: Set<Int> { Self.defaultEmptyResponseCodes }

    public func requestAllowsEmptyResponseData(_ request: URLRequest?) -> Bool? {
        request.flatMap(\.httpMethod)
            .flatMap(HTTPMethod.init)
            .map { emptyRequestMethods.contains($0) }
    }

    public func responseAllowsEmptyResponseData(_ response: HTTPURLResponse?) -> Bool? {
        response.map(\.statusCode)
            .map { emptyResponseCodes.contains($0) }
    }

    public func emptyResponseAllowed(forRequest request: URLRequest?, response: HTTPURLResponse?) -> Bool {
        (requestAllowsEmptyResponseData(request) == true) || (responseAllowsEmptyResponseData(response) == true)
    }
}

extension DownloadResponseSerializerProtocol where Self: DataResponseSerializerProtocol {
    public func serializeDownload(request: URLRequest?, response: HTTPURLResponse?, fileURL: URL?, error: (any Error)?) throws -> Self.SerializedObject {
        guard error == nil else { throw error! }

        guard let fileURL else {
            throw AFError.responseSerializationFailed(reason: .inputFileNil)
        }

        let data: Data
        do {
            data = try Data(contentsOf: fileURL)
        } catch {
            throw AFError.responseSerializationFailed(reason: .inputFileReadFailed(at: fileURL))
        }

        do {
            return try serialize(request: request, response: response, data: data, error: error)
        } catch {
            throw error
        }
    }
}

public struct URLResponseSerializer: DownloadResponseSerializerProtocol {
    public init() {}

    public func serializeDownload(request: URLRequest?,
                                  response: HTTPURLResponse?,
                                  fileURL: URL?,
                                  error: (any Error)?) throws -> URL {
        guard error == nil else { throw error! }

        guard let url = fileURL else {
            throw AFError.responseSerializationFailed(reason: .inputFileNil)
        }

        return url
    }
}

extension DownloadResponseSerializerProtocol where Self == URLResponseSerializer {
    public static var url: URLResponseSerializer { URLResponseSerializer() }
}

public final class DataResponseSerializer: ResponseSerializer {
    public let dataPreprocessor: any DataPreprocessor
    public let emptyResponseCodes: Set<Int>
    public let emptyRequestMethods: Set<HTTPMethod>

    public init(dataPreprocessor: any DataPreprocessor = DataResponseSerializer.defaultDataPreprocessor,
                emptyResponseCodes: Set<Int> = DataResponseSerializer.defaultEmptyResponseCodes,
                emptyRequestMethods: Set<HTTPMethod> = DataResponseSerializer.defaultEmptyRequestMethods) {
        self.dataPreprocessor = dataPreprocessor
        self.emptyResponseCodes = emptyResponseCodes
        self.emptyRequestMethods = emptyRequestMethods
    }

    public func serialize(request: URLRequest?, response: HTTPURLResponse?, data: Data?, error: (any Error)?) throws -> Data {
        guard error == nil else { throw error! }

        guard var data, !data.isEmpty else {
            guard emptyResponseAllowed(forRequest: request, response: response) else {
                throw AFError.responseSerializationFailed(reason: .inputDataNilOrZeroLength)
            }

            return Data()
        }

        data = try dataPreprocessor.preprocess(data)

        return data
    }
}

extension ResponseSerializer where Self == DataResponseSerializer {
    public static var data: DataResponseSerializer { DataResponseSerializer() }

    public static func data(dataPreprocessor: any DataPreprocessor = DataResponseSerializer.defaultDataPreprocessor,
                            emptyResponseCodes: Set<Int> = DataResponseSerializer.defaultEmptyResponseCodes,
                            emptyRequestMethods: Set<HTTPMethod> = DataResponseSerializer.defaultEmptyRequestMethods) -> DataResponseSerializer {
        DataResponseSerializer(dataPreprocessor: dataPreprocessor,
                               emptyResponseCodes: emptyResponseCodes,
                               emptyRequestMethods: emptyRequestMethods)
    }
}

public final class StringResponseSerializer: ResponseSerializer {
    public let dataPreprocessor: any DataPreprocessor
    public let encoding: String.Encoding?
    public let emptyResponseCodes: Set<Int>
    public let emptyRequestMethods: Set<HTTPMethod>

    public init(dataPreprocessor: any DataPreprocessor = StringResponseSerializer.defaultDataPreprocessor,
                encoding: String.Encoding? = nil,
                emptyResponseCodes: Set<Int> = StringResponseSerializer.defaultEmptyResponseCodes,
                emptyRequestMethods: Set<HTTPMethod> = StringResponseSerializer.defaultEmptyRequestMethods) {
        self.dataPreprocessor = dataPreprocessor
        self.encoding = encoding
        self.emptyResponseCodes = emptyResponseCodes
        self.emptyRequestMethods = emptyRequestMethods
    }

    public func serialize(request: URLRequest?, response: HTTPURLResponse?, data: Data?, error: (any Error)?) throws -> String {
        guard error == nil else { throw error! }

        guard var data, !data.isEmpty else {
            guard emptyResponseAllowed(forRequest: request, response: response) else {
                throw AFError.responseSerializationFailed(reason: .inputDataNilOrZeroLength)
            }

            return ""
        }

        data = try dataPreprocessor.preprocess(data)

        var convertedEncoding = encoding

        if let encodingName = response?.textEncodingName, convertedEncoding == nil {
            convertedEncoding = String.Encoding(ianaCharsetName: encodingName)
        }

        let actualEncoding = convertedEncoding ?? .isoLatin1

        guard let string = String(data: data, encoding: actualEncoding) else {
            throw AFError.responseSerializationFailed(reason: .stringSerializationFailed(encoding: actualEncoding))
        }

        return string
    }
}

extension ResponseSerializer where Self == StringResponseSerializer {
    public static var string: StringResponseSerializer { StringResponseSerializer() }

    public static func string(dataPreprocessor: any DataPreprocessor = StringResponseSerializer.defaultDataPreprocessor,
                              encoding: String.Encoding? = nil,
                              emptyResponseCodes: Set<Int> = StringResponseSerializer.defaultEmptyResponseCodes,
                              emptyRequestMethods: Set<HTTPMethod> = StringResponseSerializer.defaultEmptyRequestMethods) -> StringResponseSerializer {
        StringResponseSerializer(dataPreprocessor: dataPreprocessor,
                                 encoding: encoding,
                                 emptyResponseCodes: emptyResponseCodes,
                                 emptyRequestMethods: emptyRequestMethods)
    }
}

@available(*, deprecated, message: "JSONResponseSerializer deprecated and will be removed in Alamofire 6. Use DecodableResponseSerializer instead.")
public final class JSONResponseSerializer: ResponseSerializer {
    public let dataPreprocessor: any DataPreprocessor
    public let emptyResponseCodes: Set<Int>
    public let emptyRequestMethods: Set<HTTPMethod>
    public let options: JSONSerialization.ReadingOptions

    public init(dataPreprocessor: any DataPreprocessor = JSONResponseSerializer.defaultDataPreprocessor,
                emptyResponseCodes: Set<Int> = JSONResponseSerializer.defaultEmptyResponseCodes,
                emptyRequestMethods: Set<HTTPMethod> = JSONResponseSerializer.defaultEmptyRequestMethods,
                options: JSONSerialization.ReadingOptions = .allowFragments) {
        self.dataPreprocessor = dataPreprocessor
        self.emptyResponseCodes = emptyResponseCodes
        self.emptyRequestMethods = emptyRequestMethods
        self.options = options
    }

    public func serialize(request: URLRequest?, response: HTTPURLResponse?, data: Data?, error: (any Error)?) throws -> Any {
        guard error == nil else { throw error! }

        guard var data, !data.isEmpty else {
            guard emptyResponseAllowed(forRequest: request, response: response) else {
                throw AFError.responseSerializationFailed(reason: .inputDataNilOrZeroLength)
            }

            return NSNull()
        }

        data = try dataPreprocessor.preprocess(data)

        do {
            return try JSONSerialization.jsonObject(with: data, options: options)
        } catch {
            throw AFError.responseSerializationFailed(reason: .jsonSerializationFailed(error: error))
        }
    }
}

public protocol EmptyResponse: Sendable {
    static func emptyValue() -> Self
}

public struct Empty: Hashable, Codable, Sendable {
    public static let value = Empty()
}

extension Empty: EmptyResponse {
    public static func emptyValue() -> Empty {
        value
    }
}

public protocol DataDecoder: Sendable {
    func decode<D: Decodable>(_ type: D.Type, from data: Data) throws -> D
}

extension JSONDecoder: DataDecoder {}
extension PropertyListDecoder: DataDecoder {}

public final class DecodableResponseSerializer<T: Decodable>: ResponseSerializer where T: Sendable {
    public let dataPreprocessor: any DataPreprocessor
    public let decoder: any DataDecoder
    public let emptyResponseCodes: Set<Int>
    public let emptyRequestMethods: Set<HTTPMethod>

    public init(dataPreprocessor: any DataPreprocessor = DecodableResponseSerializer.defaultDataPreprocessor,
                decoder: any DataDecoder = JSONDecoder(),
                emptyResponseCodes: Set<Int> = DecodableResponseSerializer.defaultEmptyResponseCodes,
                emptyRequestMethods: Set<HTTPMethod> = DecodableResponseSerializer.defaultEmptyRequestMethods) {
        self.dataPreprocessor = dataPreprocessor
        self.decoder = decoder
        self.emptyResponseCodes = emptyResponseCodes
        self.emptyRequestMethods = emptyRequestMethods
    }

    public func serialize(request: URLRequest?, response: HTTPURLResponse?, data: Data?, error: (any Error)?) throws -> T {
        guard error == nil else { throw error! }

        guard var data, !data.isEmpty else {
            guard emptyResponseAllowed(forRequest: request, response: response) else {
                throw AFError.responseSerializationFailed(reason: .inputDataNilOrZeroLength)
            }

            guard let emptyResponseType = T.self as? any EmptyResponse.Type, let emptyValue = emptyResponseType.emptyValue() as? T else {
                throw AFError.responseSerializationFailed(reason: .invalidEmptyResponse(type: "\(T.self)"))
            }

            return emptyValue
        }

        data = try dataPreprocessor.preprocess(data)

        do {
            return try decoder.decode(T.self, from: data)
        } catch {
            throw AFError.responseSerializationFailed(reason: .decodingFailed(error: error))
        }
    }
}

extension ResponseSerializer {
    public static func decodable<T: Decodable>(of type: T.Type,
                                               dataPreprocessor: any DataPreprocessor = DecodableResponseSerializer<T>.defaultDataPreprocessor,
                                               decoder: any DataDecoder = JSONDecoder(),
                                               emptyResponseCodes: Set<Int> = DecodableResponseSerializer<T>.defaultEmptyResponseCodes,
                                               emptyRequestMethods: Set<HTTPMethod> = DecodableResponseSerializer<T>.defaultEmptyRequestMethods) -> DecodableResponseSerializer<T> where Self == DecodableResponseSerializer<T> {
        DecodableResponseSerializer<T>(dataPreprocessor: dataPreprocessor,
                                       decoder: decoder,
                                       emptyResponseCodes: emptyResponseCodes,
                                       emptyRequestMethods: emptyRequestMethods)
    }
}
