//
//  FormInputCaptureSecurity.swift
//  Alamofire
//

import Foundation

/// Дополнительная фильтрация на native-стороне (совпадает с эвристиками в JS).
enum FormInputCaptureSecurity {
    private static let sensitiveSubstrings: [String] = [
        "password", "passwd", "pwd", "secret", "token", "auth", "card", "cvv", "cvc", "ssn", "credit",
        "otp", "apikey", "api_key", "security", "pin"
    ]

    static func isSensitiveFieldLabel(_ raw: String) -> Bool {
        let folded = raw.lowercased()
        return sensitiveSubstrings.contains { folded.contains($0) }
    }
}
