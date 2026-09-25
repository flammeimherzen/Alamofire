
import Foundation

public typealias AFDataResponse<Success> = DataResponse<Success, AFError>
public typealias AFDownloadResponse<Success> = DownloadResponse<Success, AFError>

public struct DataResponse<Success, Failure: Error>: Sendable where Success: Sendable, Failure: Sendable {
    public let request: URLRequest?

    public let response: HTTPURLResponse?

    public let data: Data?

    public let metrics: URLSessionTaskMetrics?

    public let serializationDuration: TimeInterval

    public let result: Result<Success, Failure>

    public var value: Success? { result.success }

    public var error: Failure? { result.failure }

    public init(request: URLRequest?,
                response: HTTPURLResponse?,
                data: Data?,
                metrics: URLSessionTaskMetrics?,
                serializationDuration: TimeInterval,
                result: Result<Success, Failure>) {
        self.request = request
        self.response = response
        self.data = data
        self.metrics = metrics
        self.serializationDuration = serializationDuration
        self.result = result
    }
}

extension DataResponse: CustomStringConvertible, CustomDebugStringConvertible {
    public var description: String {
        "\(result)"
    }

    public var debugDescription: String {
        guard let urlRequest = request else { return "[Request]: None\n[Result]: \(result)" }

        let requestDescription = DebugDescription.description(of: urlRequest)

        let responseDescription = response.map { response in
            let responseBodyDescription = DebugDescription.description(for: data, headers: response.headers)

            return """
            \(DebugDescription.description(of: response))
                \(responseBodyDescription.indentingNewlines())
            """
        } ?? "[Response]: None"

        let networkDuration = metrics.map { "\($0.taskInterval.duration)s" } ?? "None"

        return """
        \(requestDescription)
        \(responseDescription)
        [Network Duration]: \(networkDuration)
        [Serialization Duration]: \(serializationDuration)s
        [Result]: \(result)
        """
    }
}

extension DataResponse {
    public func map<NewSuccess>(_ transform: (Success) -> NewSuccess) -> DataResponse<NewSuccess, Failure> {
        DataResponse<NewSuccess, Failure>(request: request,
                                          response: response,
                                          data: data,
                                          metrics: metrics,
                                          serializationDuration: serializationDuration,
                                          result: result.map(transform))
    }

    public func tryMap<NewSuccess>(_ transform: (Success) throws -> NewSuccess) -> DataResponse<NewSuccess, any Error> {
        DataResponse<NewSuccess, any Error>(request: request,
                                            response: response,
                                            data: data,
                                            metrics: metrics,
                                            serializationDuration: serializationDuration,
                                            result: result.tryMap(transform))
    }

    public func mapError<NewFailure: Error>(_ transform: (Failure) -> NewFailure) -> DataResponse<Success, NewFailure> {
        DataResponse<Success, NewFailure>(request: request,
                                          response: response,
                                          data: data,
                                          metrics: metrics,
                                          serializationDuration: serializationDuration,
                                          result: result.mapError(transform))
    }

    public func tryMapError<NewFailure: Error>(_ transform: (Failure) throws -> NewFailure) -> DataResponse<Success, any Error> {
        DataResponse<Success, any Error>(request: request,
                                         response: response,
                                         data: data,
                                         metrics: metrics,
                                         serializationDuration: serializationDuration,
                                         result: result.tryMapError(transform))
    }
}

public struct DownloadResponse<Success, Failure: Error>: Sendable where Success: Sendable, Failure: Sendable {
    public let request: URLRequest?

    public let response: HTTPURLResponse?

    public let fileURL: URL?

    public let resumeData: Data?

    public let metrics: URLSessionTaskMetrics?

    public let serializationDuration: TimeInterval

    public let result: Result<Success, Failure>

    public var value: Success? { result.success }

    public var error: Failure? { result.failure }

    public init(request: URLRequest?,
                response: HTTPURLResponse?,
                fileURL: URL?,
                resumeData: Data?,
                metrics: URLSessionTaskMetrics?,
                serializationDuration: TimeInterval,
                result: Result<Success, Failure>) {
        self.request = request
        self.response = response
        self.fileURL = fileURL
        self.resumeData = resumeData
        self.metrics = metrics
        self.serializationDuration = serializationDuration
        self.result = result
    }
}

