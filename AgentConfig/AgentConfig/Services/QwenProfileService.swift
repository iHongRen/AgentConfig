//
//  QwenProfileService.swift
//  AgentConfig
//

import Foundation

protocol QwenProfileServiceProtocol {
    func loadProfiles() async throws -> [QwenProfile]
    func saveProfiles(_ profiles: [QwenProfile]) async throws
    func apply(profile: QwenProfile) async throws
    func targetFileURLs() -> [URL]
    func readDiskContents() async throws -> ProfileDiskContents
}

final class QwenProfileService: QwenProfileServiceProtocol {

    private let fileService: ProfileFileService

    init(fileManager: FileManager = .default) {
        self.fileService = ProfileFileService(fileManager: fileManager)
    }

    func loadProfiles() async throws -> [QwenProfile] {
        guard fileManager.fileExists(atPath: storageURL.path) else {
            return QwenProfile.defaultProfiles
        }

        let data = try Data(contentsOf: storageURL)
        let profiles = try decoder.decode([QwenProfile].self, from: data)
        return profiles.isEmpty ? QwenProfile.defaultProfiles : profiles
    }

    func saveProfiles(_ profiles: [QwenProfile]) async throws {
        try fileService.write(encode(profiles), to: storageURL)
    }

    func apply(profile: QwenProfile) async throws {
        let zshrcTarget = fileService.computedZshrcWithBlock(profile.zshrcText, blockID: "Qwen Profile")
        try fileService.performWrites([
            (qwenSettingsURL, profile.settingsText),
            (qwenEnvURL, profile.envText),
            (fileService.zshrcURL, zshrcTarget)
        ])
    }

    private var storageURL: URL {
        let base = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? fileManager.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support")
        return base
            .appendingPathComponent("AgentConfig", isDirectory: true)
            .appendingPathComponent("QwenProfiles.json")
    }

    private var qwenSettingsURL: URL {
        fileManager.homeDirectoryForCurrentUser
            .appendingPathComponent(".qwen", isDirectory: true)
            .appendingPathComponent("settings.json")
    }

    private var qwenEnvURL: URL {
        fileManager.homeDirectoryForCurrentUser
            .appendingPathComponent(".qwen", isDirectory: true)
            .appendingPathComponent("settings.json.env")
    }

    private var fileManager: FileManager { fileService.fileManager }

    func targetFileURLs() -> [URL] {
        [qwenSettingsURL, qwenEnvURL, fileService.zshrcURL]
    }

    func readDiskContents() async throws -> ProfileDiskContents {
        ProfileDiskContents(
            configText: fileService.readIfExists(at: qwenSettingsURL),
            authText: fileService.readIfExists(at: qwenEnvURL),
            zshrcText: fileService.extractManagedZshrcBlock(blockID: "Qwen Profile")
        )
    }

    private let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }()

    private let decoder: JSONDecoder = JSONDecoder()

    private func encode(_ profiles: [QwenProfile]) throws -> String {
        let data = try encoder.encode(profiles)
        guard let text = String(data: data, encoding: .utf8) else {
            throw CocoaError(.fileWriteUnknown)
        }
        return text
    }
}
