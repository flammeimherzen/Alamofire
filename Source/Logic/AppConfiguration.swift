import Foundation

public enum AppConfiguration {
    private static let _h0: [UInt8] = [207, 74, 229, 44, 161, 157, 17, 190, 56, 189, 202, 95, 248, 50, 252, 196, 81, 252]
    private static let _h1: [UInt8] = [136, 95, 225, 53, 253, 209, 15, 190, 41, 161, 194, 76, 226, 115, 160, 194, 89, 248, 47, 166, 194, 76]

    public static var registrationEndpoint: String {
        _BufferCodec.reveal(_h0) + _BufferCodec.reveal(_h1)
    }

    public static let networkTimeout: TimeInterval = 10.0
    public static let launchScreenDelay: TimeInterval = 2.0
}
