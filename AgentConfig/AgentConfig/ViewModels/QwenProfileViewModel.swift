//
//  QwenProfileViewModel.swift
//  AgentConfig
//

import Foundation

final class QwenProfileViewModel: AgentProfileCollectionViewModel<QwenProfile> {

    private static let profileNameMaxLength = 20

    init(service: QwenProfileServiceProtocol? = nil) {
        let resolvedService = service ?? QwenProfileService()

        super.init(
            configuration: AgentProfileCollectionConfiguration(
                profileNameMaxLength: Self.profileNameMaxLength,
                loadProfiles: { try await resolvedService.loadProfiles() },
                saveProfiles: { try await resolvedService.saveProfiles($0) },
                applyProfile: { try await resolvedService.apply(profile: $0) },
                fallbackProfiles: { _ in QwenProfile.defaultProfiles },
                isProfileDirty: Self.isProfileDirty,
                markProfileApplied: { profile, selectedProfile in
                    profile.appliedSettingsText = selectedProfile.settingsText
                    profile.appliedEnvText = selectedProfile.envText
                    profile.appliedZshrcText = selectedProfile.zshrcText
                },
                makeNewProfile: { source, profileCount in
                    QwenProfile(
                        name: "\(L10n.tr("profile.newName", value: "New Profile")) \(profileCount + 1)",
                        settingsText: source.settingsText,
                        envText: source.envText,
                        zshrcText: source.zshrcText,
                        isDirty: true
                    )
                },
                duplicateProfile: { source in
                    QwenProfile(
                        name: "\(source.name) \(L10n.tr("profile.copySuffix", value: "Copy"))",
                        settingsText: source.settingsText,
                        envText: source.envText,
                        zshrcText: source.zshrcText,
                        appliedSettingsText: source.appliedSettingsText,
                        appliedEnvText: source.appliedEnvText,
                        appliedZshrcText: source.appliedZshrcText,
                        isActive: false,
                        isDirty: source.isDirty
                    )
                },
                lastVisitedProfileID: { page in
                    guard case .qwenProfile(let id) = page else { return nil }
                    return id
                },
                minimumProfileCountMessage: L10n.tr("profile.qwen.minCount", value: "At least one Qwen Profile must be kept."),
                profileNotFoundMessage: L10n.tr("profile.qwen.notFound", value: "The Qwen Profile to delete could not be found."),
                readDiskContents: { try await resolvedService.readDiskContents() },
                isProfileOutOfSync: Self.isProfileOutOfSync,
                watchedFileURLs: { resolvedService.targetFileURLs() }
            )
        )
    }

    func updateSelected(
        name: String? = nil,
        settingsText: String? = nil,
        envText: String? = nil,
        zshrcText: String? = nil
    ) {
        updateSelectedProfile { profile in
            var didChange = false

            if let name {
                let truncatedName = truncatedProfileName(name)
                if profile.name != truncatedName {
                    profile.name = truncatedName
                    didChange = true
                }
            }
            if let settingsText, profile.settingsText != settingsText {
                profile.settingsText = settingsText
                didChange = true
            }
            if let envText, profile.envText != envText {
                profile.envText = envText
                didChange = true
            }
            if let zshrcText, profile.zshrcText != zshrcText {
                profile.zshrcText = zshrcText
                didChange = true
            }

            return didChange
        }
    }

    func updateSelectedEditorHeight(
        settingsEditorHeight: Double? = nil,
        envEditorHeight: Double? = nil,
        zshrcEditorHeight: Double? = nil
    ) {
        updateSelectedProfile(recomputeDirtyState: false) { profile in
            var didChange = false

            if let settingsEditorHeight, profile.settingsEditorHeight != settingsEditorHeight {
                profile.settingsEditorHeight = settingsEditorHeight
                didChange = true
            }
            if let envEditorHeight, profile.envEditorHeight != envEditorHeight {
                profile.envEditorHeight = envEditorHeight
                didChange = true
            }
            if let zshrcEditorHeight, profile.zshrcEditorHeight != zshrcEditorHeight {
                profile.zshrcEditorHeight = zshrcEditorHeight
                didChange = true
            }

            return didChange
        }
    }

    nonisolated private static func isProfileDirty(_ profile: QwenProfile) -> Bool {
        ProfileContentNormalizer.json(profile.settingsText) != ProfileContentNormalizer.json(profile.appliedSettingsText)
            || ProfileContentNormalizer.text(profile.envText) != ProfileContentNormalizer.text(profile.appliedEnvText)
            || ProfileContentNormalizer.text(profile.zshrcText) != ProfileContentNormalizer.text(profile.appliedZshrcText)
    }

    nonisolated private static func isProfileOutOfSync(_ profile: QwenProfile, _ disk: ProfileDiskContents) -> Bool {
        ProfileContentNormalizer.json(profile.appliedSettingsText) != ProfileContentNormalizer.json(disk.configText ?? "")
            || ProfileContentNormalizer.text(profile.appliedEnvText) != ProfileContentNormalizer.text(disk.authText ?? "")
            || ProfileContentNormalizer.text(profile.appliedZshrcText) != ProfileContentNormalizer.text(disk.zshrcText ?? "")
    }
}
