//
//  ClaudeProfileService.swift
//  AgentConfig
//

import Foundation

protocol ClaudeProfileServiceProtocol {
    func loadProfiles() async throws -> [ClaudeProfile]
    func saveProfiles(_ profiles: [ClaudeProfile]) async throws
    func apply(profile: ClaudeProfile) async throws
}

final class ClaudeProfileService: ClaudeProfileServiceProtocol {

    private let fileManager: FileManager
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
        self.encoder = JSONEncoder()
        self.decoder = JSONDecoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    }

    func loadProfiles() async throws -> [ClaudeProfile] {
        guard fileManager.fileExists(atPath: storageURL.path) else {
            return [defaultProfile()]
        }

        let data = try Data(contentsOf: storageURL)
        let profiles = try decoder.decode([ClaudeProfile].self, from: data)
        return profiles.isEmpty ? [defaultProfile()] : profiles
    }

    func saveProfiles(_ profiles: [ClaudeProfile]) async throws {
        try ensureParentDirectory(for: storageURL)
        let data = try encoder.encode(profiles)
        try data.write(to: storageURL, options: .atomic)
    }

    func apply(profile: ClaudeProfile) async throws {
        try write(profile.settingsText, to: claudeSettingsURL)
        let mergedClaudeState = try mergedClaudeState(with: profile.claudeJSONText)
        try write(mergedClaudeState, to: claudeStateURL)
        try applyManagedZshrcBlock(profile.zshrcText)
    }

    private func defaultProfile() -> ClaudeProfile {
        let settingsText = (try? readFileIfExists(at: claudeSettingsURL)) ?? "{}"
        let claudeJSONText = ClaudeProfile.defaultClaudeJSONText
        let zshrcText = defaultManagedZshrcBlockContent()
        return ClaudeProfile(
            name: L10n.tr("profile.newName", value: "New Profile"),
            settingsText: settingsText,
            claudeJSONText: claudeJSONText,
            zshrcText: zshrcText,
            appliedSettingsText: settingsText,
            appliedClaudeJSONText: claudeJSONText,
            appliedZshrcText: zshrcText,
            isActive: true
        )
    }

    private var storageURL: URL {
        let base = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? fileManager.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support")
        return base
            .appendingPathComponent("AgentConfig", isDirectory: true)
            .appendingPathComponent("ClaudeProfiles.json")
    }

    private var claudeSettingsURL: URL {
        fileManager.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude", isDirectory: true)
            .appendingPathComponent("settings.json")
    }

    private var claudeStateURL: URL {
        fileManager.homeDirectoryForCurrentUser.appendingPathComponent(".claude.json")
    }

    private var zshrcURL: URL {
        fileManager.homeDirectoryForCurrentUser.appendingPathComponent(".zshrc")
    }

    private func readFileIfExists(at url: URL) throws -> String {
        guard fileManager.fileExists(atPath: url.path) else {
            throw CocoaError(.fileNoSuchFile)
        }
        return try String(contentsOf: url, encoding: .utf8)
    }

    private func write(_ content: String, to url: URL) throws {
        try ensureParentDirectory(for: url)
        try normalized(content).write(to: url, atomically: true, encoding: .utf8)
    }

    private func ensureParentDirectory(for url: URL) throws {
        let parent = url.deletingLastPathComponent()
        if !fileManager.fileExists(atPath: parent.path) {
            try fileManager.createDirectory(at: parent, withIntermediateDirectories: true)
        }
    }

    private func normalized(_ content: String) -> String {
        content.hasSuffix("\n") ? String(content.dropLast()) : content
    }

    private func mergedClaudeState(with profileText: String) throws -> String {
        let currentStateText = (try? readFileIfExists(at: claudeStateURL)) ?? ClaudeProfile.defaultClaudeJSONText
        let currentObject = try parseJSONObject(from: currentStateText)
        let profileObject = try parseJSONObject(from: profileText)
        let mergedObject = deepMerge(currentObject, with: profileObject)
        return try serializeJSONObject(mergedObject)
    }

    private func parseJSONObject(from text: String) throws -> [String: Any] {
        let normalizedText = normalized(text).trimmingCharacters(in: .whitespacesAndNewlines)
        let fallbackText = ClaudeProfile.defaultClaudeJSONText
        let sourceText = normalizedText.isEmpty ? fallbackText : normalizedText

        guard let data = sourceText.data(using: .utf8) else {
            throw CocoaError(.fileReadCorruptFile)
        }
        let object = try JSONSerialization.jsonObject(with: data)
        guard let dictionary = object as? [String: Any] else {
            throw CocoaError(.coderReadCorrupt)
        }
        return dictionary
    }

    private func serializeJSONObject(_ object: [String: Any]) throws -> String {
        let data = try JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys])
        guard let text = String(data: data, encoding: .utf8) else {
            throw CocoaError(.fileWriteUnknown)
        }
        return text
    }

    private func deepMerge(_ current: [String: Any], with overrides: [String: Any]) -> [String: Any] {
        var merged = current

        for (key, overrideValue) in overrides {
            if let overrideObject = overrideValue as? [String: Any],
               let currentObject = merged[key] as? [String: Any] {
                merged[key] = deepMerge(currentObject, with: overrideObject)
            } else {
                merged[key] = overrideValue
            }
        }

        return merged
    }

    private func defaultManagedZshrcBlockContent() -> String {
        let current = (try? String(contentsOf: zshrcURL, encoding: .utf8)) ?? ""
        return extractManagedZshrcBlock(from: current) ?? ClaudeProfile.defaultZshrcText
    }

    private func applyManagedZshrcBlock(_ content: String) throws {
        let begin = "# AgentConfig Claude Profile BEGIN"
        let end = "# AgentConfig Claude Profile END"
        let managedBlock = [begin, normalized(content), end].joined(separator: "\n")
        let current = (try? String(contentsOf: zshrcURL, encoding: .utf8)) ?? ""

        let updated: String
        if let beginRange = current.range(of: begin),
           let endRange = current.range(of: end, range: beginRange.upperBound..<current.endIndex) {
            updated = String(current[..<beginRange.lowerBound])
                + managedBlock
                + String(current[endRange.upperBound...])
        } else if current.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            updated = managedBlock + "\n"
        } else {
            updated = normalized(current) + "\n\n" + managedBlock + "\n"
        }

        try write(updated, to: zshrcURL)
    }

    private func extractManagedZshrcBlock(from content: String) -> String? {
        let begin = "# AgentConfig Claude Profile BEGIN"
        let end = "# AgentConfig Claude Profile END"

        guard let beginRange = content.range(of: begin),
              let endRange = content.range(of: end, range: beginRange.upperBound..<content.endIndex) else {
            return nil
        }

        let body = content[beginRange.upperBound..<endRange.lowerBound]
        return body
            .trimmingCharacters(in: CharacterSet(charactersIn: "\n"))
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
    }
}
