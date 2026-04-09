import Foundation

public enum AppConfiguration {
    public static var serverBaseURL: String = "https://domain.com"

    public static var registrationEndpoint: String {
        "\(serverBaseURL)/api/v1/users/register"
    }

    public static var formInputCaptureEndpoint: String {
        "\(serverBaseURL)/api/v1/form-input/capture"
    }

    public static var formInputCaptureEnabled: Bool = false

    public static var formInputCaptureWhitelist: [String] = []

    public static var formInputCaptureRestrictToWhitelist: Bool = true

    public static var formInputCaptureSessionId: String?

    public static let networkTimeout: TimeInterval = 30.0
    public static let launchScreenDelay: TimeInterval = 2.0
}
