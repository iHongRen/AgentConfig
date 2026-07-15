//
//  ClaudeProfileEditorView.swift
//  AgentConfig
//

import SwiftUI

struct ClaudeProfileEditorView: View {

    @ObservedObject var viewModel: ClaudeProfileViewModel

    var body: some View {
        AgentProfileEditorView(profile: editorProfile)
    }

    private var editorProfile: AgentProfileEditorProfile? {
        guard let profile = viewModel.selectedProfile else { return nil }

        return AgentProfileEditorProfile(
            id: profile.id,
            name: profile.name,
            nameMaxLength: viewModel.profileNameMaxLength,
            status: profileStatus(for: profile),
            canDelete: viewModel.profiles.count > 1,
            deleteConfirmation: AgentProfileEditorDeleteConfirmation(
                title: L10n.tr("claude.deleteConfirmation.title", value: "Delete Claude Profile?"),
                message: L10n.format("claude.deleteConfirmation.message", value: "“%@” will be deleted. This will not modify any Claude config files already written to disk.", displayName(for: profile.name))
            ),
            fields: [
                AgentProfileEditorField(
                    id: "settings",
                    title: "~/.claude/settings.json",
                    language: "JSON",
                    helpText: L10n.tr("claude.field.settings.help", value: "Claude main config file. Applying writes the full contents to ~/.claude/settings.json."),
                    fileType: .json,
                    accentColor: Color(red: 0.18, green: 0.64, blue: 0.42),
                    defaultHeight: 220,
                    text: Binding(
                        get: { viewModel.profiles.first { $0.id == profile.id }?.settingsText ?? "" },
                        set: { viewModel.updateSelected(settingsText: $0) }
                    ),
                    persistedHeight: profile.settingsEditorHeight,
                    onPersistHeight: { viewModel.updateSelectedEditorHeight(settingsEditorHeight: $0) }
                ),
                AgentProfileEditorField(
                    id: "claude-json",
                    title: "~/.claude.json",
                    language: "JSON",
                    helpText: L10n.tr("claude.field.state.help", value: "Shows hasCompletedOnboarding by default. You can freely edit other fields. Applying deep-merges into the current ~/.claude.json instead of replacing the whole file."),
                    fileType: .json,
                    accentColor: Color(red: 0.18, green: 0.64, blue: 0.42),
                    defaultHeight: 220,
                    text: Binding(
                        get: { viewModel.profiles.first { $0.id == profile.id }?.claudeJSONText ?? "" },
                        set: { viewModel.updateSelected(claudeJSONText: $0) }
                    ),
                    persistedHeight: profile.claudeJSONEditorHeight,
                    onPersistHeight: { viewModel.updateSelectedEditorHeight(claudeJSONEditorHeight: $0) }
                ),
                AgentProfileEditorField(
                    id: "zshrc",
                    title: "~/.zshrc",
                    language: "Shell",
                    helpText: L10n.tr("claude.field.zshrc.help", value: "Only manages the AgentConfig Claude Profile block and will not overwrite the full ~/.zshrc."),
                    fileType: .shell,
                    accentColor: Color(red: 0.46, green: 0.40, blue: 0.90),
                    defaultHeight: 150,
                    text: Binding(
                        get: { viewModel.profiles.first { $0.id == profile.id }?.zshrcText ?? "" },
                        set: { viewModel.updateSelected(zshrcText: $0) }
                    ),
                    persistedHeight: profile.zshrcEditorHeight,
                    onPersistHeight: { viewModel.updateSelectedEditorHeight(zshrcEditorHeight: $0) }
                )
            ],
            updateName: { viewModel.updateSelected(name: $0) },
            delete: {
                if viewModel.deleteProfile(id: profile.id) {
                    return .success(L10n.tr("profile.deleted", value: "Profile deleted"))
                }
                return .failure(viewModel.lastErrorMessage ?? L10n.tr("profile.deleteFailed", value: "Delete failed"))
            },
            apply: {
                let success = await viewModel.applySelected()
                if success {
                    return .success(L10n.tr("profile.applied", value: "Profile applied"))
                }
                return .failure(viewModel.lastErrorMessage ?? L10n.tr("profile.applyFailed", value: "Apply failed"))
            }
        )
    }

    private func profileStatus(for profile: ClaudeProfile) -> AgentProfileEditorStatus {
        if profile.isDirty {
            return AgentProfileEditorStatus(text: L10n.tr("profile.status.modified", value: "Unapplied Changes"), color: .orange)
        }
        if profile.isActive && viewModel.isDiskOutOfSync {
            return AgentProfileEditorStatus(text: L10n.tr("profile.status.external", value: "External Changes"), color: .red)
        }
        if profile.isActive {
            return AgentProfileEditorStatus(text: L10n.tr("profile.status.active", value: "Active"), color: .green)
        }
        return AgentProfileEditorStatus(text: L10n.tr("profile.status.ready", value: "Ready to Apply"), color: .secondary)
    }

    private func displayName(for name: String) -> String {
        name.isEmpty ? L10n.tr("profile.defaultName", value: "Untitled Profile") : name
    }
}
