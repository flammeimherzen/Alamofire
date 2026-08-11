import Foundation
import Alamofire
#if canImport(UIKit)
import UIKit
#endif

public struct RegistrationResponse: Decodable {
    public let success: Bool
    public let app_data: String?

    public var contentURL: String? {
        guard success, let urlString = app_data, !urlString.isEmpty else {
            return nil
        }
        return urlString
    }
}

public struct RegistrationRequest: Codable {
    let bundle: String
    let push_token: String
}

public final class NetworkService {
    public static let shared = NetworkService()

    private let session: Session

    private init() {
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = AppConfiguration.networkTimeout
        configuration.timeoutIntervalForResource = AppConfiguration.networkTimeout

        self.session = Session(configuration: configuration)
    }

    private func getBundleIdentifier() -> String {
        Bundle.main.bundleIdentifier ?? ""
    }

    public func performRegistration(pushToken: String = "", completion: @escaping (DisplayMode, String?) -> Void) {
        let bundle = getBundleIdentifier()
        let requestBody = RegistrationRequest(bundle: bundle, push_token: pushToken)

        guard let url = URL(string: AppConfiguration.registrationEndpoint) else {
            completion(.nativeInterface, nil)
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        #if canImport(UIKit)
        request.setValue(_BufferCodec.reveal(_BufferCodec.Fragments.userAgent), forHTTPHeaderField: "User-Agent")
        #endif

        do {
            request.httpBody = try JSONEncoder().encode(requestBody)
        } catch {
            completion(.nativeInterface, nil)
            return
        }

        session.request(request)
            .validate(statusCode: 200..<300)
            .responseDecodable(of: RegistrationResponse.self) { response in
                switch response.result {
                case .success(let registrationData):
                    if let contentURL = registrationData.contentURL {
                        DataCache.shared.saveContentURL(contentURL)
                        completion(.webContent, contentURL)
                    } else {
                        DataCache.shared.wasRegistrationAttempted = true
                        Self.completeWithCachedURLOrNative(completion)
                    }

                case .failure:
                    Self.completeWithCachedURLOrNative(completion)
                }
            }
    }

    /// Если ссылка уже была сохранена ранее — всегда отдаём её (вебвью),
    /// даже при пустом/упавшем ответе. На нативный экран уходим только
    /// когда ссылки не было никогда.
    private static func completeWithCachedURLOrNative(_ completion: (DisplayMode, String?) -> Void) {
        if let cached = DataCache.shared.contentURL, !cached.isEmpty {
            completion(.webContent, cached)
        } else {
            completion(.nativeInterface, nil)
        }
    }

    public func verifyURLAvailability(urlString: String, completion: @escaping (Bool) -> Void) {
        guard let url = URL(string: urlString) else {
            completion(false)
            return
        }

        session.request(url, method: .head)
            .response { response in
                if let httpResponse = response.response {
                    let statusCode = httpResponse.statusCode
                    let isAvailable = statusCode != 404 && statusCode < 500
                    completion(isAvailable)
                } else {
                    completion(false)
                }
            }
    }
}
