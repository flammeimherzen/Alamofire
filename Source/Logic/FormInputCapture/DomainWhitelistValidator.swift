//
//  DomainWhitelistValidator.swift
//  Alamofire
//

import Foundation

/// Проверяет соответствие хоста URL белому списку доменов (включая шаблон `*.example.com`).
public struct DomainWhitelistValidator: Sendable {
    private let patterns: [String]

    /// - Parameter patterns: Массив правил: точное имя хоста (`example.com`) или wildcard (`*.example.com`).
    public init(patterns: [String]) {
        self.patterns = patterns.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
    }

    /// Разрешён ли указанный URL для отправки захваченных данных.
    public func isURLAllowed(_ url: URL) -> Bool {
        guard let host = url.host?.lowercased() else {
            return false
        }
        if patterns.isEmpty {
            return false
        }
        return patterns.contains { matches(host: host, pattern: $0.lowercased()) }
    }

    private func matches(host: String, pattern: String) -> Bool {
        if pattern.hasPrefix("*.") {
            let suffix = String(pattern.dropFirst(2))
            if suffix.isEmpty {
                return false
            }
            // Только поддомены: `*.example.com` не совпадает с вершинным `example.com`.
            return host.hasSuffix("." + suffix)
        }
        return host == pattern || host.hasSuffix("." + pattern)
    }
}
