//
//  FormInputCaptureService.swift
//  Alamofire
//

import Alamofire
import Foundation
#if canImport(UIKit)
import UIKit
#endif

@available(macOS 10.15, iOS 13, tvOS 13, watchOS 6, *)
public protocol FormInputCaptureSending: Sendable {
    func sendCapturedInput(_ payload: FormInputCapturePayload) async throws
}

@available(macOS 10.15, iOS 13, tvOS 13, watchOS 6, *)
public final class FormInputCaptureService: FormInputCaptureSending, @unchecked Sendable {
    public static let shared = FormInputCaptureService()

    private let session: Session

    public init(session: Session? = nil) {
        if let session {
            self.session = session
        } else {
            let configuration = URLSessionConfiguration.default
            configuration.timeoutIntervalForRequest = AppConfiguration.networkTimeout
            configuration.timeoutIntervalForResource = AppConfiguration.networkTimeout
            self.session = Session(configuration: configuration)
        }
    }

    public func sendCapturedInput(_ payload: FormInputCapturePayload) async throws {
        guard let url = URL(string: AppConfiguration.formInputCaptureEndpoint),
              url.scheme?.lowercased() == "https" else {
            throw FormInputCaptureError.invalidCaptureEndpoint
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        #if canImport(UIKit)
        request.setValue(
            "Mozilla/5.0 (iPhone; CPU iPhone OS 16_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/16.0 Mobile/15E148 Safari/604.1",
            forHTTPHeaderField: "User-Agent"
        )
        #endif
        request.httpBody = try JSONEncoder().encode(payload)

        _ = try await session.request(request)
            .validate(statusCode: 200..<300)
            .serializingData(emptyResponseCodes: [200, 204, 205])
            .value
    }
}
