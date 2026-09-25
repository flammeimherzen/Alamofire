
import Foundation

#if canImport(Security)
@preconcurrency import Security
#endif

public enum AFError: Error, Sendable {
    public enum MultipartEncodingFailureReason: Sendable {
        case bodyPartURLInvalid(url: URL)
        case bodyPartFilenameInvalid(in: URL)
        case bodyPartFileNotReachable(at: URL)
        case bodyPartFileNotReachableWithError(atURL: URL, error: any Error)
        case bodyPartFileIsDirectory(at: URL)
        case bodyPartFileSizeNotAvailable(at: URL)
        case bodyPartFileSizeQueryFailedWithError(forURL: URL, error: any Error)
        case bodyPartInputStreamCreationFailed(for: URL)
        case outputStreamCreationFailed(for: URL)
        case outputStreamFileAlreadyExists(at: URL)
        case outputStreamURLInvalid(url: URL)
        case outputStreamWriteFailed(error: any Error)
        case inputStreamReadFailed(error: any Error)
    }

    public struct UnexpectedInputStreamLength: Error {
        public var bytesExpected: UInt64
        public var bytesRead: UInt64
    }

    public enum ParameterEncodingFailureReason: Sendable {
        case missingURL
        case jsonEncodingFailed(error: any Error)
        case customEncodingFailed(error: any Error)
    }

    public enum ParameterEncoderFailureReason: Sendable {
        public enum RequiredComponent: Sendable {
            case url
            case httpMethod(rawValue: String)
        }

        case missingRequiredComponent(RequiredComponent)
        case encoderFailed(error: any Error)
    }

    public enum ResponseValidationFailureReason: Sendable {
        case dataFileNil
        case dataFileReadFailed(at: URL)
        case missingContentType(acceptableContentTypes: [String])
        case unacceptableContentType(acceptableContentTypes: [String], responseContentType: String)
        case unacceptableStatusCode(code: Int)
        case customValidationFailed(error: any Error)
    }

    public enum ResponseSerializationFailureReason: Sendable {
        case inputDataNilOrZeroLength
        case inputFileNil
        case inputFileReadFailed(at: URL)
        case stringSerializationFailed(encoding: String.Encoding)
        case jsonSerializationFailed(error: any Error)
        case decodingFailed(error: any Error)
        case customSerializationFailed(error: any Error)
        case invalidEmptyResponse(type: String)
    }

    #if canImport(Security)
    public enum ServerTrustFailureReason: Sendable {
        public struct Output: Sendable {
            public let host: String
            public let trust: SecTrust
            public let status: OSStatus
            public let result: SecTrustResultType

            init(_ host: String, _ trust: SecTrust, _ status: OSStatus, _ result: SecTrustResultType) {
                self.host = host
                self.trust = trust
                self.status = status
                self.result = result
            }
        }

        case noRequiredEvaluator(host: String)
        case noCertificatesFound
        case noPublicKeysFound
        case policyApplicationFailed(trust: SecTrust, policy: SecPolicy, status: OSStatus)
        case settingAnchorCertificatesFailed(status: OSStatus, certificates: [SecCertificate])
        case revocationPolicyCreationFailed
        case trustEvaluationFailed(error: (any Error)?)
        case defaultEvaluationFailed(output: Output)
        case hostValidationFailed(output: Output)
        case revocationCheckFailed(output: Output, options: RevocationTrustEvaluator.Options)
        case certificatePinningFailed(host: String, trust: SecTrust, pinnedCertificates: [SecCertificate], serverCertificates: [SecCertificate])
        case publicKeyPinningFailed(host: String, trust: SecTrust, pinnedKeys: [SecKey], serverKeys: [SecKey])
        case customEvaluationFailed(error: any Error)
    }
    #endif

    public enum URLRequestValidationFailureReason: Sendable {
        case bodyDataInGETRequest(Data)
    }

    case createUploadableFailed(error: any Error)
    case createURLRequestFailed(error: any Error)
    case downloadedFileMoveFailed(error: any Error, source: URL, destination: URL)
    case explicitlyCancelled
    case invalidURL(url: any URLConvertible)
    case multipartEncodingFailed(reason: MultipartEncodingFailureReason)
    case parameterEncodingFailed(reason: ParameterEncodingFailureReason)
    case parameterEncoderFailed(reason: ParameterEncoderFailureReason)
    case requestAdaptationFailed(error: any Error)
    case requestRetryFailed(retryError: any Error, originalError: any Error)
    case responseValidationFailed(reason: ResponseValidationFailureReason)
    case responseSerializationFailed(reason: ResponseSerializationFailureReason)
    #if canImport(Security)
    case serverTrustEvaluationFailed(reason: ServerTrustFailureReason)
    #endif
    case sessionDeinitialized
    case sessionInvalidated(error: (any Error)?)
    case sessionTaskFailed(error: any Error)
    case urlRequestValidationFailed(reason: URLRequestValidationFailureReason)
}

