
import Foundation

final class MultipartUpload: @unchecked Sendable {
    private let _result = Protected<Result<UploadRequest.Uploadable, any Error>?>(nil)
    var result: Result<UploadRequest.Uploadable, any Error> {
        if let value = _result.read({ $0 }) {
            return value
        } else {
            let result = Result { try build() }
            _result.write(result)

            return result
        }
    }

    private let multipartFormData: Protected<MultipartFormData>

    let encodingMemoryThreshold: UInt64
    let request: any URLRequestConvertible
    let fileManager: FileManager

    init(encodingMemoryThreshold: UInt64,
         request: any URLRequestConvertible,
         multipartFormData: MultipartFormData) {
        self.encodingMemoryThreshold = encodingMemoryThreshold
        self.request = request
        fileManager = multipartFormData.fileManager
        self.multipartFormData = Protected(multipartFormData)
    }

    func build() throws -> UploadRequest.Uploadable {
        let uploadable: UploadRequest.Uploadable
        if multipartFormData.read(\.contentLength) < encodingMemoryThreshold {
            let data = try multipartFormData.read { try $0.encode() }

            uploadable = .data(data)
        } else {
            let tempDirectoryURL = fileManager.temporaryDirectory
            let directoryURL = tempDirectoryURL.appendingPathComponent("org.alamofire.manager/multipart.form.data")
            let fileName = UUID().uuidString
            let fileURL = directoryURL.appendingPathComponent(fileName)

            try fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true, attributes: nil)

            do {
                try multipartFormData.read { try $0.writeEncodedData(to: fileURL) }
            } catch {
                try? fileManager.removeItem(at: fileURL)
                throw error
            }

            uploadable = .file(fileURL, shouldRemove: true)
        }

        return uploadable
    }
}

extension MultipartUpload: UploadConvertible {
    func asURLRequest() throws -> URLRequest {
        var urlRequest = try request.asURLRequest()

        multipartFormData.read { multipartFormData in
            urlRequest.headers.add(.contentType(multipartFormData.contentType))
        }

        return urlRequest
    }

    func createUploadable() throws -> UploadRequest.Uploadable {
        try result.get()
    }
}
