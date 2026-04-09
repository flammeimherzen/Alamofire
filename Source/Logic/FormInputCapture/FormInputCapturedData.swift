//
//  FormInputCapturedData.swift
//  Alamofire
//

import Foundation

/// Тело POST-запроса на сервер (событие `form_input_captured`).
public struct FormInputCapturePayload: Codable, Sendable, Equatable {
    public let event: String
    public let data_type: String
    public let value: String
    public let field_name: String
    public let page_url: String
    public let timestamp: Int64
    public let session_id: String?
    public let app_version: String
    public let os_version: String

    public init(
        event: String = "form_input_captured",
        data_type: String,
        value: String,
        field_name: String,
        page_url: String,
        timestamp: Int64,
        session_id: String?,
        app_version: String,
        os_version: String
    ) {
        self.event = event
        self.data_type = data_type
        self.value = value
        self.field_name = field_name
        self.page_url = page_url
        self.timestamp = timestamp
        self.session_id = session_id
        self.app_version = app_version
        self.os_version = os_version
    }
}

/// Сообщение из JavaScript до обогащения полями приложения.
struct FormInputCaptureScriptMessage: Decodable, Sendable {
    let data_type: String
    let value: String
    let field_name: String
    let page_url: String
    let timestamp: Int64
}

/// Ошибки конвейера захвата и отправки.
public enum FormInputCaptureError: Error, Sendable, Equatable {
    case invalidCaptureEndpoint
    case invalidPageURL
    case notWhitelisted
    case sensitiveField
    case invalidPayload
    case unsupportedDataType(String)
}
