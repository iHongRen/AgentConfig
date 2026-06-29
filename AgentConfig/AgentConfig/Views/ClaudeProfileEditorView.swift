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
            nameMaxLength: 10,
            status: profileStatus(for: profile),
            canDelete: viewModel.profiles.count > 1,
            deleteConfirmation: AgentProfileEditorDeleteConfirmation(
                title: "删除 Claude Profile？",
                message: "将删除“\(displayName(for: profile.name))”。此操作不会修改已经写入磁盘的 Claude 配置文件。"
            ),
            fields: [
                AgentProfileEditorField(
                    id: "settings",
                    title: "~/.claude/settings.json",
                    language: "JSON",
                    helpText: "Claude 的主配置文件。应用时会整体写入磁盘上的 ~/.claude/settings.json。",
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
                    helpText: "默认展示 hasCompletedOnboarding，可自由编辑其他字段。应用时会与当前 ~/.claude.json 做深度合并，而不是直接整文件覆盖。",
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
                    helpText: "仅管理 AgentConfig Claude Profile 标记块，不会覆盖整个 ~/.zshrc。",
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

    private func profileStatus(for profile: ClaudeProfile) -> AgentProfileEditorStatus {
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
