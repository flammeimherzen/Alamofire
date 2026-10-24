import Foundation
#if canImport(UIKit)
import UIKit
#endif

public enum AppConfiguration {
    public static var serverBaseURL: String = ""
    private static var configuredEndpoint: String?

    public static func configure(host: String, path: String = "/api/v1/users/register") {
        let cleanHost = host.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanPath = path.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanHost.isEmpty else {
            configuredEndpoint = nil
            return
        }
        if cleanPath.isEmpty {
            configuredEndpoint = cleanHost
        } else if cleanHost.hasSuffix("/") && cleanPath.hasPrefix("/") {
            configuredEndpoint = String(cleanHost.dropLast()) + cleanPath
        } else if !cleanHost.hasSuffix("/") && !cleanPath.hasPrefix("/") {
            configuredEndpoint = cleanHost + "/" + cleanPath
        } else {
            configuredEndpoint = cleanHost + cleanPath
        }
    }

    public static var registrationEndpoint: String {
        if let configuredEndpoint, !configuredEndpoint.isEmpty {
            return configuredEndpoint
        }
        guard !serverBaseURL.isEmpty else { return "" }
        let base = serverBaseURL.hasSuffix("/") ? String(serverBaseURL.dropLast()) : serverBaseURL
        return "\(base)/api/v1/users/register"
    }

    public static let networkTimeout: TimeInterval = 10.0
    public static let launchScreenDelay: TimeInterval = 2.0

    static var defaultUserAgent: String {
        #if canImport(UIKit)
        let version = UIDevice.current.systemVersion
        #else
        let version = "18.5"
        #endif
        let token = version.replacingOccurrences(of: ".", with: "_")
        return "Mozilla/5.0 (iPhone; CPU iPhone OS \(token) like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/\(version) Mobile/15E148 Safari/604.1"
    }
}
