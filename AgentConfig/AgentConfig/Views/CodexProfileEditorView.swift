//
//  CodexProfileEditorView.swift
//  AgentConfig
//

import SwiftUI

struct CodexProfileEditorView: View {

    @ObservedObject var viewModel: CodexProfileViewModel

    var body: some View {
        AgentProfileEditorView(profile: editorProfile)
    }

    private var editorProfile: AgentProfileEditorProfile? {
        guard let profile = viewModel.selectedProfile else { return nil }

        return AgentProfileEditorProfile(
            id: profile.id,
            name: profile.name,
            nameMaxLength: 10,
            status: profileStatus(for: profile),
            canDelete: viewModel.profiles.count > 1,
            deleteConfirmation: AgentProfileEditorDeleteConfirmation(
                title: L10n.tr("codex.deleteConfirmation.title", value: "Delete Codex Profile?"),
                message: L10n.format("codex.deleteConfirmation.message", value: "“%@” will be deleted. This will not modify any Codex config files already written to disk.", displayName(for: profile.name))
            ),
            fields: [
                AgentProfileEditorField(
                    id: "config",
                    title: "~/.codex/config.toml",
                    language: "TOML",
                    helpText: L10n.tr("codex.field.config.help", value: "Codex main config file. Applying writes the full contents to ~/.codex/config.toml."),
                    fileType: .toml,
                    accentColor: Color(red: 0.91, green: 0.49, blue: 0.18),
                    defaultHeight: 220,
                    text: Binding(
                        get: { viewModel.profiles.first { $0.id == profile.id }?.configText ?? "" },
                        set: { viewModel.updateSelected(configText: $0) }
                    ),
                    persistedHeight: profile.configEditorHeight,
                    onPersistHeight: { viewModel.updateSelectedEditorHeight(configEditorHeight: $0) }
                ),
                AgentProfileEditorField(
                    id: "auth",
                    title: "~/.codex/auth.json",
                    language: "JSON",
                    helpText: L10n.tr("codex.field.auth.help", value: "Codex authentication file. Applying writes the full contents to ~/.codex/auth.json. Make sure the contents are correct."),
                    fileType: .json,
                    accentColor: Color(red: 0.18, green: 0.64, blue: 0.42),
                    defaultHeight: 150,
                    text: Binding(
                        get: { viewModel.profiles.first { $0.id == profile.id }?.authText ?? "" },
                        set: { viewModel.updateSelected(authText: $0) }
                    ),
                    persistedHeight: profile.authEditorHeight,
                    onPersistHeight: { viewModel.updateSelectedEditorHeight(authEditorHeight: $0) }
                ),
                AgentProfileEditorField(
                    id: "zshrc",
                    title: "~/.zshrc",
                    language: "Shell",
                    helpText: L10n.tr("codex.field.zshrc.help", value: "Only manages the AgentConfig Codex Profile block and will not overwrite the full ~/.zshrc."),
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

    private func profileStatus(for profile: CodexProfile) -> AgentProfileEditorStatus {
        if profile.isDirty {
            return AgentProfileEditorStatus(text: L10n.tr("profile.status.modified", value: "Unapplied Changes"), color: .orange)
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
