
import Foundation

extension Request {

    fileprivate typealias ErrorReason = AFError.ResponseValidationFailureReason

    public typealias ValidationResult = Result<Void, any(Error & Sendable)>

    fileprivate struct MIMEType {
        let type: String
        let subtype: String

        var isWildcard: Bool { type == "*" && subtype == "*" }

        init?(_ string: String) {
            let components: [String] = {
                let stripped = string.trimmingCharacters(in: .whitespacesAndNewlines)
                let split = stripped[..<(stripped.range(of: ";")?.lowerBound ?? stripped.endIndex)]

                return split.components(separatedBy: "/")
            }()

            if let type = components.first, let subtype = components.last {
                self.type = type
                self.subtype = subtype
            } else {
                return nil
            }
        }

        func matches(_ mime: MIMEType) -> Bool {
            switch (type, subtype) {
            case (mime.type, mime.subtype), (mime.type, "*"), ("*", mime.subtype), ("*", "*"):
                true
            default:
                false
            }
        }
    }

    fileprivate var acceptableStatusCodes: Range<Int> { 200..<300 }

    fileprivate var acceptableContentTypes: [String] {
        if let accept = request?.value(forHTTPHeaderField: "Accept") {
            return accept.components(separatedBy: ",")
        }

        return ["*/*"]
    }

    fileprivate func validate<S: Sequence>(statusCode acceptableStatusCodes: S,
                                           response: HTTPURLResponse)
        -> ValidationResult
        where S.Iterator.Element == Int {
        if acceptableStatusCodes.contains(response.statusCode) {
            return .success(())
        } else {
            let reason: ErrorReason = .unacceptableStatusCode(code: response.statusCode)
            return .failure(AFError.responseValidationFailed(reason: reason))
        }
    }

    fileprivate func validate<S: Sequence>(contentType acceptableContentTypes: S,
                                           response: HTTPURLResponse,
                                           isEmpty: Bool)
        -> ValidationResult
        where S.Iterator.Element == String {
        guard !isEmpty else { return .success(()) }

        return validate(contentType: acceptableContentTypes, response: response)
    }

    fileprivate func validate<S: Sequence>(contentType acceptableContentTypes: S,
                                           response: HTTPURLResponse)
        -> ValidationResult
        where S.Iterator.Element == String {
        guard
            let responseContentType = response.mimeType,
            let responseMIMEType = MIMEType(responseContentType)
        else {
            for contentType in acceptableContentTypes {
                if let mimeType = MIMEType(contentType), mimeType.isWildcard {
                    return .success(())
                }
            }

            let error: AFError = {
                let reason: ErrorReason = .missingContentType(acceptableContentTypes: acceptableContentTypes.sorted())
                return AFError.responseValidationFailed(reason: reason)
            }()

            return .failure(error)
        }

        for contentType in acceptableContentTypes {
            if let acceptableMIMEType = MIMEType(contentType), acceptableMIMEType.matches(responseMIMEType) {
                return .success(())
            }
        }

        let error: AFError = {
            let reason: ErrorReason = .unacceptableContentType(acceptableContentTypes: acceptableContentTypes.sorted(),
                                                               responseContentType: responseContentType)

            return AFError.responseValidationFailed(reason: reason)
        }()

        return .failure(error)
    }
}

extension DataRequest {
    public typealias Validation = @Sendable (URLRequest?, HTTPURLResponse, Data?) -> ValidationResult

    @preconcurrency
    @discardableResult
    public func validate<S: Sequence>(statusCode acceptableStatusCodes: S) -> Self where S.Iterator.Element == Int, S: Sendable {
        validate { [unowned self] _, response, _ in
            self.validate(statusCode: acceptableStatusCodes, response: response)
        }
    }

    @preconcurrency
    @discardableResult
    public func validate<S: Sequence>(contentType acceptableContentTypes: @escaping @Sendable @autoclosure () -> S) -> Self where S.Iterator.Element == String, S: Sendable {
        validate { [unowned self] _, response, data in
            self.validate(contentType: acceptableContentTypes(), response: response, isEmpty: (data == nil || data?.isEmpty == true))
        }
    }

    @discardableResult
    public func validate() -> Self {
        let contentTypes: @Sendable () -> [String] = { [unowned self] in
            acceptableContentTypes
        }
        return validate(statusCode: acceptableStatusCodes).validate(contentType: contentTypes())
    }
}

extension DataStreamRequest {
    public typealias Validation = @Sendable (_ request: URLRequest?, _ response: HTTPURLResponse) -> ValidationResult

    @preconcurrency
    @discardableResult
    public func validate<S: Sequence>(statusCode acceptableStatusCodes: S) -> Self where S.Iterator.Element == Int, S: Sendable {
        validate { [unowned self] _, response in
            self.validate(statusCode: acceptableStatusCodes, response: response)
        }
    }

    @preconcurrency
    @discardableResult
    public func validate<S: Sequence>(contentType acceptableContentTypes: @escaping @Sendable @autoclosure () -> S) -> Self where S.Iterator.Element == String, S: Sendable {
        validate { [unowned self] _, response in
            self.validate(contentType: acceptableContentTypes(), response: response)
        }
    }

    @discardableResult
    public func validate() -> Self {
        let contentTypes: @Sendable () -> [String] = { [unowned self] in
            acceptableContentTypes
        }
        return validate(statusCode: acceptableStatusCodes).validate(contentType: contentTypes())
    }
}

extension DownloadRequest {
    public typealias Validation = @Sendable (_ request: URLRequest?,
                                             _ response: HTTPURLResponse,
                                             _ fileURL: URL?)
        -> ValidationResult

    @preconcurrency
    @discardableResult
    public func validate<S: Sequence>(statusCode acceptableStatusCodes: S) -> Self where S.Iterator.Element == Int, S: Sendable {
        validate { [unowned self] _, response, _ in
            self.validate(statusCode: acceptableStatusCodes, response: response)
        }
    }

    @preconcurrency
    @discardableResult
    public func validate<S: Sequence>(contentType acceptableContentTypes: @escaping @Sendable @autoclosure () -> S) -> Self where S.Iterator.Element == String, S: Sendable {
        validate { [unowned self] _, response, fileURL in
            guard let fileURL else {
                return .failure(AFError.responseValidationFailed(reason: .dataFileNil))
            }

            do {
                let isEmpty = try (fileURL.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0) == 0
                return self.validate(contentType: acceptableContentTypes(), response: response, isEmpty: isEmpty)
            } catch {
                return .failure(AFError.responseValidationFailed(reason: .dataFileReadFailed(at: fileURL)))
            }
        }
    }

    @discardableResult
    public func validate() -> Self {
        let contentTypes: @Sendable () -> [String] = { [unowned self] in
            acceptableContentTypes
        }
        return validate(statusCode: acceptableStatusCodes).validate(contentType: contentTypes())
    }
}