extension Error {
    public var asAFError: AFError? {
        self as? AFError
    }

    public func asAFError(orFailWith message: @autoclosure () -> String, file: StaticString = #file, line: UInt = #line) -> AFError {
        guard let afError = self as? AFError else {
            fatalError(message(), file: file, line: line)
        }
        return afError
    }

    func asAFError(or defaultAFError: @autoclosure () -> AFError) -> AFError {
        self as? AFError ?? defaultAFError()
    }
}

extension AFError {
    public var isSessionDeinitializedError: Bool {
        if case .sessionDeinitialized = self { return true }
        return false
    }

    public var isSessionInvalidatedError: Bool {
        if case .sessionInvalidated = self { return true }
        return false
    }

    public var isExplicitlyCancelledError: Bool {
        if case .explicitlyCancelled = self { return true }
        return false
    }

    public var isInvalidURLError: Bool {
        if case .invalidURL = self { return true }
        return false
    }

    public var isParameterEncodingError: Bool {
        if case .parameterEncodingFailed = self { return true }
        return false
    }

    public var isParameterEncoderError: Bool {
        if case .parameterEncoderFailed = self { return true }
        return false
    }

    public var isMultipartEncodingError: Bool {
        if case .multipartEncodingFailed = self { return true }
        return false
    }

    public var isRequestAdaptationError: Bool {
        if case .requestAdaptationFailed = self { return true }
        return false
    }

    public var isResponseValidationError: Bool {
        if case .responseValidationFailed = self { return true }
        return false
    }

    public var isResponseSerializationError: Bool {
        if case .responseSerializationFailed = self { return true }
        return false
    }

    #if canImport(Security)
    public var isServerTrustEvaluationError: Bool {
        if case .serverTrustEvaluationFailed = self { return true }
        return false
    }
    #endif

    public var isRequestRetryError: Bool {
        if case .requestRetryFailed = self { return true }
        return false
    }

    public var isCreateUploadableError: Bool {
        if case .createUploadableFailed = self { return true }
        return false
    }

    public var isCreateURLRequestError: Bool {
        if case .createURLRequestFailed = self { return true }
        return false
    }

    public var isDownloadedFileMoveError: Bool {
        if case .downloadedFileMoveFailed = self { return true }
        return false
    }

    public var isSessionTaskError: Bool {
        if case .sessionTaskFailed = self { return true }
        return false
    }
}

extension AFError {
    public var urlConvertible: (any URLConvertible)? {
        guard case let .invalidURL(url) = self else { return nil }
        return url
    }

    public var url: URL? {
        guard case let .multipartEncodingFailed(reason) = self else { return nil }
        return reason.url
    }

    public var underlyingError: (any Error)? {
        switch self {
        case let .multipartEncodingFailed(reason):
            return reason.underlyingError
        case let .parameterEncodingFailed(reason):
            return reason.underlyingError
        case let .parameterEncoderFailed(reason):
            return reason.underlyingError
        case let .requestAdaptationFailed(error):
            return error
        case let .requestRetryFailed(retryError, _):
            return retryError
        case let .responseValidationFailed(reason):
            return reason.underlyingError
        case let .responseSerializationFailed(reason):
            return reason.underlyingError
        #if canImport(Security)
        case let .serverTrustEvaluationFailed(reason):
            return reason.underlyingError
        #endif
        case let .sessionInvalidated(error):
            return error
        case let .createUploadableFailed(error):
            return error
        case let .createURLRequestFailed(error):
            return error
        case let .downloadedFileMoveFailed(error, _, _):
            return error
        case let .sessionTaskFailed(error):
            return error
        case .explicitlyCancelled,
             .invalidURL,
             .sessionDeinitialized,
             .urlRequestValidationFailed:
            return nil
        }
    }

    public var acceptableContentTypes: [String]? {
        guard case let .responseValidationFailed(reason) = self else { return nil }
        return reason.acceptableContentTypes
    }

    public var responseContentType: String? {
        guard case let .responseValidationFailed(reason) = self else { return nil }
        return reason.responseContentType
    }

    public var responseCode: Int? {
        guard case let .responseValidationFailed(reason) = self else { return nil }
        return reason.responseCode
    }

