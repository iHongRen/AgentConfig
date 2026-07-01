//
//  ClaudeProfileViewModel.swift
//  AgentConfig
//

import Foundation

final class ClaudeProfileViewModel: AgentProfileCollectionViewModel<ClaudeProfile> {

    private static let profileNameMaxLength = 10

    init(service: ClaudeProfileServiceProtocol? = nil) {
        let resolvedService = service ?? ClaudeProfileService()

        super.init(
            configuration: AgentProfileCollectionConfiguration(
                profileNameMaxLength: Self.profileNameMaxLength,
                loadProfiles: { try await resolvedService.loadProfiles() },
                saveProfiles: { try await resolvedService.saveProfiles($0) },
                applyProfile: { try await resolvedService.apply(profile: $0) },
                fallbackProfiles: { _ in [Self.makeFallbackProfile()] },
                isProfileDirty: Self.isProfileDirty,
                markProfileApplied: { profile, selectedProfile in
                    profile.appliedSettingsText = selectedProfile.settingsText
                    profile.appliedClaudeJSONText = selectedProfile.claudeJSONText
                    profile.appliedZshrcText = selectedProfile.zshrcText
                },
                makeNewProfile: { source, profileCount in
                    ClaudeProfile(
                        name: "\(L10n.tr("profile.newName", value: "New Profile")) \(profileCount + 1)",
                        settingsText: source.settingsText,
                        claudeJSONText: source.claudeJSONText,
                        zshrcText: source.zshrcText,
                        isDirty: true
                    )
                },
                lastVisitedProfileID: { page in
                    guard case .claudeProfile(let id) = page else { return nil }
                    return id
                },
                minimumProfileCountMessage: L10n.tr("profile.claude.minCount", value: "At least one Claude Profile must be kept."),
                profileNotFoundMessage: L10n.tr("profile.claude.notFound", value: "The Claude Profile to delete could not be found.")
            )
        )
    }

    func updateSelected(
        name: String? = nil,
        settingsText: String? = nil,
        claudeJSONText: String? = nil,
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
            if let claudeJSONText, profile.claudeJSONText != claudeJSONText {
                profile.claudeJSONText = claudeJSONText
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
        claudeJSONEditorHeight: Double? = nil,
        zshrcEditorHeight: Double? = nil
    ) {
        updateSelectedProfile(recomputeDirtyState: false) { profile in
            var didChange = false

            if let settingsEditorHeight, profile.settingsEditorHeight != settingsEditorHeight {
                profile.settingsEditorHeight = settingsEditorHeight
                didChange = true
            }
            if let claudeJSONEditorHeight, profile.claudeJSONEditorHeight != claudeJSONEditorHeight {
                profile.claudeJSONEditorHeight = claudeJSONEditorHeight
                didChange = true
            }
            if let zshrcEditorHeight, profile.zshrcEditorHeight != zshrcEditorHeight {
                profile.zshrcEditorHeight = zshrcEditorHeight
                didChange = true
            }

            return didChange
        }
    }

    nonisolated private static func isProfileDirty(_ profile: ClaudeProfile) -> Bool {
        ProfileContentNormalizer.json(profile.settingsText) != ProfileContentNormalizer.json(profile.appliedSettingsText)
            || ProfileContentNormalizer.json(profile.claudeJSONText) != ProfileContentNormalizer.json(profile.appliedClaudeJSONText)
            || ProfileContentNormalizer.text(profile.zshrcText) != ProfileContentNormalizer.text(profile.appliedZshrcText)
    }

    private static func makeFallbackProfile() -> ClaudeProfile {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let settingsURL = home.appendingPathComponent(".claude", isDirectory: true).appendingPathComponent("settings.json")

        let settingsText = (try? String(contentsOf: settingsURL, encoding: .utf8)) ?? "{}"
        let claudeJSONText = ClaudeProfile.defaultClaudeJSONText

        return ClaudeProfile(
            name: L10n.tr("profile.newName", value: "New Profile"),
            settingsText: settingsText,
            claudeJSONText: claudeJSONText,
            zshrcText: ClaudeProfile.defaultZshrcText,
            appliedSettingsText: settingsText,
            appliedClaudeJSONText: claudeJSONText,
            appliedZshrcText: ClaudeProfile.defaultZshrcText,
            isActive: true
        )
    }
}
