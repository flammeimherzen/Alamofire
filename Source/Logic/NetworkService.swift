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
            print("❌ [NetworkService] Invalid registration endpoint URL: \(AppConfiguration.registrationEndpoint)")
            completion(.nativeInterface, nil)
            return
        }
        
        print("📤 [NetworkService] Starting registration request")
        print("   URL: \(url.absoluteString)")
        print("   Bundle: \(bundle)")
        print("   PushToken: \(pushToken.isEmpty ? "(empty)" : "***")")
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        
        #if canImport(UIKit)
        request.setValue("Mozilla/5.0 (iPhone; CPU iPhone OS 16_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/16.0 Mobile/15E148 Safari/604.1", forHTTPHeaderField: "User-Agent")
        #endif
        
        do {
            request.httpBody = try JSONEncoder().encode(requestBody)
            if let bodyData = request.httpBody, let bodyString = String(data: bodyData, encoding: .utf8) {
                print("   Request Body: \(bodyString)")
            }
        } catch {
            print("❌ [NetworkService] Failed to encode request: \(error)")
            completion(.nativeInterface, nil)
            return
        }
        
        print("   Headers: \(request.allHTTPHeaderFields ?? [:])")
        
        session.request(request)
        .validate(statusCode: 200..<300)
        .responseData { dataResponse in
            if let httpResponse = dataResponse.response {
                print("📥 [NetworkService] Response received")
                print("   Status Code: \(httpResponse.statusCode)")
                print("   Headers: \(httpResponse.allHeaderFields)")
            }
            
            if let data = dataResponse.data, let responseString = String(data: data, encoding: .utf8) {
                print("   Response Body: \(responseString)")
            }
            
            if let error = dataResponse.error {
                print("❌ [NetworkService] Request error: \(error.localizedDescription)")
                if let afError = error.asAFError {
                    print("   AFError: \(afError)")
                }
            }
        }
        .responseDecodable(of: RegistrationResponse.self) { response in
            switch response.result {
            case .success(let registrationData):
                print("✅ [NetworkService] Registration response received")
                print("   Success: \(registrationData.success)")
                print("   AppData: \(registrationData.app_data ?? "nil")")
                
                if registrationData.success {
                    if let contentURL = registrationData.contentURL {
                        print("✅ [NetworkService] Registration successful with URL: \(contentURL)")
                        print("   Saving URL and marking registration as completed")
                        DataCache.shared.saveContentURL(contentURL)
                        completion(.webContent, contentURL)
                    } else {
                        print("⚠️ [NetworkService] Registration success=true but no URL provided")
                        print("   Marking registration as completed (no URL)")
                        DataCache.shared.saveContentURL(nil)
                        completion(.nativeInterface, nil)
                    }
                } else {
                    print("❌ [NetworkService] Registration failed (success=false)")
                    print("   Marking registration as completed (will not retry)")
                    DataCache.shared.saveContentURL(nil)
                    completion(.nativeInterface, nil)
                }
                
            case .failure(let error):
                print("❌ [NetworkService] Registration request failed: \(error.localizedDescription)")
                if let afError = error.asAFError {
                    print("   AFError details: \(afError)")
                }
                print("   Not saving registration attempt (network error, will retry on next launch)")
                completion(.nativeInterface, nil)
            }
        }
    }
    
    public func verifyURLAvailability(urlString: String, completion: @escaping (Bool) -> Void) {
        guard let url = URL(string: urlString) else {
            print("❌ [NetworkService] Invalid URL for verification: \(urlString)")
            completion(false)
            return
        }
        
        print("🔍 [NetworkService] Verifying URL availability: \(urlString)")
        
        session.request(url, method: .head)
            .response { response in
                if let httpResponse = response.response {
                    let statusCode = httpResponse.statusCode
                    let isAvailable = statusCode != 404 && statusCode < 500
                    print("   Status Code: \(statusCode)")
                    print("   Available: \(isAvailable)")
                    completion(isAvailable)
                } else {
                    print("⚠️ [NetworkService] No response received for URL verification")
                    completion(false)
                }
                
                if let error = response.error {
                    print("❌ [NetworkService] URL verification error: \(error.localizedDescription)")
                }
            }
    }
}
