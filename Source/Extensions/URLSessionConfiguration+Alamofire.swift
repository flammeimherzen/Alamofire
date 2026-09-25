
import Foundation

extension URLSessionConfiguration: AlamofireExtended {}
extension AlamofireExtension where ExtendedType: URLSessionConfiguration {
    public static var `default`: URLSessionConfiguration {
        let configuration = URLSessionConfiguration.default
        configuration.headers = .default

        return configuration
    }

    public static var ephemeral: URLSessionConfiguration {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.headers = .default

        return configuration
    }
}
