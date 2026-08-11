import Foundation

public enum AppConfiguration {
    private static var _hostFragment: [UInt8]?
    private static var _pathFragment: [UInt8]?

    /// Передать XOR-фрагменты из app-проекта. Вызвать в `didFinishLaunching` до сетевых запросов.
    /// Plaintext URL в коде не нужен — только `[UInt8]` из `encode-string.py`.
    public static func configure(host: [UInt8], path: [UInt8]) {
        _hostFragment = host
        _pathFragment = path
    }

    public static var registrationEndpoint: String {
        guard let host = _hostFragment, let path = _pathFragment else { return "" }
        return _BufferCodec.reveal(host) + _BufferCodec.reveal(path)
    }

    public static let networkTimeout: TimeInterval = 10.0
    public static let launchScreenDelay: TimeInterval = 2.0
}