    public var failedStringEncoding: String.Encoding? {
        guard case let .responseSerializationFailed(reason) = self else { return nil }
        return reason.failedStringEncoding
    }

    public var sourceURL: URL? {
        guard case let .downloadedFileMoveFailed(_, source, _) = self else { return nil }
        return source
    }

    public var destinationURL: URL? {
        guard case let .downloadedFileMoveFailed(_, _, destination) = self else { return nil }
        return destination
    }

    #if canImport(Security)
    public var downloadResumeData: Data? {
        (underlyingError as? URLError)?.userInfo[NSURLSessionDownloadTaskResumeData] as? Data
    }
    #endif
}

extension AFError.ParameterEncodingFailureReason {
    var underlyingError: (any Error)? {
        switch self {
        case let .jsonEncodingFailed(error),
             let .customEncodingFailed(error):
            error
        case .missingURL:
            nil
        }
    }
}

extension AFError.ParameterEncoderFailureReason {
    var underlyingError: (any Error)? {
        switch self {
        case let .encoderFailed(error):
            error
        case .missingRequiredComponent:
            nil
        }
    }
}

extension AFError.MultipartEncodingFailureReason {
    var url: URL? {
        switch self {
        case let .bodyPartURLInvalid(url),
             let .bodyPartFilenameInvalid(url),
             let .bodyPartFileNotReachable(url),
             let .bodyPartFileIsDirectory(url),
             let .bodyPartFileSizeNotAvailable(url),
             let .bodyPartInputStreamCreationFailed(url),
             let .outputStreamCreationFailed(url),
             let .outputStreamFileAlreadyExists(url),
             let .outputStreamURLInvalid(url),
             let .bodyPartFileNotReachableWithError(url, _),
             let .bodyPartFileSizeQueryFailedWithError(url, _):
            url
        case .outputStreamWriteFailed,
             .inputStreamReadFailed:
            nil
        }
    }

    var underlyingError: (any Error)? {
        switch self {
        case let .bodyPartFileNotReachableWithError(_, error),
             let .bodyPartFileSizeQueryFailedWithError(_, error),
             let .outputStreamWriteFailed(error),
             let .inputStreamReadFailed(error):
            error
        case .bodyPartURLInvalid,
             .bodyPartFilenameInvalid,
             .bodyPartFileNotReachable,
             .bodyPartFileIsDirectory,
             .bodyPartFileSizeNotAvailable,
             .bodyPartInputStreamCreationFailed,
             .outputStreamCreationFailed,
             .outputStreamFileAlreadyExists,
             .outputStreamURLInvalid:
            nil
        }
    }
}

extension AFError.ResponseValidationFailureReason {
    var acceptableContentTypes: [String]? {
        switch self {
        case let .missingContentType(types),
             let .unacceptableContentType(types, _):
            types
        case .dataFileNil,
             .dataFileReadFailed,
             .unacceptableStatusCode,
             .customValidationFailed:
            nil
        }
    }

    var responseContentType: String? {
        switch self {
        case let .unacceptableContentType(_, responseType):
            responseType
        case .dataFileNil,
             .dataFileReadFailed,
             .missingContentType,
             .unacceptableStatusCode,
             .customValidationFailed:
            nil
        }
    }

    var responseCode: Int? {
        switch self {
        case let .unacceptableStatusCode(code):
            code
        case .dataFileNil,
             .dataFileReadFailed,
             .missingContentType,
             .unacceptableContentType,
             .customValidationFailed:
            nil
        }
    }

    var underlyingError: (any Error)? {
        switch self {
        case let .customValidationFailed(error):
            error
        case .dataFileNil,
             .dataFileReadFailed,
             .missingContentType,
             .unacceptableContentType,
             .unacceptableStatusCode:
            nil
        }
    }
}

extension AFError.ResponseSerializationFailureReason {
    var failedStringEncoding: String.Encoding? {
        switch self {
        case let .stringSerializationFailed(encoding):
            encoding
        case .inputDataNilOrZeroLength,
             .inputFileNil,
             .inputFileReadFailed(_),
             .jsonSerializationFailed(_),
             .decodingFailed(_),
             .customSerializationFailed(_),
             .invalidEmptyResponse:
            nil
        }
    }

    var underlyingError: (any Error)? {
        switch self {
        case let .jsonSerializationFailed(error),
             let .decodingFailed(error),
             let .customSerializationFailed(error):
            error
        case .inputDataNilOrZeroLength,
             .inputFileNil,
             .inputFileReadFailed,
             .stringSerializationFailed,
             .invalidEmptyResponse:
            nil
        }
    }
}

