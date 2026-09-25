
#if canImport(zlib) && !os(Android)
import Foundation
import zlib

@available(macOS 10.15, iOS 13, tvOS 13, watchOS 6, *)
public struct DeflateRequestCompressor: Sendable, RequestInterceptor {
    public enum DuplicateHeaderBehavior: Sendable {
        case error
        case replace
        case skip
    }

    public struct DuplicateHeaderError: Error {}

    public let duplicateHeaderBehavior: DuplicateHeaderBehavior
    public let shouldCompressBodyData: @Sendable (_ bodyData: Data) -> Bool

    public init(duplicateHeaderBehavior: DuplicateHeaderBehavior = .error,
                shouldCompressBodyData: @escaping @Sendable (_ bodyData: Data) -> Bool = { _ in true }) {
        self.duplicateHeaderBehavior = duplicateHeaderBehavior
        self.shouldCompressBodyData = shouldCompressBodyData
    }

    public func adapt(_ urlRequest: URLRequest, for session: Session, completion: @escaping (Result<URLRequest, any Error>) -> Void) {
        guard let bodyData = urlRequest.httpBody else {
            completion(.success(urlRequest))
            return
        }

        guard shouldCompressBodyData(bodyData) else {
            completion(.success(urlRequest))
            return
        }

        if urlRequest.headers.value(for: "Content-Encoding") != nil {
            switch duplicateHeaderBehavior {
            case .error:
                completion(.failure(DuplicateHeaderError()))
                return
            case .replace:
                break
            case .skip:
                completion(.success(urlRequest))
                return
            }
        }

        var compressedRequest = urlRequest

        do {
            compressedRequest.httpBody = try deflate(bodyData)
            compressedRequest.headers.update(.contentEncoding("deflate"))
            completion(.success(compressedRequest))
        } catch {
            completion(.failure(error))
        }
    }

    func deflate(_ data: Data) throws -> Data {
        var output = Data([0x78, 0x5E])
        try output.append((data as NSData).compressed(using: .zlib) as Data)
        var checksum = adler32Checksum(of: data).bigEndian
        output.append(Data(bytes: &checksum, count: MemoryLayout<UInt32>.size))

        return output
    }

    func adler32Checksum(of data: Data) -> UInt32 {
        data.withUnsafeBytes { buffer in
            UInt32(adler32(1, buffer.baseAddress, UInt32(buffer.count)))
        }
    }
}

@available(macOS 10.15, iOS 13, tvOS 13, watchOS 6, *)
extension RequestInterceptor where Self == DeflateRequestCompressor {
    public static var deflateCompressor: DeflateRequestCompressor {
        DeflateRequestCompressor()
    }

    public static func deflateCompressor(
        duplicateHeaderBehavior: DeflateRequestCompressor.DuplicateHeaderBehavior = .error,
        shouldCompressBodyData: @escaping @Sendable (_ bodyData: Data) -> Bool = { _ in true }
    ) -> DeflateRequestCompressor {
        DeflateRequestCompressor(duplicateHeaderBehavior: duplicateHeaderBehavior,
                                 shouldCompressBodyData: shouldCompressBodyData)
    }
}
#endif
