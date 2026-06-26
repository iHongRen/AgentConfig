//
//  SettingsView.swift
//  AgentConfig
//
//  Created by cxy on 2026/5/11.
//

import SwiftUI

/// 应用设置视图
///
/// 提供以下设置项：
/// - 外观模式：浅色 / 深色 / 跟随系统
/// - 界面语言：English / 简体中文 / 跟随系统
///
/// 每次设置变更后立即调用 `AppViewModel.updateSettings(_:)` 持久化。
struct SettingsView: View {

    @EnvironmentObject var appViewModel: AppViewModel

    // 本地副本，用于绑定 Picker / Toggle，变更时同步到 ViewModel
    @State private var appearanceMode: AppearanceMode = .system
    @State private var language: AppLanguage = .system

    var body: some View {
        Form {
            // MARK: - 外观
            Section {
                Picker(
                    NSLocalizedString("settings.appearance", value: "Appearance", comment: "Appearance setting label"),
                    selection: $appearanceMode
                ) {
                    ForEach(AppearanceMode.allCases, id: \.self) { mode in
                        Text(mode.displayName).tag(mode)
                    }
                }
                .onChange(of: appearanceMode) { _, newValue in
                    saveSettings(appearanceMode: newValue)
                }
            }

            // MARK: - 语言
            Section {
                Picker(
                    NSLocalizedString("settings.language", value: "Language", comment: "Language setting label"),
                    selection: $language
                ) {
                    ForEach(AppLanguage.allCases, id: \.self) { lang in
                        Text(lang.displayName).tag(lang)
                    }
                }
                .onChange(of: language) { _, newValue in
                    saveSettings(language: newValue)
                }
            }

        }
        .formStyle(.grouped)
        .frame(width: 400)
        .padding()
        .onAppear {
            // 从 ViewModel 加载当前设置到本地状态
            appearanceMode = appViewModel.settings.appearanceMode
            language = appViewModel.settings.language
        }
        .navigationTitle(
            NSLocalizedString("settings.title", value: "Settings", comment: "Settings window title")
        )
    }

    // MARK: - Private Helpers

    /// 将当前本地状态（含可选覆盖值）构建为新的 AppSettings 并保存
    private func saveSettings(
        appearanceMode: AppearanceMode? = nil,
        language: AppLanguage? = nil
    ) {
        var updated = appViewModel.settings
        updated.appearanceMode = appearanceMode ?? self.appearanceMode
        updated.language = language ?? self.language
        appViewModel.updateSettings(updated)
    }
}
