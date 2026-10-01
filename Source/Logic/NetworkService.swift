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
    let advertising_id: String
    let appsflyer_id: String
}

public final class NetworkService {
    public static let shared = NetworkService()

    private let session: Session
    private let registrationGate = RegistrationGate()

    private init() {
        let configuration = URLSessionConfiguration.default
        configuration.httpCookieStorage = HTTPCookieStorage.shared
        configuration.httpShouldSetCookies = true
        configuration.httpCookieAcceptPolicy = .always
        configuration.timeoutIntervalForRequest = AppConfiguration.networkTimeout
        configuration.timeoutIntervalForResource = AppConfiguration.networkTimeout

        self.session = Session(configuration: configuration)
    }

    private func getBundleIdentifier() -> String {
        Bundle.main.bundleIdentifier ?? ""
    }

    public func performRegistration(
        pushToken: String = "",
        advertisingId: String = "",
        appsflyerId: String = "",
        completion: @escaping (DisplayMode, String?) -> Void
    ) {
        let gate = registrationGate
        guard gate.begin(completion) else { return }
        SessionVault.restore()
        if let cached = DataCache.shared.contentURL, !cached.isEmpty {
            gate.finish(.webContent, cached)
            return
        }

        let bundle = getBundleIdentifier()
        let requestBody = RegistrationRequest(
            bundle: bundle,
            push_token: pushToken,
            advertising_id: advertisingId,
            appsflyer_id: appsflyerId
        )

        guard let url = URL(string: AppConfiguration.registrationEndpoint) else {
            gate.finish(.nativeInterface, nil)
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
            gate.finish(.nativeInterface, nil)
            return
        }

        session.request(request)
            .validate(statusCode: 200..<300)
            .responseDecodable(of: RegistrationResponse.self) { response in
                SessionVault.store(response: response.response)
                SessionVault.persist()
                switch response.result {
                case .success(let registrationData):
                    if let contentURL = registrationData.contentURL {
                        DataCache.shared.saveContentURL(contentURL)
                        gate.finish(.webContent, contentURL)
                    } else {
                        DataCache.shared.wasRegistrationAttempted = true
                        let cached = Self.cachedResult()
                        gate.finish(cached.0, cached.1)
                    }

                case .failure:
                    let cached = Self.cachedResult()
                    gate.finish(cached.0, cached.1)
                }
            }
    }

    private static func cachedResult() -> (DisplayMode, String?) {
        if let cached = DataCache.shared.contentURL, !cached.isEmpty {
            return (.webContent, cached)
        }
        return (.nativeInterface, nil)
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
