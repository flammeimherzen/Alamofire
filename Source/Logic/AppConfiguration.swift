import Foundation

public enum AppConfiguration {
    public static var serverBaseURL: String = "https://domain.com"
    
    public static var registrationEndpoint: String {
        return "\(serverBaseURL)/api/v1/users/register"
    }
    
    public static let networkTimeout: TimeInterval = 30.0
    public static let launchScreenDelay: TimeInterval = 2.0
}
