//
//  ProfileContentNormalizer.swift
//  AgentConfig
//

import Foundation

enum ProfileContentNormalizer {
    nonisolated static func text(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    nonisolated static func json(_ value: String) -> String {
        let trimmedText = text(value)
        guard let data = trimmedText.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data),
              JSONSerialization.isValidJSONObject(object),
              let stableData = try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]),
              let stableText = String(data: stableData, encoding: .utf8) else {
            return trimmedText
        }

        return stableText
    }
}
