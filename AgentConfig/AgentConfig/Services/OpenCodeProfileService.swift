//
//  OpenCodeProfileService.swift
//  AgentConfig
//

import Foundation

protocol OpenCodeProfileServiceProtocol {
    func loadProfiles() async throws -> [OpenCodeProfile]
    func saveProfiles(_ profiles: [OpenCodeProfile]) async throws
    func apply(profile: OpenCodeProfile) async throws
    func targetFileURLs() -> [URL]
    func readDiskContents() async throws -> ProfileDiskContents
}

final class OpenCodeProfileService: OpenCodeProfileServiceProtocol {

    private let fileService: ProfileFileService

    init(fileManager: FileManager = .default) {
        self.fileService = ProfileFileService(fileManager: fileManager)
    }

    func loadProfiles() async throws -> [OpenCodeProfile] {
        guard fileManager.fileExists(atPath: storageURL.path) else {
            return OpenCodeProfile.defaultProfiles
        }

        let data = try Data(contentsOf: storageURL)
        let profiles = try decoder.decode([OpenCodeProfile].self, from: data)
        return profiles.isEmpty ? OpenCodeProfile.defaultProfiles : profiles
    }

    func saveProfiles(_ profiles: [OpenCodeProfile]) async throws {
        try fileService.write(encode(profiles), to: storageURL)
    }

    func apply(profile: OpenCodeProfile) async throws {
        let zshrcTarget = fileService.computedZshrcWithBlock(profile.zshrcText, blockID: "OpenCode Profile")
        try fileService.performWrites([
            (openCodeConfigURL, profile.configText),
            (openCodeAuthURL, profile.authText),
            (fileService.zshrcURL, zshrcTarget)
        ])
    }

    private var storageURL: URL {
        let base = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? fileManager.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support")
        return base
            .appendingPathComponent("AgentConfig", isDirectory: true)
            .appendingPathComponent("OpenCodeProfiles.json")
    }

    private var openCodeConfigURL: URL {
        fileManager.homeDirectoryForCurrentUser
            .appendingPathComponent(".config", isDirectory: true)
            .appendingPathComponent("opencode", isDirectory: true)
            .appendingPathComponent("opencode.json")
    }

    private var openCodeAuthURL: URL {
        fileManager.homeDirectoryForCurrentUser
            .appendingPathComponent(".local", isDirectory: true)
            .appendingPathComponent("share", isDirectory: true)
            .appendingPathComponent("opencode", isDirectory: true)
            .appendingPathComponent("auth.json")
    }

    private var fileManager: FileManager { fileService.fileManager }

    func targetFileURLs() -> [URL] {
        [openCodeConfigURL, openCodeAuthURL, fileService.zshrcURL]
    }

    func readDiskContents() async throws -> ProfileDiskContents {
        ProfileDiskContents(
            configText: fileService.readIfExists(at: openCodeConfigURL),
            authText: fileService.readIfExists(at: openCodeAuthURL),
            zshrcText: fileService.extractManagedZshrcBlock(blockID: "OpenCode Profile")
        )
    }

    private let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }()

    private let decoder: JSONDecoder = JSONDecoder()

    private func encode(_ profiles: [OpenCodeProfile]) throws -> String {
        let data = try encoder.encode(profiles)
        guard let text = String(data: data, encoding: .utf8) else {
            throw CocoaError(.fileWriteUnknown)
        }
        return text
    }
}