#if canImport(Security)
extension AFError.ServerTrustFailureReason {
    var output: AFError.ServerTrustFailureReason.Output? {
        switch self {
        case let .defaultEvaluationFailed(output),
             let .hostValidationFailed(output),
             let .revocationCheckFailed(output, _):
            output
        case .noRequiredEvaluator,
             .noCertificatesFound,
             .noPublicKeysFound,
             .policyApplicationFailed,
             .settingAnchorCertificatesFailed,
             .revocationPolicyCreationFailed,
             .trustEvaluationFailed,
             .certificatePinningFailed,
             .publicKeyPinningFailed,
             .customEvaluationFailed:
            nil
        }
    }

    var underlyingError: (any Error)? {
        switch self {
        case let .customEvaluationFailed(error):
            error
        case let .trustEvaluationFailed(error):
            error
        case .noRequiredEvaluator,
             .noCertificatesFound,
             .noPublicKeysFound,
             .policyApplicationFailed,
             .settingAnchorCertificatesFailed,
             .revocationPolicyCreationFailed,
             .defaultEvaluationFailed,
             .hostValidationFailed,
             .revocationCheckFailed,
             .certificatePinningFailed,
             .publicKeyPinningFailed:
            nil
        }
    }
}
#endif

extension AFError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .explicitlyCancelled:
            return "Request explicitly cancelled."
        case let .invalidURL(url):
            return "URL is not valid: \(url)"
        case let .parameterEncodingFailed(reason):
            return reason.localizedDescription
        case let .parameterEncoderFailed(reason):
            return reason.localizedDescription
        case let .multipartEncodingFailed(reason):
            return reason.localizedDescription
        case let .requestAdaptationFailed(error):
            return "Request adaption failed with error: \(error.localizedDescription)"
        case let .responseValidationFailed(reason):
            return reason.localizedDescription
        case let .responseSerializationFailed(reason):
            return reason.localizedDescription
        case let .requestRetryFailed(retryError, originalError):
            return """
            Request retry failed with retry error: \(retryError.localizedDescription), \
            original error: \(originalError.localizedDescription)
            """
        case .sessionDeinitialized:
            return """
            Session was invalidated without error, so it was likely deinitialized unexpectedly. \
            Be sure to retain a reference to your Session for the duration of your requests.
            """
        case let .sessionInvalidated(error):
            return "Session was invalidated with error: \(error?.localizedDescription ?? "No description.")"
        #if canImport(Security)
        case let .serverTrustEvaluationFailed(reason):
            return "Server trust evaluation failed due to reason: \(reason.localizedDescription)"
        #endif
        case let .urlRequestValidationFailed(reason):
            return "URLRequest validation failed due to reason: \(reason.localizedDescription)"
        case let .createUploadableFailed(error):
            return "Uploadable creation failed with error: \(error.localizedDescription)"
        case let .createURLRequestFailed(error):
            return "URLRequest creation failed with error: \(error.localizedDescription)"
        case let .downloadedFileMoveFailed(error, source, destination):
            return "Moving downloaded file from: \(source) to: \(destination) failed with error: \(error.localizedDescription)"
        case let .sessionTaskFailed(error):
            return "URLSessionTask failed with error: \(error.localizedDescription)"
        }
    }
}

extension AFError.ParameterEncodingFailureReason {
    var localizedDescription: String {
        switch self {
        case .missingURL:
            "URL request to encode was missing a URL"
        case let .jsonEncodingFailed(error):
            "JSON could not be encoded because of error:\n\(error.localizedDescription)"
        case let .customEncodingFailed(error):
            "Custom parameter encoder failed with error: \(error.localizedDescription)"
        }
    }
}

extension AFError.ParameterEncoderFailureReason {
    var localizedDescription: String {
        switch self {
        case let .missingRequiredComponent(component):
            "Encoding failed due to a missing request component: \(component)"
        case let .encoderFailed(error):
            "The underlying encoder failed with the error: \(error)"
        }
    }
}

