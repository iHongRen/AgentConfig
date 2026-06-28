//
//  ClaudeProfileViewModel.swift
//  AgentConfig
//

import Combine
import Foundation

final class ClaudeProfileViewModel: ObservableObject {

    private static let profileNameMaxLength = 10

    @Published var profiles: [ClaudeProfile] = []
    @Published var selectedProfileID: UUID?
    @Published var lastErrorMessage: String?
    @Published var lastAppliedProfileName: String?
    @Published private(set) var didFinishInitialLoad: Bool = false

    private let service: ClaudeProfileServiceProtocol
    private var persistTask: Task<Void, Never>?
    private var hasRestoredInitialSelection = false

    init(service: ClaudeProfileServiceProtocol? = nil) {
        self.service = service ?? ClaudeProfileService()
        Task { await loadProfiles() }
    }

    var selectedProfile: ClaudeProfile? {
        guard let selectedProfileID else { return nil }
        return profiles.first { $0.id == selectedProfileID }
    }

    func loadProfiles() async {
        do {
            let loadedProfiles = try await service.loadProfiles()
            profiles = loadedProfiles.map { profile in
                var updatedProfile = profile
                updatedProfile.isDirty = isProfileDirty(updatedProfile)
                return updatedProfile
            }
            selectedProfileID = selectedProfileID ?? loadedProfiles.first(where: \.isActive)?.id ?? loadedProfiles.first?.id
        } catch {
            var fallbackProfile = makeFallbackProfile()
            fallbackProfile.isDirty = isProfileDirty(fallbackProfile)
            profiles = [fallbackProfile]
            selectedProfileID = fallbackProfile.id
            lastErrorMessage = error.localizedDescription
        }
        didFinishInitialLoad = true
    }

    func selectProfile(_ profile: ClaudeProfile) {
        guard selectedProfileID != profile.id else { return }
        selectedProfileID = profile.id
    }

    func restoreInitialSelectionIfNeeded(appViewModel: AppViewModel) -> Bool {
        guard didFinishInitialLoad, !hasRestoredInitialSelection else { return false }
        hasRestoredInitialSelection = true

        guard case .claudeProfile(let id) = appViewModel.lastVisitedPage else { return false }
        guard profiles.contains(where: { $0.id == id }) else {
            appViewModel.persistLastVisitedPage(nil)
            return false
        }

        selectedProfileID = id
        return true
    }

    func clearSelection() {
        guard selectedProfileID != nil else { return }
        selectedProfileID = nil
    }

    func defaultSelectedProfileID() -> UUID? {
        profiles.first(where: \.isActive)?.id ?? profiles.first?.id
    }

    func updateSelected(name: String? = nil, settingsText: String? = nil, claudeJSONText: String? = nil) {
        guard let index = selectedIndex else { return }
        var didChange = false

        if let name {
            let truncatedName = String(name.prefix(Self.profileNameMaxLength))
            if profiles[index].name != truncatedName {
                profiles[index].name = truncatedName
                didChange = true
            }
        }
        if let settingsText, profiles[index].settingsText != settingsText {
            profiles[index].settingsText = settingsText
            didChange = true
        }
        if let claudeJSONText, profiles[index].claudeJSONText != claudeJSONText {
            profiles[index].claudeJSONText = claudeJSONText
            didChange = true
        }

        guard didChange else { return }
        profiles[index].isDirty = isProfileDirty(profiles[index])
        schedulePersistProfiles()
    }

    func updateSelectedEditorHeight(
        settingsEditorHeight: Double? = nil,
        claudeJSONEditorHeight: Double? = nil
    ) {
        guard let index = selectedIndex else { return }
        var didChange = false

        if let settingsEditorHeight, profiles[index].settingsEditorHeight != settingsEditorHeight {
            profiles[index].settingsEditorHeight = settingsEditorHeight
            didChange = true
        }
        if let claudeJSONEditorHeight, profiles[index].claudeJSONEditorHeight != claudeJSONEditorHeight {
            profiles[index].claudeJSONEditorHeight = claudeJSONEditorHeight
            didChange = true
        }

        guard didChange else { return }
        schedulePersistProfiles()
    }

