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
                title: "删除 Codex Profile？",
                message: "将删除“\(displayName(for: profile.name))”。此操作不会修改已经写入磁盘的 Codex 配置文件。"
            ),
            fields: [
                AgentProfileEditorField(
                    id: "config",
                    title: "~/.codex/config.toml",
                    language: "TOML",
                    helpText: "Codex 的主配置文件。应用时会整体写入磁盘上的 ~/.codex/config.toml。",
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
                    helpText: "Codex 的认证信息文件。应用时会整体写入 ~/.codex/auth.json，请确认内容正确。",
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
                    helpText: "仅管理 AgentConfig Codex Profile 标记块，不会覆盖整个 ~/.zshrc。",
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
                    return .success("已删除配置")
                }
                return .failure(viewModel.lastErrorMessage ?? "删除失败")
            },
            apply: {
                let success = await viewModel.applySelected()
                if success {
                    return .success("已应用配置")
                }
                return .failure(viewModel.lastErrorMessage ?? "应用失败")
            }
        )
    }

    private func profileStatus(for profile: CodexProfile) -> AgentProfileEditorStatus {
        if profile.isDirty {
            return AgentProfileEditorStatus(text: "未应用修改", color: .orange)
        }
        if profile.isActive {
            return AgentProfileEditorStatus(text: "当前生效", color: .green)
        }
        return AgentProfileEditorStatus(text: "可应用", color: .secondary)
    }

    private func displayName(for name: String) -> String {
        name.isEmpty ? "未命名配置" : name
    }
}