extension AFError.MultipartEncodingFailureReason {
    var localizedDescription: String {
        switch self {
        case let .bodyPartURLInvalid(url):
            "The URL provided is not a file URL: \(url)"
        case let .bodyPartFilenameInvalid(url):
            "The URL provided does not have a valid filename: \(url)"
        case let .bodyPartFileNotReachable(url):
            "The URL provided is not reachable: \(url)"
        case let .bodyPartFileNotReachableWithError(url, error):
            """
            The system returned an error while checking the provided URL for reachability.
            URL: \(url)
            Error: \(error)
            """
        case let .bodyPartFileIsDirectory(url):
            "The URL provided is a directory: \(url)"
        case let .bodyPartFileSizeNotAvailable(url):
            "Could not fetch the file size from the provided URL: \(url)"
        case let .bodyPartFileSizeQueryFailedWithError(url, error):
            """
            The system returned an error while attempting to fetch the file size from the provided URL.
            URL: \(url)
            Error: \(error)
            """
        case let .bodyPartInputStreamCreationFailed(url):
            "Failed to create an InputStream for the provided URL: \(url)"
        case let .outputStreamCreationFailed(url):
            "Failed to create an OutputStream for URL: \(url)"
        case let .outputStreamFileAlreadyExists(url):
            "A file already exists at the provided URL: \(url)"
        case let .outputStreamURLInvalid(url):
            "The provided OutputStream URL is invalid: \(url)"
        case let .outputStreamWriteFailed(error):
            "OutputStream write failed with error: \(error)"
        case let .inputStreamReadFailed(error):
            "InputStream read failed with error: \(error)"
        }
    }
}

extension AFError.ResponseSerializationFailureReason {
    var localizedDescription: String {
        switch self {
        case .inputDataNilOrZeroLength:
            "Response could not be serialized, input data was nil or zero length."
        case .inputFileNil:
            "Response could not be serialized, input file was nil."
        case let .inputFileReadFailed(url):
            "Response could not be serialized, input file could not be read: \(url)."
        case let .stringSerializationFailed(encoding):
            "String could not be serialized with encoding: \(encoding)."
        case let .jsonSerializationFailed(error):
            "JSON could not be serialized because of error:\n\(error.localizedDescription)"
        case let .invalidEmptyResponse(type):
            """
            Empty response could not be serialized to type: \(type). \
            Use Empty as the expected type for such responses.
            """
        case let .decodingFailed(error):
            "Response could not be decoded because of error:\n\(error.localizedDescription)"
        case let .customSerializationFailed(error):
            "Custom response serializer failed with error:\n\(error.localizedDescription)"
        }
    }
}

extension AFError.ResponseValidationFailureReason {
    var localizedDescription: String {
        switch self {
        case .dataFileNil:
            "Response could not be validated, data file was nil."
        case let .dataFileReadFailed(url):
            "Response could not be validated, data file could not be read: \(url)."
        case let .missingContentType(types):
            """
            Response Content-Type was missing and acceptable content types \
            (\(types.joined(separator: ","))) do not match "*/*".
            """
        case let .unacceptableContentType(acceptableTypes, responseType):
            """
            Response Content-Type "\(responseType)" does not match any acceptable types: \
            \(acceptableTypes.joined(separator: ",")).
            """
        case let .unacceptableStatusCode(code):
            "Response status code was unacceptable: \(code)."
        case let .customValidationFailed(error):
            "Custom response validation failed with error: \(error.localizedDescription)"
        }
    }
}

#if canImport(Security)
extension AFError.ServerTrustFailureReason {
    var localizedDescription: String {
        switch self {
        case let .noRequiredEvaluator(host):
            "A ServerTrustEvaluating value is required for host \(host) but none was found."
        case .noCertificatesFound:
            "No certificates were found or provided for evaluation."
        case .noPublicKeysFound:
            "No public keys were found or provided for evaluation."
        case .policyApplicationFailed:
            "Attempting to set a SecPolicy failed."
        case .settingAnchorCertificatesFailed:
            "Attempting to set the provided certificates as anchor certificates failed."
        case .revocationPolicyCreationFailed:
            "Attempting to create a revocation policy failed."
        case let .trustEvaluationFailed(error):
            "SecTrust evaluation failed with error: \(error?.localizedDescription ?? "None")"
        case let .defaultEvaluationFailed(output):
            "Default evaluation failed for host \(output.host)."
        case let .hostValidationFailed(output):
            "Host validation failed for host \(output.host)."
        case let .revocationCheckFailed(output, _):
            "Revocation check failed for host \(output.host)."
        case let .certificatePinningFailed(host, _, _, _):
            "Certificate pinning failed for host \(host)."
        case let .publicKeyPinningFailed(host, _, _, _):
            "Public key pinning failed for host \(host)."
        case let .customEvaluationFailed(error):
            "Custom trust evaluation failed with error: \(error.localizedDescription)"
        }
    }
}
#endif

extension AFError.URLRequestValidationFailureReason {
    var localizedDescription: String {
        switch self {
        case let .bodyDataInGETRequest(data):
            """
            Invalid URLRequest: Requests with GET method cannot have body data:
            \(String(decoding: data, as: UTF8.self))
            """
        }
    }
}
