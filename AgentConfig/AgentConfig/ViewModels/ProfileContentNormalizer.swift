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

    // MARK: - 关键字段提取（用于外部改动判定，只比对关键配置字段）

    /// 从 TOML 文本中提取指定 key（支持形如 `base_url` 或 `[model_providers.OpenAI]` 段内的 `base_url`）的值。
    /// 目前仅支持扁平 key 与单层表（table）段内的 key，足够覆盖 Codex config.toml 的 `base_url`。
    nonisolated static func tomlKey(_ value: String, _ key: String) -> String? {
        let lines = value.components(separatedBy: "\n")
        var currentTable: String?
        var bestMatch: String?

        for rawLine in lines {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.isEmpty || line.hasPrefix("#") { continue }

            if line.hasPrefix("[") && line.hasSuffix("]") {
                currentTable = String(line.dropFirst().dropLast())
                    .trimmingCharacters(in: .whitespaces)
                continue
            }

            guard let eqIndex = line.firstIndex(of: "=") else { continue }
            let rawName = line[..<eqIndex].trimmingCharacters(in: .whitespaces)
            let rawVal = line[line.index(after: eqIndex)...].trimmingCharacters(in: .whitespaces)

            let fullKey = currentTable.map { "\($0).\(rawName)" } ?? rawName
            if rawName == key || fullKey == key {
                bestMatch = rawVal
                    .trimmingCharacters(in: CharacterSet(charactersIn: "\""))
            }
        }
        return bestMatch
    }

    /// 从 shell 文本（如 .zshrc 托管块）中提取指定环境变量赋值（如 `export OPENAI_API_KEY="xxx"`）。
    nonisolated static func shellEnv(_ value: String, _ name: String) -> String? {
        let lines = value.components(separatedBy: "\n")
        for rawLine in lines {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.isEmpty || line.hasPrefix("#") { continue }

            let assignment: String
            if line.hasPrefix("export ") {
                assignment = String(line.dropFirst("export ".count))
            } else {
                assignment = line
            }

            guard let eqIndex = assignment.firstIndex(of: "=") else { continue }
            let varName = assignment[..<eqIndex].trimmingCharacters(in: .whitespaces)
            guard varName == name else { continue }

            let rawVal = assignment[assignment.index(after: eqIndex)...].trimmingCharacters(in: .whitespaces)
            return rawVal.trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
        }
        return nil
    }

    /// 从 JSON 文本中提取指定 key 的字符串值（顶层或嵌套，返回首个匹配）。
    nonisolated static func jsonKey(_ value: String, _ key: String) -> String? {
        guard let object = object(from: value) else { return nil }
        return findKey(object, key)
    }

    private nonisolated static func findKey(_ object: Any?, _ key: String) -> String? {
        guard let dict = object as? [String: Any] else { return nil }
        if let value = dict[key] {
            if let string = value as? String { return string }
            if let number = value as? NSNumber { return number.stringValue }
            if let bool = value as? Bool { return String(bool) }
        }
        for (_, subValue) in dict {
            if let found = findKey(subValue, key) { return found }
        }
        return nil
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