    func addProfile() {
        guard let source = selectedProfile ?? profiles.first else { return }
        let profile = ClaudeProfile(
            name: "新配置 \(profiles.count + 1)",
            settingsText: source.settingsText,
            claudeJSONText: source.claudeJSONText,
            isDirty: true
        )
        profiles.append(profile)
        selectedProfileID = profile.id
        Task { await persistProfiles() }
    }

    func deleteProfile(id: UUID) -> Bool {
        guard profiles.count > 1 else {
            lastErrorMessage = "至少需要保留一个 Claude Profile。"
            return false
        }
        guard let index = profiles.firstIndex(where: { $0.id == id }) else {
            lastErrorMessage = "未找到要删除的 Claude Profile。"
            return false
        }

        let deletedWasSelected = selectedProfileID == id
        profiles.remove(at: index)

        if deletedWasSelected {
            let nextIndex = min(index, profiles.count - 1)
            selectedProfileID = profiles.indices.contains(nextIndex) ? profiles[nextIndex].id : profiles.first?.id
        }

        lastErrorMessage = nil
        Task { await persistProfiles() }
        return true
    }

    func applySelected() async -> Bool {
        guard let selectedProfile, let selectedIndex else { return false }

        do {
            try await service.apply(profile: selectedProfile)
            for index in profiles.indices {
                profiles[index].isActive = profiles[index].id == selectedProfile.id
            }
            profiles[selectedIndex].appliedSettingsText = selectedProfile.settingsText
            profiles[selectedIndex].appliedClaudeJSONText = selectedProfile.claudeJSONText
            profiles[selectedIndex].isDirty = false
            lastAppliedProfileName = profiles[selectedIndex].name
            lastErrorMessage = nil
            await persistProfiles()
            return true
        } catch {
            lastErrorMessage = error.localizedDescription
            return false
        }
    }

    private var selectedIndex: Array<ClaudeProfile>.Index? {
        guard let selectedProfileID else { return nil }
        return profiles.firstIndex { $0.id == selectedProfileID }
    }

    private func isProfileDirty(_ profile: ClaudeProfile) -> Bool {
        normalizedJSON(profile.settingsText) != normalizedJSON(profile.appliedSettingsText)
            || normalizedJSON(profile.claudeJSONText) != normalizedJSON(profile.appliedClaudeJSONText)
    }

    private func normalizedText(_ text: String) -> String {
        text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func normalizedJSON(_ text: String) -> String {
        let trimmedText = normalizedText(text)
        guard let data = trimmedText.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data),
              JSONSerialization.isValidJSONObject(object),
              let stableData = try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]),
              let stableText = String(data: stableData, encoding: .utf8) else {
            return trimmedText
        }

        return stableText
    }

    private func persistProfiles() async {
        do {
            try await service.saveProfiles(profiles)
        } catch {
            lastErrorMessage = error.localizedDescription
        }
    }

    private func makeFallbackProfile() -> ClaudeProfile {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let settingsURL = home.appendingPathComponent(".claude", isDirectory: true).appendingPathComponent("settings.json")
        let claudeJSONURL = home.appendingPathComponent(".claude.json")

        let settingsText = (try? String(contentsOf: settingsURL, encoding: .utf8)) ?? "{}"
        let claudeJSONText = (try? String(contentsOf: claudeJSONURL, encoding: .utf8)) ?? "{}"

        return ClaudeProfile(
            name: "新配置",
            settingsText: settingsText,
            claudeJSONText: claudeJSONText,
            appliedSettingsText: settingsText,
            appliedClaudeJSONText: claudeJSONText,
            isActive: true
        )
    }

    private func schedulePersistProfiles() {
        persistTask?.cancel()
        persistTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 350_000_000)
            guard !Task.isCancelled else { return }
            await self?.persistProfiles()
        }
    }
}
