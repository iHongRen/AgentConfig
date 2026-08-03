//
//  OpenCodeProfileViewModel.swift
//  AgentConfig
//

import Foundation

final class OpenCodeProfileViewModel: AgentProfileCollectionViewModel<OpenCodeProfile> {

    private static let profileNameMaxLength = 20

    init(service: OpenCodeProfileServiceProtocol? = nil) {
        let resolvedService = service ?? OpenCodeProfileService()

        super.init(
            configuration: AgentProfileCollectionConfiguration(
                profileNameMaxLength: Self.profileNameMaxLength,
                loadProfiles: { try await resolvedService.loadProfiles() },
                saveProfiles: { try await resolvedService.saveProfiles($0) },
                applyProfile: { try await resolvedService.apply(profile: $0) },
                fallbackProfiles: { _ in OpenCodeProfile.defaultProfiles },
                isProfileDirty: Self.isProfileDirty,
                markProfileApplied: { profile, selectedProfile in
                    profile.appliedConfigText = selectedProfile.configText
                    profile.appliedAuthText = selectedProfile.authText
                    profile.appliedZshrcText = selectedProfile.zshrcText
                },
                makeNewProfile: { source, profileCount in
                    OpenCodeProfile(
                        name: "\(L10n.tr("profile.newName", value: "New Profile")) \(profileCount + 1)",
                        configText: source.configText,
                        authText: source.authText,
                        zshrcText: source.zshrcText,
                        isDirty: true
                    )
                },
                duplicateProfile: { source in
                    OpenCodeProfile(
                        name: "\(source.name) \(L10n.tr("profile.copySuffix", value: "Copy"))",
                        configText: source.configText,
                        authText: source.authText,
                        zshrcText: source.zshrcText,
                        appliedConfigText: source.appliedConfigText,
                        appliedAuthText: source.appliedAuthText,
                        appliedZshrcText: source.appliedZshrcText,
                        isActive: false,
                        isDirty: source.isDirty
                    )
                },
                lastVisitedProfileID: { page in
                    guard case .opencodeProfile(let id) = page else { return nil }
                    return id
                },
                minimumProfileCountMessage: L10n.tr("profile.opencode.minCount", value: "At least one OpenCode Profile must be kept."),
                profileNotFoundMessage: L10n.tr("profile.opencode.notFound", value: "The OpenCode Profile to delete could not be found."),
                readDiskContents: { try await resolvedService.readDiskContents() },
                isProfileOutOfSync: Self.isProfileOutOfSync,
                watchedFileURLs: { resolvedService.targetFileURLs() }
            )
        )
    }

    func updateSelected(name: String? = nil, configText: String? = nil, authText: String? = nil, zshrcText: String? = nil) {
        updateSelectedProfile { profile in
            var didChange = false

            if let name {
                let truncatedName = truncatedProfileName(name)
                if profile.name != truncatedName {
                    profile.name = truncatedName
                    didChange = true
                }
            }
            if let configText, profile.configText != configText {
                profile.configText = configText
                didChange = true
            }
            if let authText, profile.authText != authText {
                profile.authText = authText
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
        configEditorHeight: Double? = nil,
        authEditorHeight: Double? = nil,
        zshrcEditorHeight: Double? = nil
    ) {
        updateSelectedProfile(recomputeDirtyState: false) { profile in
            var didChange = false

            if let configEditorHeight, profile.configEditorHeight != configEditorHeight {
                profile.configEditorHeight = configEditorHeight
                didChange = true
            }
            if let authEditorHeight, profile.authEditorHeight != authEditorHeight {
                profile.authEditorHeight = authEditorHeight
                didChange = true
            }
            if let zshrcEditorHeight, profile.zshrcEditorHeight != zshrcEditorHeight {
                profile.zshrcEditorHeight = zshrcEditorHeight
                didChange = true
            }

            return didChange
        }
    }

    nonisolated private static func isProfileDirty(_ profile: OpenCodeProfile) -> Bool {
        ProfileContentNormalizer.json(profile.configText) != ProfileContentNormalizer.json(profile.appliedConfigText)
            || ProfileContentNormalizer.json(profile.authText) != ProfileContentNormalizer.json(profile.appliedAuthText)
            || ProfileContentNormalizer.text(profile.zshrcText) != ProfileContentNormalizer.text(profile.appliedZshrcText)
    }

    nonisolated private static func isProfileOutOfSync(_ profile: OpenCodeProfile, _ disk: ProfileDiskContents) -> Bool {
        ProfileContentNormalizer.json(profile.appliedConfigText) != ProfileContentNormalizer.json(disk.configText ?? "")
            || ProfileContentNormalizer.json(profile.appliedAuthText) != ProfileContentNormalizer.json(disk.authText ?? "")
            || ProfileContentNormalizer.text(profile.appliedZshrcText) != ProfileContentNormalizer.text(disk.zshrcText ?? "")
    }
}
