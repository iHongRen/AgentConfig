//
//  CodexProfileViewModel.swift
//  AgentConfig
//

import Combine
import Foundation

final class CodexProfileViewModel: ObservableObject {

    @Published var profiles: [CodexProfile] = []
    @Published var selectedProfileID: UUID?
    @Published var lastErrorMessage: String?
    @Published var lastAppliedProfileName: String?

    private let service: CodexProfileServiceProtocol
    private var persistTask: Task<Void, Never>?

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
            profiles = loadedProfiles
            selectedProfileID = selectedProfileID ?? loadedProfiles.first(where: \.isActive)?.id ?? loadedProfiles.first?.id
        } catch {
            profiles = CodexProfile.defaultProfiles
            selectedProfileID = profiles.first?.id
            lastErrorMessage = error.localizedDescription
        }
    }

    func selectProfile(_ profile: CodexProfile) {
        guard selectedProfileID != profile.id else { return }
        selectedProfileID = profile.id
    }

    func clearSelection() {
        guard selectedProfileID != nil else { return }
        selectedProfileID = nil
    }

    func updateSelected(name: String? = nil, configText: String? = nil, authText: String? = nil, zshrcText: String? = nil) {
        guard let index = selectedIndex else { return }
        var didChange = false

        if let name {
            let truncatedName = String(name.prefix(15))
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
        profiles[index].isDirty = true
        schedulePersistProfiles()
    }

    func addProfile() {
        guard let source = selectedProfile ?? profiles.first else { return }
        let profile = CodexProfile(
            name: "新配置 \(profiles.count + 1)",
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
            lastErrorMessage = "至少需要保留一个 Codex Profile。"
            return false
        }
        guard let index = profiles.firstIndex(where: { $0.id == id }) else {
            lastErrorMessage = "未找到要删除的 Codex Profile。"
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
        if let validationError = validate(profile: selectedProfile) {
            lastErrorMessage = validationError
            return false
        }

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

    func validateSelected() -> String? {
        guard let selectedProfile else { return "未选择 Profile" }
        return validate(profile: selectedProfile)
    }

    private var selectedIndex: Array<CodexProfile>.Index? {
        guard let selectedProfileID else { return nil }
        return profiles.firstIndex { $0.id == selectedProfileID }
    }

    private func validate(profile: CodexProfile) -> String? {
        if profile.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return "配置名称不能为空。"
        }
        if profile.configText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return "config.toml 不能为空。"
        }

        do {
            let data = Data(profile.authText.utf8)
            let object = try JSONSerialization.jsonObject(with: data)
            guard object is [String: Any] else {
                return "auth.json 必须是 JSON object。"
            }
        } catch {
            return "auth.json 不是合法 JSON：\(error.localizedDescription)"
        }

        return nil
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