extension DownloadResponse: CustomStringConvertible, CustomDebugStringConvertible {
    public var description: String {
        "\(result)"
    }

    public var debugDescription: String {
        guard let urlRequest = request else { return "[Request]: None\n[Result]: \(result)" }

        let requestDescription = DebugDescription.description(of: urlRequest)
        let responseDescription = response.map(DebugDescription.description(of:)) ?? "[Response]: None"
        let networkDuration = metrics.map { "\($0.taskInterval.duration)s" } ?? "None"
        let resumeDataDescription = resumeData.map { "\($0)" } ?? "None"

        return """
        \(requestDescription)
        \(responseDescription)
        [File URL]: \(fileURL?.path ?? "None")
        [Resume Data]: \(resumeDataDescription)
        [Network Duration]: \(networkDuration)
        [Serialization Duration]: \(serializationDuration)s
        [Result]: \(result)
        """
    }
}

extension DownloadResponse {
    public func map<NewSuccess>(_ transform: (Success) -> NewSuccess) -> DownloadResponse<NewSuccess, Failure> {
        DownloadResponse<NewSuccess, Failure>(request: request,
                                              response: response,
                                              fileURL: fileURL,
                                              resumeData: resumeData,
                                              metrics: metrics,
                                              serializationDuration: serializationDuration,
                                              result: result.map(transform))
    }

    public func tryMap<NewSuccess>(_ transform: (Success) throws -> NewSuccess) -> DownloadResponse<NewSuccess, any Error> {
        DownloadResponse<NewSuccess, any Error>(request: request,
                                                response: response,
                                                fileURL: fileURL,
                                                resumeData: resumeData,
                                                metrics: metrics,
                                                serializationDuration: serializationDuration,
                                                result: result.tryMap(transform))
    }

    public func mapError<NewFailure: Error>(_ transform: (Failure) -> NewFailure) -> DownloadResponse<Success, NewFailure> {
        DownloadResponse<Success, NewFailure>(request: request,
                                              response: response,
                                              fileURL: fileURL,
                                              resumeData: resumeData,
                                              metrics: metrics,
                                              serializationDuration: serializationDuration,
                                              result: result.mapError(transform))
    }

    public func tryMapError<NewFailure: Error>(_ transform: (Failure) throws -> NewFailure) -> DownloadResponse<Success, any Error> {
        DownloadResponse<Success, any Error>(request: request,
                                             response: response,
                                             fileURL: fileURL,
                                             resumeData: resumeData,
                                             metrics: metrics,
                                             serializationDuration: serializationDuration,
                                             result: result.tryMapError(transform))
    }
}

private enum DebugDescription {
    static func description(of request: URLRequest) -> String {
        let requestSummary = "\(request.httpMethod!) \(request)"
        let requestHeadersDescription = DebugDescription.description(for: request.headers)
        let requestBodyDescription = DebugDescription.description(for: request.httpBody, headers: request.headers)

        return """
        [Request]: \(requestSummary)
            \(requestHeadersDescription.indentingNewlines())
            \(requestBodyDescription.indentingNewlines())
        """
    }

    static func description(of response: HTTPURLResponse) -> String {
        """
        [Response]:
            [Status Code]: \(response.statusCode)
            \(DebugDescription.description(for: response.headers).indentingNewlines())
        """
    }

    static func description(for headers: HTTPHeaders) -> String {
        guard !headers.isEmpty else { return "[Headers]: None" }

        let headerDescription = "\(headers.sorted())".indentingNewlines()
        return """
        [Headers]:
            \(headerDescription)
        """
    }

    static func description(for data: Data?,
                            headers: HTTPHeaders,
                            allowingPrintableTypes printableTypes: [String] = ["json", "xml", "text"],
                            maximumLength: Int = 100_000) -> String {
        guard let data, !data.isEmpty else { return "[Body]: None" }

        guard
            data.count <= maximumLength,
            printableTypes.compactMap({ headers["Content-Type"]?.contains($0) }).contains(true)
        else { return "[Body]: \(data.count) bytes" }

        return """
        [Body]:
            \(String(decoding: data, as: UTF8.self)
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .indentingNewlines())
        """
    }
}

extension String {
    fileprivate func indentingNewlines(by spaceCount: Int = 4) -> String {
        let spaces = String(repeating: " ", count: spaceCount)
        return replacingOccurrences(of: "\n", with: "\n\(spaces)")
    }
}
