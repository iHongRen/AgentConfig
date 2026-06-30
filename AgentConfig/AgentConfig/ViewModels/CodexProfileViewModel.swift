//
//  CodexProfileViewModel.swift
//  AgentConfig
//

import Combine
import Foundation

final class CodexProfileViewModel: ObservableObject {

    private static let profileNameMaxLength = 10

    @Published var profiles: [CodexProfile] = []
    @Published var selectedProfileID: UUID?
    @Published var lastErrorMessage: String?
    @Published var lastAppliedProfileName: String?
    @Published private(set) var didFinishInitialLoad: Bool = false

    private let service: CodexProfileServiceProtocol
    private var persistTask: Task<Void, Never>?
    private var hasRestoredInitialSelection = false

    init(service: CodexProfileServiceProtocol? = nil) {
        self.service = service ?? CodexProfileService()
        Task { await loadProfiles() }
    }

    var selectedProfile: CodexProfile? {
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
            profiles = CodexProfile.defaultProfiles
            selectedProfileID = profiles.first?.id
            lastErrorMessage = error.localizedDescription
        }
        didFinishInitialLoad = true
    }

    func selectProfile(_ profile: CodexProfile) {
        guard selectedProfileID != profile.id else { return }
        selectedProfileID = profile.id
    }

    func restoreInitialSelectionIfNeeded(appViewModel: AppViewModel) -> Bool {
        guard didFinishInitialLoad, !hasRestoredInitialSelection else { return false }
        hasRestoredInitialSelection = true

        guard case .codexProfile(let id) = appViewModel.lastVisitedPage else { return false }
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

    func updateSelected(name: String? = nil, configText: String? = nil, authText: String? = nil, zshrcText: String? = nil) {
        guard let index = selectedIndex else { return }
        var didChange = false

        if let name {
            let truncatedName = String(name.prefix(Self.profileNameMaxLength))
            if profiles[index].name != truncatedName {
                profiles[index].name = truncatedName
                didChange = true
            }
        }
        if let configText, profiles[index].configText != configText {
            profiles[index].configText = configText
            didChange = true
        }
        if let authText, profiles[index].authText != authText {
            profiles[index].authText = authText
            didChange = true
        }
        if let zshrcText, profiles[index].zshrcText != zshrcText {
            profiles[index].zshrcText = zshrcText
            didChange = true
        }

        guard didChange else { return }
        profiles[index].isDirty = isProfileDirty(profiles[index])
        schedulePersistProfiles()
    }

    func updateSelectedEditorHeight(
        configEditorHeight: Double? = nil,
        authEditorHeight: Double? = nil,
        zshrcEditorHeight: Double? = nil
    ) {
        guard let index = selectedIndex else { return }
        var didChange = false

        if let configEditorHeight {
            if profiles[index].configEditorHeight != configEditorHeight {
                profiles[index].configEditorHeight = configEditorHeight
                didChange = true
            }
        }
        if let authEditorHeight {
            if profiles[index].authEditorHeight != authEditorHeight {
                profiles[index].authEditorHeight = authEditorHeight
                didChange = true
            }
        }
        if let zshrcEditorHeight {
            if profiles[index].zshrcEditorHeight != zshrcEditorHeight {
                profiles[index].zshrcEditorHeight = zshrcEditorHeight
                didChange = true
            }
        }

        guard didChange else { return }
        schedulePersistProfiles()
    }

    func addProfile() {
        guard let source = selectedProfile ?? profiles.first else { return }
        let profile = CodexProfile(
            name: "\(L10n.tr("profile.newName", value: "New Profile")) \(profiles.count + 1)",
            configText: source.configText,
            authText: source.authText,
            zshrcText: source.zshrcText,
            isDirty: true
        )
        profiles.append(profile)
        selectedProfileID = profile.id
        Task { await persistProfiles() }
    }

    func deleteProfile(id: UUID) -> Bool {
        guard profiles.count > 1 else {
            lastErrorMessage = L10n.tr("profile.codex.minCount", value: "At least one Codex Profile must be kept.")
            return false
        }
        guard let index = profiles.firstIndex(where: { $0.id == id }) else {
            lastErrorMessage = L10n.tr("profile.codex.notFound", value: "The Codex Profile to delete could not be found.")
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
            profiles[selectedIndex].appliedConfigText = selectedProfile.configText
            profiles[selectedIndex].appliedAuthText = selectedProfile.authText
            profiles[selectedIndex].appliedZshrcText = selectedProfile.zshrcText
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

    private var selectedIndex: Array<CodexProfile>.Index? {
        guard let selectedProfileID else { return nil }
        return profiles.firstIndex { $0.id == selectedProfileID }
    }

    private func isProfileDirty(_ profile: CodexProfile) -> Bool {
        normalizedProfileText(profile.configText) != normalizedProfileText(profile.appliedConfigText)
            || normalizedAuthJSON(profile.authText) != normalizedAuthJSON(profile.appliedAuthText)
            || normalizedProfileText(profile.zshrcText) != normalizedProfileText(profile.appliedZshrcText)
    }

    private func normalizedProfileText(_ text: String) -> String {
        text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func normalizedAuthJSON(_ text: String) -> String {
        let trimmedText = normalizedProfileText(text)
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

    private func schedulePersistProfiles() {
        persistTask?.cancel()
        persistTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 350_000_000)
            guard !Task.isCancelled else { return }
            await self?.persistProfiles()
        }
    }

}
