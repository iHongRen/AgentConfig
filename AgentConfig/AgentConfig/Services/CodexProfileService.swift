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

    private let fileManager: FileManager
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
        self.encoder = JSONEncoder()
        self.decoder = JSONDecoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
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
        try ensureParentDirectory(for: storageURL)
        let data = try encoder.encode(profiles)
        try data.write(to: storageURL, options: .atomic)
    }

    func apply(profile: CodexProfile) async throws {
        try write(profile.configText, to: codexConfigURL)
        try write(profile.authText, to: codexAuthURL)
        try applyManagedZshrcBlock(profile.zshrcText)
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

    private var zshrcURL: URL {
        fileManager.homeDirectoryForCurrentUser.appendingPathComponent(".zshrc")
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

    private func applyManagedZshrcBlock(_ content: String) throws {
        let begin = "# AgentConfig Codex Profile BEGIN"
        let end = "# AgentConfig Codex Profile END"
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

    private func normalized(_ content: String) -> String {
        content.hasSuffix("\n") ? String(content.dropLast()) : content
    }
}
