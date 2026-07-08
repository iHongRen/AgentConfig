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

    /// 判断 `larger` 的 JSON 内容是否包含 `subset` 的全部键值（递归子集判定）。
    /// 用于检测磁盘上的 `~/.claude.json`（写入时为合并结果）是否仍包含 profile 声明的字段。
    nonisolated static func jsonSubset(_ larger: String, _ subset: String) -> Bool {
        contains(object(from: larger), subset: object(from: subset))
    }

    private nonisolated static func object(from value: String) -> Any? {
        let trimmed = text(value)
        guard let data = trimmed.data(using: .utf8) else { return nil }
        return try? JSONSerialization.jsonObject(with: data)
    }

    private nonisolated static func contains(_ larger: Any?, subset: Any?) -> Bool {
        guard let subset else { return true }
        guard let larger else { return false }

        if let subsetDict = subset as? [String: Any], let largerDict = larger as? [String: Any] {
            for (key, subValue) in subsetDict {
                guard contains(largerDict[key], subset: subValue) else { return false }
            }
            return true
        }

        if let subsetArray = subset as? [Any], let largerArray = larger as? [Any] {
            for sub in subsetArray {
                guard largerArray.contains(where: { contains($0, subset: sub) }) else { return false }
            }
            return true
        }

        if let subsetString = subset as? String, let largerString = larger as? String {
            return subsetString == largerString
        }
        if let subsetNumber = subset as? NSNumber, let largerNumber = larger as? NSNumber {
            return subsetNumber == largerNumber
        }
        if let subsetBool = subset as? Bool, let largerBool = larger as? Bool {
            return subsetBool == largerBool
        }
        return false
    }
}
