//
//  CodexProfileService.swift
//  AgentConfig
//

import Foundation

protocol CodexProfileServiceProtocol {
    func loadProfiles() async throws -> [CodexProfile]
    func saveProfiles(_ profiles: [CodexProfile]) async throws
    func apply(profile: CodexProfile) async throws
}

final class CodexProfileService: CodexProfileServiceProtocol {

    private let fileService: ProfileFileService

    init(fileManager: FileManager = .default) {
        self.fileService = ProfileFileService(fileManager: fileManager)
    }

    func loadProfiles() async throws -> [CodexProfile] {
        guard fileManager.fileExists(atPath: storageURL.path) else {
            return CodexProfile.defaultProfiles
        }

        let data = try Data(contentsOf: storageURL)
        let profiles = try decoder.decode([CodexProfile].self, from: data)
        return profiles.isEmpty ? CodexProfile.defaultProfiles : profiles
    }

    func saveProfiles(_ profiles: [CodexProfile]) async throws {
        try fileService.write(encode(profiles), to: storageURL)
    }

    func apply(profile: CodexProfile) async throws {
        let zshrcTarget = fileService.computedZshrcWithBlock(profile.zshrcText, blockID: "Codex Profile")
        try fileService.performWrites([
            (codexConfigURL, profile.configText),
            (codexAuthURL, profile.authText),
            (fileService.zshrcURL, zshrcTarget)
        ])
    }

    private var storageURL: URL {
        let base = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? fileManager.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support")
        return base
            .appendingPathComponent("AgentConfig", isDirectory: true)
            .appendingPathComponent("CodexProfiles.json")
    }

    private var codexConfigURL: URL {
        fileManager.homeDirectoryForCurrentUser
            .appendingPathComponent(".codex", isDirectory: true)
            .appendingPathComponent("config.toml")
    }

    private var codexAuthURL: URL {
        fileManager.homeDirectoryForCurrentUser
            .appendingPathComponent(".codex", isDirectory: true)
            .appendingPathComponent("auth.json")
    }

    private var fileManager: FileManager { fileService.fileManager }

    private let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }()

    private let decoder: JSONDecoder = JSONDecoder()

    private func encode(_ profiles: [CodexProfile]) throws -> String {
        let data = try encoder.encode(profiles)
        guard let text = String(data: data, encoding: .utf8) else {
            throw CocoaError(.fileWriteUnknown)
        }
        return text
    }
}
