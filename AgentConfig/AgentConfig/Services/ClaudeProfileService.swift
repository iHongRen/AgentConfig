//
//  ClaudeProfileService.swift
//  AgentConfig
//

import Foundation

protocol ClaudeProfileServiceProtocol {
    func loadProfiles() async throws -> [ClaudeProfile]
    func saveProfiles(_ profiles: [ClaudeProfile]) async throws
    func apply(profile: ClaudeProfile) async throws
    func targetFileURLs() -> [URL]
    func readDiskContents() async throws -> ProfileDiskContents
}

final class ClaudeProfileService: ClaudeProfileServiceProtocol {

    private let fileService: ProfileFileService

    init(fileManager: FileManager = .default) {
        self.fileService = ProfileFileService(fileManager: fileManager)
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
        try fileService.write(encode(profiles), to: storageURL)
    }

    func apply(profile: ClaudeProfile) async throws {
        let mergedClaudeState = try mergedClaudeState(with: profile.claudeJSONText)
        let zshrcTarget = fileService.computedZshrcWithBlock(profile.zshrcText, blockID: "Claude Profile")
        try fileService.performWrites([
            (claudeSettingsURL, profile.settingsText),
            (claudeStateURL, mergedClaudeState),
            (fileService.zshrcURL, zshrcTarget)
        ])
    }

    private func defaultProfile() -> ClaudeProfile {
        let settingsText = fileService.readIfExists(at: claudeSettingsURL) ?? "{}"
        let claudeJSONText = ClaudeProfile.defaultClaudeJSONText
        let zshrcText = fileService.extractManagedZshrcBlock(blockID: "Claude Profile") ?? ClaudeProfile.defaultZshrcText
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

    private var fileManager: FileManager { fileService.fileManager }

    func targetFileURLs() -> [URL] {
        [claudeSettingsURL, claudeStateURL, fileService.zshrcURL]
    }

    func readDiskContents() async throws -> ProfileDiskContents {
        ProfileDiskContents(
            configText: fileService.readIfExists(at: claudeSettingsURL),
            authText: fileService.readIfExists(at: claudeStateURL),
            zshrcText: fileService.extractManagedZshrcBlock(blockID: "Claude Profile")
        )
    }

    private let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }()

    private let decoder: JSONDecoder = JSONDecoder()

    private func encode(_ profiles: [ClaudeProfile]) throws -> String {
        let data = try encoder.encode(profiles)
        guard let text = String(data: data, encoding: .utf8) else {
            throw CocoaError(.fileWriteUnknown)
        }
        return text
    }

    private func mergedClaudeState(with profileText: String) throws -> String {
        let currentStateText = fileService.readIfExists(at: claudeStateURL) ?? ClaudeProfile.defaultClaudeJSONText
        let currentObject = try parseJSONObject(from: currentStateText)
        let profileObject = try parseJSONObject(from: profileText)
        let mergedObject = deepMerge(currentObject, with: profileObject)
        return try serializeJSONObject(mergedObject)
    }

    private func parseJSONObject(from text: String) throws -> [String: Any] {
        let normalizedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
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
}
