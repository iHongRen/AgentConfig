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
        try write(profile.claudeJSONText, to: claudeStateURL)
    }

    private func defaultProfile() -> ClaudeProfile {
        let settingsText = (try? readFileIfExists(at: claudeSettingsURL)) ?? "{}"
        let claudeJSONText = (try? readFileIfExists(at: claudeStateURL)) ?? "{}"
        return ClaudeProfile(
            name: "新配置",
            settingsText: settingsText,
            claudeJSONText: claudeJSONText,
            appliedSettingsText: settingsText,
            appliedClaudeJSONText: claudeJSONText,
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
}
