import Foundation
import XCTest
@testable import Alamofire

private final class RegistrationProtocol: URLProtocol {
    static var requests = 0
    static var status = 200
    static var body = Data()
    static var error: Error?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        Self.requests += 1
        if let error = Self.error {
            client?.urlProtocol(self, didFailWithError: error)
            return
        }
        let response = HTTPURLResponse(url: request.url!, statusCode: Self.status,
                                       httpVersion: nil, headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Self.body)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

final class RegistrationTests: XCTestCase {
    private var previousURL: String?
    private var previousAttempted = false
    private var previousEndpoint = ""

    override func setUp() {
        super.setUp()
        previousURL = DataCache.shared.contentURL
        previousAttempted = DataCache.shared.wasRegistrationAttempted
        previousEndpoint = AppConfiguration.registrationEndpoint
        DataCache.shared.clearCache()
        AppConfiguration.configure(host: "https://registration.test")
        RegistrationProtocol.requests = 0
        RegistrationProtocol.status = 200
        RegistrationProtocol.error = nil
        RegistrationProtocol.body = Data(#"{"success":true,"app_data":null}"#.utf8)
    }

    override func tearDown() {
        DataCache.shared.contentURL = previousURL
        DataCache.shared.wasRegistrationAttempted = previousAttempted
        AppConfiguration.configure(host: previousEndpoint, path: "")
        super.tearDown()
    }

    // A new service resets the process-local gate while retaining installation defaults.
    private func launch(expectedMode: DisplayMode, expectedURL: String? = nil) {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [RegistrationProtocol.self]
        let service = NetworkService(session: Session(configuration: configuration))
        let completed = expectation(description: "Registration completed")
        service.performRegistration { mode, url in
            XCTAssertEqual(mode, expectedMode)
            XCTAssertEqual(url, expectedURL)
            completed.fulfill()
        }
        wait(for: [completed], timeout: 5)
        withExtendedLifetime(service) {}
    }

    func testResponseWithoutURLRemainsNativeAfterRegionChange() {
        launch(expectedMode: .nativeInterface)
        XCTAssertTrue(DataCache.shared.wasRegistrationAttempted)
        RegistrationProtocol.body = Data(#"{"success":true,"app_data":"https://content.test"}"#.utf8)
        launch(expectedMode: .nativeInterface)
        XCTAssertEqual(RegistrationProtocol.requests, 1)
        XCTAssertNil(DataCache.shared.contentURL)
    }

    func testNegativeResponseRemainsNative() {
        RegistrationProtocol.body = Data(#"{"success":false,"app_data":null}"#.utf8)
        launch(expectedMode: .nativeInterface)
        XCTAssertTrue(DataCache.shared.wasRegistrationAttempted)
        launch(expectedMode: .nativeInterface)
        XCTAssertEqual(RegistrationProtocol.requests, 1)
    }

    func testEmptyURLRemainsNative() {
        RegistrationProtocol.body = Data(#"{"success":true,"app_data":""}"#.utf8)
        launch(expectedMode: .nativeInterface)
        launch(expectedMode: .nativeInterface)
        XCTAssertTrue(DataCache.shared.wasRegistrationAttempted)
        XCTAssertEqual(RegistrationProtocol.requests, 1)
    }

    func testSavedURLIsReused() {
        RegistrationProtocol.body = Data(#"{"success":true,"app_data":"https://content.test"}"#.utf8)
        launch(expectedMode: .webContent, expectedURL: "https://content.test")
        launch(expectedMode: .webContent, expectedURL: "https://content.test")
        XCTAssertTrue(DataCache.shared.wasRegistrationAttempted)
        XCTAssertEqual(RegistrationProtocol.requests, 1)
    }

    private func assertRetryAfterFailure(file: StaticString = #filePath, line: UInt = #line) {
        launch(expectedMode: .nativeInterface)
        XCTAssertFalse(DataCache.shared.wasRegistrationAttempted, file: file, line: line)
        RegistrationProtocol.error = nil
        RegistrationProtocol.status = 200
        RegistrationProtocol.body = Data(#"{"success":true,"app_data":"https://content.test"}"#.utf8)
        launch(expectedMode: .webContent, expectedURL: "https://content.test")
        XCTAssertEqual(RegistrationProtocol.requests, 2, file: file, line: line)
    }

    func testNetworkErrorAllowsRetryOnNextLaunch() {
        RegistrationProtocol.error = URLError(.notConnectedToInternet)
        assertRetryAfterFailure()
    }

    func testHTTPErrorAllowsRetryOnNextLaunch() {
        RegistrationProtocol.status = 503
        assertRetryAfterFailure()
    }

    func testDecodingErrorAllowsRetryOnNextLaunch() {
        RegistrationProtocol.body = Data("invalid json".utf8)
        assertRetryAfterFailure()
    }
}
